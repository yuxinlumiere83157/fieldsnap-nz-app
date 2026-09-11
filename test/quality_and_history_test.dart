import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fieldsnap/services/confidence_policy.dart';
import 'package:fieldsnap/services/history_repository.dart';
import 'package:fieldsnap/services/quality_gate.dart';
import 'package:fieldsnap/services/species_cards.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Component tests for the FR2 gate, the FR4 policy, the FR5 cards and the FR6 repository.
void main() {
  img.Image checker({double luma = 0.6, int block = 8}) {
    final int base = (luma * 255).round().clamp(0, 255);
    final img.Image image = img.Image(width: 224, height: 224);
    for (int y = 0; y < 224; y++) {
      for (int x = 0; x < 224; x++) {
        final bool dark = ((x ~/ block + y ~/ block) % 2 == 0);
        final int value = dark ? (base * 0.15).round() : base;
        image.setPixelRgb(x, y, value, value, value);
      }
    }
    return image;
  }

  img.Image flat(int value) {
    final img.Image image = img.Image(width: 224, height: 224);
    for (int y = 0; y < 224; y++) {
      for (int x = 0; x < 224; x++) {
        image.setPixelRgb(x, y, value, value, value);
      }
    }
    return image;
  }

  group('quality gate (FR2)', () {
    test('a sharp, normally lit image passes and reports its metrics', () {
      final QualityDecision decision =
          const ImageQualityGate().evaluateDecoded(checker());
      expect(decision.isAcceptable, isTrue);
      expect(decision.metrics!.brightness, closeTo(0.345, 0.05));
      expect(decision.metrics!.laplacianVariance, greaterThan(250));
      expect(decision.explanation, contains('accepted'));
    });

    test('dark, bright and flat images fail for the right reason', () {
      expect(const ImageQualityGate().evaluateDecoded(checker(luma: 0.02)).kind,
          QualityFailureKind.tooDark);
      expect(const ImageQualityGate().evaluateDecoded(flat(250)).kind,
          QualityFailureKind.tooBright);
      expect(const ImageQualityGate().evaluateDecoded(flat(128)).kind,
          QualityFailureKind.tooBlurry);
    });

    test('the explanation carries the measured value and the threshold', () {
      final QualityDecision decision =
          const ImageQualityGate().evaluateDecoded(flat(128));
      expect(decision.measured, isNotNull);
      // The blur threshold is now the calibrated value (100.0); see the pinned-threshold test.
      expect(decision.threshold, const QualityGateConfig().minLaplacianVariance);
      expect(decision.explanation, contains('100'));
      expect(decision.explanation, contains('sharpness'));
    });

    test('an undecodable file is reported, not thrown', () {
      final QualityDecision decision =
          const ImageQualityGate().evaluate(Uint8List.fromList(<int>[1, 2, 3, 4]));
      expect(decision.isAcceptable, isFalse);
      expect(decision.kind, QualityFailureKind.undecodable);
    });

    test('thresholds are injectable, so a stricter gate changes the verdict', () {
      const QualityGateConfig strict = QualityGateConfig(minLaplacianVariance: 100000);
      final QualityDecision decision =
          const ImageQualityGate(strict).evaluateDecoded(checker());
      expect(decision.kind, QualityFailureKind.tooBlurry);
      expect(decision.threshold, 100000);
    });

    test('config serialises for the record', () {
      final Map<String, Object> json = const QualityGateConfig().toJson();
      expect(json['min_laplacian_variance'], const QualityGateConfig().minLaplacianVariance);
      expect(json['min_brightness'], const QualityGateConfig().minBrightness);
      expect(json['max_brightness'], const QualityGateConfig().maxBrightness);
    });
  });

  group('confidence policy (FR4)', () {
    const ConfidencePolicyConfig config = ConfidencePolicyConfig(
      acceptThreshold: 0.5,
      marginThreshold: 0.1,
      isValidated: true,
      provenance: 'unit test fixture',
    );

    test('a clear top candidate is accepted', () {
      final ConfidenceDecision decision =
          const ConfidencePolicy(config).decide(<double>[0.8, 0.1, 0.1]);
      expect(decision.verdict, ConfidenceVerdict.accept);
      expect(decision.topScore, 0.8);
    });

    test('a score below the threshold is uncertain', () {
      final ConfidenceDecision decision =
          const ConfidencePolicy(config).decide(<double>[0.4, 0.3, 0.3]);
      expect(decision.verdict, ConfidenceVerdict.uncertain);
      expect(decision.reason, contains('below the accept threshold'));
    });

    test('a narrow margin is uncertain even above the threshold', () {
      final ConfidenceDecision decision =
          const ConfidencePolicy(config).decide(<double>[0.52, 0.48]);
      expect(decision.verdict, ConfidenceVerdict.uncertain);
      expect(decision.reason, contains('too close'));
    });

    test('the margin rule can be disabled', () {
      const ConfidencePolicyConfig noMargin =
          ConfidencePolicyConfig(acceptThreshold: 0.5);
      final ConfidenceDecision decision =
          const ConfidencePolicy(noMargin).decide(<double>[0.52, 0.48]);
      expect(decision.verdict, ConfidenceVerdict.accept);
    });

    test('an empty score vector is uncertain rather than an error', () {
      final ConfidenceDecision decision = const ConfidencePolicy(config).decide(<double>[]);
      expect(decision.verdict, ConfidenceVerdict.uncertain);
      expect(decision.reason, contains('no scores'));
    });

    test('a single score has no runner-up and cannot trip the margin rule wrongly', () {
      final ConfidenceDecision decision =
          const ConfidencePolicy(config).decide(<double>[0.9]);
      expect(decision.verdict, ConfidenceVerdict.accept);
      expect(decision.runnerUpScore, 0.0);
    });

    test('the deployed policy is validated and records its provenance', () {
      final ConfidenceDecision decision =
          const ConfidencePolicy(config).decide(<double>[0.9, 0.05]);
      expect(decision.toJson()['config'], isA<Map<String, Object?>>());
      expect(config.isValidated, isTrue);
      // The app's default is now the calibrated configuration, with a stated provenance.
      expect(kDeployedConfidencePolicy.isValidated, isTrue);
      expect(kDeployedConfidencePolicy.provenance, contains('validation-split sweep'));
      expect(kDeployedConfidencePolicy.acceptThreshold, 0.37);
    });
  });

  group('species cards (FR5)', () {
    test('the bundled asset covers all 20 current model classes', () async {
      final String raw = File('assets/data/species_cards.json').readAsStringSync();
      final SpeciesCardRepository repository =
          SpeciesCardRepository.fromJsonString(raw);
      final String labels =
          File('assets/models/class_indices.json').readAsStringSync();
      final List<String> classes = _classesFrom(labels);

      expect(repository.length, 20);
      expect(repository.missingFor(classes), isEmpty,
          reason: 'every model label must have a learning card');
    });

    test('cards carry the fields FR5 requires', () {
      final SpeciesCardRepository repository = SpeciesCardRepository.fromJsonString(
        File('assets/data/species_cards.json').readAsStringSync(),
      );
      for (final String slug in repository.slugs) {
        final SpeciesCard card = repository.bySlug(slug)!;
        expect(card.commonName, isNotEmpty);
        expect(card.scientificName, isNotEmpty);
        expect(card.identification.length, greaterThan(20));
        expect(card.habitat, isNotEmpty);
        expect(<String>['native', 'introduced', 'pest'], contains(card.status));
        expect(<String>['bird', 'plant'], contains(card.group));
      }
    });

    test('an unknown label returns null instead of a invented species', () {
      final SpeciesCardRepository repository = SpeciesCardRepository.fromJsonString(
        File('assets/data/species_cards.json').readAsStringSync(),
      );
      expect(repository.bySlug('not_a_species'), isNull);
      expect(repository.missingFor(<String>['not_a_species']), <String>['not_a_species']);
    });

    test('a duplicate slug is rejected rather than silently overwriting', () {
      expect(
        () => SpeciesCardRepository.fromJsonString(
          '{"species":[{"slug":"a","common_name":"A","scientific_name":"A a","group":"bird",'
          '"maori_name":"","identification":"x","habitat":"y","status":"native"},'
          '{"slug":"a","common_name":"B","scientific_name":"B b","group":"bird",'
          '"maori_name":"","identification":"x","habitat":"y","status":"native"}]}',
        ),
        throwsStateError,
      );
    });
  });

  group('calibrated FR2 thresholds', () {
    calibratedThresholdsArePinned();
  });

  group('history repository (FR6)', () {
    HistoryRecord record({String name = 'kereru', bool uncertain = false}) => HistoryRecord(
          createdAt: DateTime(2026, 9, 11, 12),
          topSlug: name,
          topCommonName: name,
          topScientificName: 'Scientific name',
          topConfidence: 0.8,
          runnerUpSlug: 'tui',
          runnerUpConfidence: 0.1,
          wasUncertain: uncertain,
          confidenceThreshold: 0.45,
          confidencePolicyValidated: false,
          qualityBrightness: 0.5,
          qualityLaplacianVariance: 1200,
          qualityAccepted: true,
          modelLabel: 'fieldsnap_float.tflite',
          modelAsset: 'assets/models/fieldsnap_float.tflite',
        );

    test('save assigns an id and load returns the newest first', () async {
      final InMemoryHistoryRepository repository = InMemoryHistoryRepository();
      final HistoryRecord older = await repository.save(HistoryRecord(
        createdAt: DateTime(2026, 9, 11, 10),
        topSlug: 'tui',
        topCommonName: 'tui',
        topScientificName: 'Scientific name',
        topConfidence: 0.8,
        runnerUpSlug: '',
        runnerUpConfidence: 0,
        wasUncertain: false,
        confidenceThreshold: 0.45,
        confidencePolicyValidated: false,
        qualityBrightness: 0.5,
        qualityLaplacianVariance: 1200,
        qualityAccepted: true,
        modelLabel: 'm',
        modelAsset: 'a',
      ));
      final HistoryRecord newer = await repository.save(HistoryRecord(
        createdAt: DateTime(2026, 9, 11, 12),
        topSlug: 'kereru',
        topCommonName: 'kereru',
        topScientificName: 'Scientific name',
        topConfidence: 0.8,
        runnerUpSlug: '',
        runnerUpConfidence: 0,
        wasUncertain: false,
        confidenceThreshold: 0.45,
        confidencePolicyValidated: false,
        qualityBrightness: 0.5,
        qualityLaplacianVariance: 1200,
        qualityAccepted: true,
        modelLabel: 'm',
        modelAsset: 'a',
      ));

      expect(older.id, 1);
      expect(newer.id, 2);
      final List<HistoryRecord> all = await repository.loadAll();
      expect(all.length, 2);
      expect(all.first.id, 2, reason: 'newest first');
    });

    test('delete removes one record and reports whether it existed', () async {
      final InMemoryHistoryRepository repository = InMemoryHistoryRepository();
      final HistoryRecord saved = await repository.save(record());

      expect(await repository.delete(saved.id!), isTrue);
      expect(await repository.delete(saved.id!), isFalse);
      expect(await repository.count(), 0);
    });

    test('deleteAll clears everything', () async {
      final InMemoryHistoryRepository repository = InMemoryHistoryRepository();
      await repository.save(record());
      await repository.save(record());

      expect(await repository.deleteAll(), 2);
      expect(await repository.count(), 0);
    });

    test('the record carries no photograph reference', () {
      final Map<String, Object?> json = record().toJson();
      expect(json.keys.where((String k) => k.contains('path')), isEmpty);
      expect(json.keys.where((String k) => k.contains('image')), isEmpty);
      expect(json['was_uncertain'], 0);
    });

    test('a record survives a row round-trip', () {
      final HistoryRecord original = record(uncertain: true);
      final HistoryRecord restored = HistoryRecord.fromRow(
        original.toRow()..['id'] = 7,
      );
      expect(restored.id, 7);
      expect(restored.wasUncertain, isTrue);
      expect(restored.topConfidence, 0.8);
      expect(restored.confidencePolicyValidated, isFalse);
      expect(restored.modelAsset, 'assets/models/fieldsnap_float.tflite');
    });
  });
}

List<String> _classesFrom(String raw) {
  final Map<String, dynamic> parsed = jsonDecode(raw) as Map<String, dynamic>;
  return (parsed['classes'] as List<dynamic>).cast<String>();
}

/// The gate's thresholds are calibrated artefacts, so they are pinned here with their provenance:
/// changing them without re-running the calibration (and updating the record) fails this test.
void calibratedThresholdsArePinned() {
  test('the frozen FR2 thresholds match the calibration artefact', () {
    final File verification = File('artifacts/quality_gate_verification.json');
    if (!verification.existsSync()) {
      markTestSkipped('calibration artefact absent; run tools/calibrate_quality_gate.py');
      return;
    }
    final Map<String, dynamic> payload =
        jsonDecode(verification.readAsStringSync()) as Map<String, dynamic>;
    final Map<String, dynamic> chosen = payload['chosen_thresholds'] as Map<String, dynamic>;
    const QualityGateConfig config = QualityGateConfig();

    expect(config.minBrightness, chosen['min_brightness']);
    expect(config.maxBrightness, chosen['max_brightness']);
    expect(config.minLaplacianVariance, chosen['min_laplacian_variance']);
    expect(config.analysisSize, chosen['analysis_size']);
    expect(payload['calibrated'], isTrue,
        reason: 'the verification pass must have met the acceptance rule');
  });
}
