import 'dart:convert';
import 'dart:io';

import 'package:fieldsnap/services/image_preprocessor.dart';
import 'package:fieldsnap/services/model_labels.dart';
import 'package:fieldsnap/services/tflite_inference_engine.dart';
import 'package:fieldsnap/services/tflite_species_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

/// Offline confidence-calibration harness (Iteration 3).
///
/// Classifies every validation image **once** with the shipped FP32 model through the production
/// preprocessor and writes each image's top-1 score and correctness to
/// `artifacts/conf/val_scores.json`. `tools/calibrate_confidence_threshold.py` then applies the
/// pre-registered selection rule; the threshold itself is never chosen here.
///
/// Skipped by default (the validation images are git-ignored local data). Run:
///
/// ```sh
/// flutter test test/confidence_calibration_harness_test.dart --dart-define=CONF_CALIBRATE=true
/// ```
void main() {
  const bool enabled = bool.fromEnvironment('CONF_CALIBRATE');

  test('scores every validation image with the shipped model', () async {
    if (!enabled) {
      markTestSkipped('calibration harness: pass --dart-define=CONF_CALIBRATE=true to run');
      return;
    }
    final File manifest = File('data/manifest_val.csv');
    expect(manifest.existsSync(), isTrue, reason: 'validation manifest missing');

    final ModelLabels labels = ModelLabels.fromJsonString(
      File('assets/models/class_indices.json').readAsStringSync(),
    );
    final List<String> classes = labels.classes;
    final TfliteInferenceEngine engine = await TfliteInferenceEngine.loadFromBytes(
      bytes: File('assets/models/fieldsnap_float.tflite').readAsBytesSync(),
      expectedLabels: classes,
    );
    addTearDown(engine.dispose);

    // Parse as CSV (attribution strings contain commas) and resolve paths relative to the
    // repository root, because the manifest stores repo-relative paths. `File(path)` silently
    // existsSync()==false otherwise, which is how the first run scored zero images.
    final List<List<String>> table = _parseCsv(manifest.readAsStringSync());
    final List<String> header = table.first;
    final int slugIndex = header.indexOf('class_slug');
    final int pathIndex = header.indexOf('file_path');
    final int photoIndex = header.indexOf('photo_id');
    expect(slugIndex, greaterThanOrEqualTo(0));
    expect(pathIndex, greaterThanOrEqualTo(0));
    final String repoRoot = Directory.current.path;

    const ImagePreprocessor preprocessor = ImagePreprocessor();
    final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
    int correct = 0;
    int skipped = 0;
    for (final List<String> parts in table.skip(1)) {
      if (parts.length <= pathIndex) {
        continue;
      }
      final String slug = parts[slugIndex];
      final File image = File('$repoRoot/${parts[pathIndex]}');
      if (!image.existsSync()) {
        skipped++;
        continue;
      }
      final ModelInput input = preprocessor.fromImageBytes(image.readAsBytesSync());
      final List<double> scores = await engine.run(input);
      int argmax = 0;
      for (int i = 1; i < scores.length; i++) {
        if (scores[i] > scores[argmax]) {
          argmax = i;
        }
      }
      final bool isCorrect = classes[argmax] == slug;
      if (isCorrect) {
        correct++;
      }
      rows.add(<String, Object?>{
        'photo_id': parts[photoIndex],
        'truth': slug,
        'predicted': classes[argmax],
        'top1_score': scores[argmax],
        'correct': isCorrect,
      });
    }

    Directory('artifacts/conf').createSync(recursive: true);
    File('artifacts/conf/val_scores.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'rows': rows,
        'overall_top1': rows.isEmpty ? 0.0 : correct / rows.length,
        'model': 'assets/models/fieldsnap_float.tflite',
      }),
    );
    // ignore: avoid_print
    print('SCORED ${rows.length} validation images (skipped $skipped missing), '
        'top-1 ${rows.isEmpty ? "n/a" : (correct / rows.length).toStringAsFixed(4)}');
  });
}

/// Minimal CSV parser for the manifest (quoted fields, embedded commas).
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
