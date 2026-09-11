import 'dart:convert';

/// One saved identification (FR6).
///
/// **No photograph is stored.** The record keeps the derived data only: what was predicted, how
/// confident the model was, what the quality gate measured, and which model produced it. Keeping
/// the image would mean holding a copy of the user's photo on disk indefinitely, which this
/// project does not need for any feature, so the path is not persisted. The reasoning is recorded
/// in docs/history.md.
class HistoryRecord {
  const HistoryRecord({
    this.id,
    required this.createdAt,
    required this.topSlug,
    required this.topCommonName,
    required this.topScientificName,
    required this.topConfidence,
    required this.runnerUpSlug,
    required this.runnerUpConfidence,
    required this.wasUncertain,
    required this.confidenceThreshold,
    required this.confidencePolicyValidated,
    required this.qualityBrightness,
    required this.qualityLaplacianVariance,
    required this.qualityAccepted,
    required this.modelLabel,
    required this.modelAsset,
  });

  /// SQLite row id; null until saved.
  final int? id;
  final DateTime createdAt;

  final String topSlug;
  final String topCommonName;
  final String topScientificName;
  final double topConfidence;

  final String runnerUpSlug;
  final double runnerUpConfidence;

  /// True when the confidence policy chose "Uncertain" instead of asserting a species.
  final bool wasUncertain;
  final double confidenceThreshold;

  /// Whether that threshold came from a documented validation procedure. False for the current
  /// prototype, and stored per record so an old row is never mistaken for a calibrated result.
  final bool confidencePolicyValidated;

  final double qualityBrightness;
  final double qualityLaplacianVariance;
  final bool qualityAccepted;

  /// Human-readable model name, e.g. `fieldsnap_float.tflite`.
  final String modelLabel;
  final String modelAsset;

  HistoryRecord copyWith({int? id}) => HistoryRecord(
        id: id ?? this.id,
        createdAt: createdAt,
        topSlug: topSlug,
        topCommonName: topCommonName,
        topScientificName: topScientificName,
        topConfidence: topConfidence,
        runnerUpSlug: runnerUpSlug,
        runnerUpConfidence: runnerUpConfidence,
        wasUncertain: wasUncertain,
        confidenceThreshold: confidenceThreshold,
        confidencePolicyValidated: confidencePolicyValidated,
        qualityBrightness: qualityBrightness,
        qualityLaplacianVariance: qualityLaplacianVariance,
        qualityAccepted: qualityAccepted,
        modelLabel: modelLabel,
        modelAsset: modelAsset,
      );

  Map<String, Object?> toRow() => <String, Object?>{
        if (id != null) 'id': id,
        'created_at': createdAt.toIso8601String(),
        'top_slug': topSlug,
        'top_common_name': topCommonName,
        'top_scientific_name': topScientificName,
        'top_confidence': topConfidence,
        'runner_up_slug': runnerUpSlug,
        'runner_up_confidence': runnerUpConfidence,
        'was_uncertain': wasUncertain ? 1 : 0,
        'confidence_threshold': confidenceThreshold,
        'confidence_policy_validated': confidencePolicyValidated ? 1 : 0,
        'quality_brightness': qualityBrightness,
        'quality_laplacian_variance': qualityLaplacianVariance,
        'quality_accepted': qualityAccepted ? 1 : 0,
        'model_label': modelLabel,
        'model_asset': modelAsset,
      };

  static HistoryRecord fromRow(Map<String, Object?> row) => HistoryRecord(
        id: row['id'] as int?,
        createdAt: DateTime.parse(row['created_at']! as String),
        topSlug: row['top_slug']! as String,
        topCommonName: row['top_common_name']! as String,
        topScientificName: row['top_scientific_name']! as String,
        topConfidence: (row['top_confidence']! as num).toDouble(),
        runnerUpSlug: (row['runner_up_slug']! as String),
        runnerUpConfidence: (row['runner_up_confidence']! as num).toDouble(),
        wasUncertain: (row['was_uncertain']! as int) == 1,
        confidenceThreshold: (row['confidence_threshold']! as num).toDouble(),
        confidencePolicyValidated: (row['confidence_policy_validated']! as int) == 1,
        qualityBrightness: (row['quality_brightness']! as num).toDouble(),
        qualityLaplacianVariance: (row['quality_laplacian_variance']! as num).toDouble(),
        qualityAccepted: (row['quality_accepted']! as int) == 1,
        modelLabel: row['model_label']! as String,
        modelAsset: row['model_asset']! as String,
      );

  /// Compact line for the history list and for logs.
  String get summary {
    final String species = wasUncertain ? 'Uncertain' : topCommonName;
    return '$species  ${(topConfidence * 100).toStringAsFixed(0)}%  '
        '($modelLabel, threshold '
        '${(confidenceThreshold * 100).toStringAsFixed(0)}%'
        '${confidencePolicyValidated ? '' : ', unvalidated'})';
  }

  Map<String, Object?> toJson() => <String, Object?>{...toRow()};
}

/// Storage boundary for history. The UI and ViewModel depend on this, never on SQL.
abstract class HistoryRepository {
  Future<List<HistoryRecord>> loadAll({int limit = 100});

  /// Inserts and returns the record with its assigned id.
  Future<HistoryRecord> save(HistoryRecord record);

  /// Deletes one record. Returns true when a row was removed.
  Future<bool> delete(int id);

  /// Deletes everything. Used by the "clear history" affordance and by tests.
  Future<int> deleteAll();

  Future<int> count();
}

/// In-memory implementation for tests and for a platform without sqflite.
class InMemoryHistoryRepository implements HistoryRepository {
  InMemoryHistoryRepository();

  final List<HistoryRecord> _records = <HistoryRecord>[];
  int _nextId = 1;

  @override
  Future<List<HistoryRecord>> loadAll({int limit = 100}) async {
    final List<HistoryRecord> sorted = List<HistoryRecord>.from(_records)
      ..sort((HistoryRecord a, HistoryRecord b) => b.createdAt.compareTo(a.createdAt));
    return sorted.take(limit).toList(growable: false);
  }

  @override
  Future<HistoryRecord> save(HistoryRecord record) async {
    final HistoryRecord stored = record.copyWith(id: _nextId++);
    _records.add(stored);
    return stored;
  }

  @override
  Future<bool> delete(int id) async {
    final int before = _records.length;
    _records.removeWhere((HistoryRecord record) => record.id == id);
    return _records.length != before;
  }

  @override
  Future<int> deleteAll() async {
    final int removed = _records.length;
    _records.clear();
    return removed;
  }

  @override
  Future<int> count() async => _records.length;

  /// Test helper: the stored rows, for assertions about what was persisted.
  List<HistoryRecord> get debugRecords => List<HistoryRecord>.unmodifiable(_records);
}

/// Serialises a record for a log line without leaking anything unexpected.
String describeRecordForLog(HistoryRecord record) => json.encode(record.toJson());
