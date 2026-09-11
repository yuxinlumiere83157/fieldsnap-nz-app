import 'dart:convert';
import 'dart:io';

import 'package:fieldsnap/services/image_preprocessor.dart';
import 'package:fieldsnap/services/model_labels.dart';
import 'package:fieldsnap/services/tflite_inference_engine.dart';
import 'package:fieldsnap/services/tflite_species_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

/// FINAL TEST-SPLIT EVALUATION — opened once, per docs/final_test_evaluation_protocol.md.
///
/// Uses the shipped FP32 model through the **production** preprocessing (`ImagePreprocessor`) for
/// every image in `data/manifest_test.csv`, regardless of any quality-gate outcome, and writes raw
/// per-image predictions to `artifacts/final_test_predictions.json`. Metrics are computed from that
/// file by `tools/final_test_evaluation_report.py`; no threshold is applied here.
///
/// Skipped by default (the test images are git-ignored local data). Run once:
///
/// ```sh
/// flutter test test/final_test_evaluation_harness_test.dart --dart-define=FINAL_TEST=1
/// ```
void main() {
  const bool enabled = bool.fromEnvironment('FINAL_TEST');

  test('evaluates every sealed test image with the shipped FP32 model', () async {
    if (!enabled) {
      markTestSkipped('final test harness: pass --dart-define=FINAL_TEST=1 to run');
      return;
    }
    final File manifest = File('data/manifest_test.csv');
    expect(manifest.existsSync(), isTrue, reason: 'sealed test manifest missing');

    final ModelLabels labels = ModelLabels.fromJsonString(
      File('assets/models/class_indices.json').readAsStringSync(),
    );
    final List<String> classes = labels.classes;
    final TfliteInferenceEngine engine = await TfliteInferenceEngine.loadFromBytes(
      bytes: File('assets/models/fieldsnap_float.tflite').readAsBytesSync(),
      expectedLabels: classes,
    );
    addTearDown(engine.dispose);

    final List<List<String>> table = _parseCsv(manifest.readAsStringSync());
    final List<String> header = table.first;
    final int slugIndex = header.indexOf('class_slug');
    final int pathIndex = header.indexOf('file_path');
    final int photoIndex = header.indexOf('photo_id');
    final int obsIndex = header.indexOf('observation_id');
    final String repoRoot = Directory.current.path;

    const ImagePreprocessor preprocessor = ImagePreprocessor();
    final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
    int skipped = 0;
    final Stopwatch total = Stopwatch()..start();
    for (final List<String> parts in table.skip(1)) {
      if (parts.length <= pathIndex) {
        continue;
      }
      final File image = File('$repoRoot/${parts[pathIndex]}');
      if (!image.existsSync()) {
        skipped++;
        continue;
      }
      final String truth = parts[slugIndex];
      final ModelInput input =
          preprocessor.fromImageBytes(image.readAsBytesSync());
      final List<double> scores = await engine.run(input);

      final List<int> order = List<int>.generate(scores.length, (int i) => i)
        ..sort((int a, int b) => scores[b].compareTo(scores[a]));
      final List<Map<String, Object?>> top3 = <Map<String, Object?>>[
        for (int i = 0; i < 3 && i < order.length; i++)
          <String, Object?>{
            'class': classes[order[i]],
            'score': double.parse(scores[order[i]].toStringAsFixed(6)),
          },
      ];
      rows.add(<String, Object?>{
        'photo_id': parts[photoIndex],
        'observation_id': parts[obsIndex],
        'truth': truth,
        'predicted': classes[order[0]],
        'top1_score': double.parse(scores[order[0]].toStringAsFixed(6)),
        'top3': top3,
        'correct_top1': classes[order[0]] == truth,
        'correct_top3': top3.any((Map<String, Object?> c) => c['class'] == truth),
      });
    }
    total.stop();

    Directory('artifacts').createSync(recursive: true);
    File('artifacts/final_test_predictions.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'model': 'assets/models/fieldsnap_float.tflite',
        'preprocessing': 'ImagePreprocessor (production path)',
        'images_scored': rows.length,
        'images_missing': skipped,
        'scoring_ms_total': total.elapsedMilliseconds,
        'rows': rows,
      }),
    );
    // ignore: avoid_print
    print('FINAL_TEST scored ${rows.length} images (missing $skipped) in '
        '${total.elapsedMilliseconds} ms');
  });
}

/// Minimal CSV parser (quoted fields, embedded commas).
List<List<String>> _parseCsv(String input) {
  final List<List<String>> rows = <List<String>>[];
  List<String> row = <String>[];
  final StringBuffer field = StringBuffer();
  bool inQuotes = false;
  for (int i = 0; i < input.length; i++) {
    final String ch = input[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < input.length && input[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(ch);
      }
    } else if (ch == '"') {
      inQuotes = true;
    } else if (ch == ',') {
      row.add(field.toString());
      field.clear();
    } else if (ch == '\n') {
      row.add(field.toString());
      field.clear();
      rows.add(row);
      row = <String>[];
    } else if (ch != '\r') {
      field.write(ch);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows;
}
