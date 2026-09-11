import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'history_repository.dart';

/// SQLite-backed history (FR6).
///
/// Schema notes:
///  * no column stores a photograph or a file path to one — only derived values, per the
///    decision recorded in docs/history.md;
///  * the confidence threshold and its `is_validated` flag are stored per row, so a record made
///    with an older or uncalibrated threshold can never be read later as a calibrated result;
///  * timestamps are stored as ISO-8601 strings, which sort correctly and stay readable in a
///    database browser during review.
class SqfliteHistoryRepository implements HistoryRepository {
  SqfliteHistoryRepository._(this._db);

  final Database _db;

  static const int schemaVersion = 1;
  static const String tableName = 'history';

  static const String createTableSql = '''
CREATE TABLE $tableName (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  created_at TEXT NOT NULL,
  top_slug TEXT NOT NULL,
  top_common_name TEXT NOT NULL,
  top_scientific_name TEXT NOT NULL,
  top_confidence REAL NOT NULL,
  runner_up_slug TEXT NOT NULL,
  runner_up_confidence REAL NOT NULL,
  was_uncertain INTEGER NOT NULL,
  confidence_threshold REAL NOT NULL,
  confidence_policy_validated INTEGER NOT NULL,
  quality_brightness REAL NOT NULL,
  quality_laplacian_variance REAL NOT NULL,
  quality_accepted INTEGER NOT NULL,
  model_label TEXT NOT NULL,
  model_asset TEXT NOT NULL
)
''';

  /// Opens (and creates) the database. [path] defaults to the app's private databases folder.
  static Future<SqfliteHistoryRepository> open({String? path}) async {
    final String databasePath =
        path ?? p.join(await getDatabasesPath(), 'fieldsnap_history.db');
    final Database db = await openDatabase(
      databasePath,
      version: schemaVersion,
      onCreate: (Database db, int version) async {
        await db.execute(createTableSql);
      },
    );
    return SqfliteHistoryRepository._(db);
  }

  @override
  Future<List<HistoryRecord>> loadAll({int limit = 100}) async {
    final List<Map<String, Object?>> rows = await _db.query(
      tableName,
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(HistoryRecord.fromRow).toList(growable: false);
  }

  @override
  Future<HistoryRecord> save(HistoryRecord record) async {
    final int id = await _db.insert(tableName, record.toRow());
    return record.copyWith(id: id);
  }

  @override
  Future<bool> delete(int id) async {
    final int removed = await _db.delete(tableName, where: 'id = ?', whereArgs: <Object>[id]);
    return removed > 0;
  }

  @override
  Future<int> deleteAll() => _db.delete(tableName);

  @override
  Future<int> count() async {
    final List<Map<String, Object?>> rows =
        await _db.rawQuery('SELECT COUNT(*) AS c FROM $tableName');
    return (rows.first['c']! as int);
  }

  Future<void> close() => _db.close();
}
