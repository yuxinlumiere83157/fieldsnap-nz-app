import 'dart:convert';
import 'dart:io';

import 'package:fieldsnap/services/quality_gate.dart';
import 'package:flutter_test/flutter_test.dart';

/// Offline quality-gate calibration harness (Iteration 3).
///
/// Not a behaviour test: it measures the **production** gate
/// (`ImageQualityGate.evaluate`, the same code the app runs) over the pre-generated calibration and
/// verification subsets from `tools/calibrate_quality_gate.py`, and writes every image's two
/// metrics to `artifacts/qg/metrics.json` so the pre-registered selection rule can be applied in
/// Python without re-implementing the metrics.
///
/// It is skipped by default because the subsets are generated artefacts (git-ignored). Run the
/// generator first, then:
///
/// ```sh
/// flutter test test/quality_gate_calibration_harness_test.dart --dart-define=QG_CALIBRATE=1
/// ```
void main() {
  const bool enabled = bool.fromEnvironment('QG_CALIBRATE');

  test('measures the production gate over the calibration subsets', () {
    if (!enabled) {
      markTestSkipped('calibration harness: pass --dart-define=QG_CALIBRATE=1 to run');
      return;
    }
    final File manifest = File('artifacts/qg/manifest.json');
    expect(manifest.existsSync(), isTrue,
        reason: 'run tools/calibrate_quality_gate.py --stage prepare first');

    final Map<String, dynamic> payload =
        json.decode(manifest.readAsStringSync()) as Map<String, dynamic>;
    const ImageQualityGate gate = ImageQualityGate();
    final Map<String, List<Map<String, Object?>>> out = <String, List<Map<String, Object?>>>{};

    for (final String subset in <String>['calibration', 'verification']) {
      final List<Map<String, Object?>> records = <Map<String, Object?>>[];
      for (final dynamic entry in payload[subset] as List<dynamic>) {
        final Map<String, dynamic> row = entry as Map<String, dynamic>;
        final QualityDecision decision =
            gate.evaluate(File(row['path'] as String).readAsBytesSync());
        records.add(<String, Object?>{
          'photo_id': row['photo_id'],
          'observation_id': row['observation_id'],
          'condition': row['condition'],
          'expected': row['expected'],
          'acceptable': decision.isAcceptable,
          'failure_kind': decision.kind?.name,
          'brightness': decision.metrics?.brightness,
          'laplacian_variance': decision.metrics?.laplacianVariance,
        });
      }
      out[subset] = records;
      // ignore: avoid_print
      print('MEASURED $subset ${records.length} images');
    }

    File('artifacts/qg/metrics.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
    // ignore: avoid_print
    print('WROTE artifacts/qg/metrics.json');
  });
}
