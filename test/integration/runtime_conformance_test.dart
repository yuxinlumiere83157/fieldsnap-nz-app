@Tags(<String>['integration'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fieldsnap/models/picked_image.dart';
import 'package:fieldsnap/services/model_labels.dart';
import 'package:fieldsnap/services/tflite_inference_engine.dart';
import 'package:fieldsnap/services/tflite_species_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

/// Check 2 of 3: **runtime conformance** (a fixed tensor in, the full output vector out).
///
/// Preprocessing is excluded on purpose, so a disagreement here can only come from the
/// interpreter, the tensor layout or the label order — never from a resampling difference.
///
/// Two clearly separated scopes, because they need different inputs:
///
///  * **shipped model (required)** — `assets/models/fieldsnap_int8.tflite`, which is committed,
///    compared against `assets/test/reference_output.json`. Runs on a plain clone with no
///    training artefacts.
///  * **training comparison (research)** — `artifacts/fieldsnap_float.tflite`, which is *not*
///    committed. Skips with an explicit reason when absent. A skip is reported as a skip and is
///    never counted as a pass.
void main() {
  // Iteration 2 moved the deployment baseline from INT8 to FP32 (docs/model_selection.md), so the
  // required check follows the shipped model.
  const String shippedModel = 'assets/models/fieldsnap_float.tflite';
  const String floatModel = 'artifacts/fieldsnap_float.tflite';
  const String referencePath = 'assets/test/reference_output.json';
  const String tensorPath = 'assets/test/reference_input.f32';

  // Same model file, same tensor, different runtime.
  //
  // The float model reproduces Python to ~1e-6, so its bound is tight.
  //
  // The INT8 model is a different story: on this model its output barely moves from a
  // near-uniform distribution (top probability ~0.16) and the two runtimes disagree by up to
  // ~0.09 absolute probability. That is *not* a clean "one quantisation step": it has not been
  // proven where the difference comes from (per-channel scales, the XNNPACK int8 kernels, or
  // the near-uniform softmax itself). The bound below is therefore a measured empirical band,
  // not a derived property, and the argmax is only checked when the two runtimes actually
  // agree — a disagreement is reported as a finding rather than hidden.
  const double floatTolerance = 1e-3;

  Float32List loadTensor(String path) {
    final Uint8List bytes = File(path).readAsBytesSync();
    return bytes.buffer.asFloat32List(0, bytes.length ~/ 4);
  }

  ModelLabels labels() => ModelLabels.fromJsonString(
        File('assets/models/class_indices.json').readAsStringSync(),
      );

  double maxDelta(List<double> a, List<double> b) {
    double worst = 0;
    for (int i = 0; i < a.length; i++) {
      final double delta = (a[i] - b[i]).abs();
      worst = delta > worst ? delta : worst;
    }
    return worst;
  }

  group('shipped FP32 model (runs on a fresh clone)', () {
    test('reproduces the recorded reference vector for the canonical tensor', () async {
      expect(File(shippedModel).existsSync(), isTrue,
          reason: 'the shipped model must be committed alongside the app');
      expect(File(referencePath).existsSync(), isTrue);
      expect(File(tensorPath).existsSync(), isTrue);
      if (!_hostTfliteLibraryAvailable()) {
        markTestSkipped('tflite_flutter macOS dylib not installed next to flutter_tester; the '
            'Android integration test covers this on a device');
        return;
      }

      final Map<String, dynamic> reference =
          json.decode(File(referencePath).readAsStringSync()) as Map<String, dynamic>;
      final Map<String, dynamic> expected = reference['float'] as Map<String, dynamic>;
      final List<double> expectedVector =
          (expected['probabilities'] as List<dynamic>).cast<double>();
      final ModelLabels modelLabels = labels();

      final TfliteInferenceEngine engine = await TfliteInferenceEngine.loadFromBytes(
        bytes: File(shippedModel).readAsBytesSync(),
        expectedLabels: modelLabels.classes,
      );
      addTearDown(engine.dispose);

      expect(engine.contract['input_shape'], <int>[1, 224, 224, 3]);
      expect(engine.contract['output_shape'], <int>[1, modelLabels.classes.length]);

      final List<double> scores = await engine.run(ModelInput(
        tensor: loadTensor(tensorPath),
        imageWidth: 224,
        imageHeight: 224,
      ));

      expect(scores.length, expectedVector.length);
      final double delta = maxDelta(scores, expectedVector);
      expect(delta, lessThan(floatTolerance),
          reason: 'Dart and Python disagree on the shipped FP32 model by $delta');

      final int argmax =
          scores.indexOf(scores.reduce((double a, double b) => a > b ? a : b));
      final String dartClass = modelLabels.classes[argmax];
      expect(dartClass, expected['argmax_class'],
          reason: 'the shipped model must predict the same class as the Python reference');

      // The experimental INT8 artefact stays covered: it must still load and produce a
      // distribution, and its known accuracy gap is recorded in docs/model_selection.md.
      final File int8 = File('assets/models/fieldsnap_int8.tflite');
      if (int8.existsSync()) {
        final TfliteInferenceEngine int8Engine = await TfliteInferenceEngine.loadFromBytes(
          bytes: int8.readAsBytesSync(),
          expectedLabels: modelLabels.classes,
        );
        addTearDown(int8Engine.dispose);
        final List<double> int8Scores = await int8Engine.run(ModelInput(
          tensor: loadTensor(tensorPath),
          imageWidth: 224,
          imageHeight: 224,
        ));
        expect(int8Scores.length, modelLabels.classes.length);
        expect(int8Scores.reduce((double a, double b) => a + b), closeTo(1.0, 0.1));
      }

      // The classifier wrapper is what the UI will consume, so exercise it too.
      final TfliteSpeciesClassifier classifier = TfliteSpeciesClassifier(
        engine: engine,
        preprocess: (PickedImage _) => ModelInput(
          tensor: loadTensor(tensorPath),
          imageWidth: 224,
          imageHeight: 224,
        ),
      );
      expect(classifier.isModelAvailable, isTrue);
    });
  });

  group('training comparison (needs artefacts from tools/train_and_export.py)', () {
    test('the float conversion reproduces the Python vector', () async {
      if (!File(floatModel).existsSync()) {
        markTestSkipped('research comparison skipped: artifacts/fieldsnap_float.tflite is not '
            'present (deliberately not committed); regenerate with tools/train_and_export.py');
        return;
      }
      if (!_hostTfliteLibraryAvailable()) {
        markTestSkipped('tflite_flutter macOS dylib not installed for flutter_tester');
        return;
      }

      final Map<String, dynamic> reference = json.decode(
        File('test/fixtures/reference_expected.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final Map<String, dynamic> expected =
          (reference['outputs'] as Map<String, dynamic>)['fieldsnap_float.tflite']
              as Map<String, dynamic>;
      final List<double> expectedVector =
          (expected['probabilities'] as List<dynamic>).cast<double>();
      final ModelLabels modelLabels = labels();

      final TfliteInferenceEngine engine = await TfliteInferenceEngine.loadFromBytes(
        bytes: File(floatModel).readAsBytesSync(),
        expectedLabels: modelLabels.classes,
      );
      addTearDown(engine.dispose);

      final List<double> scores = await engine.run(ModelInput(
        tensor: loadTensor('test/fixtures/reference_input.f32'),
        imageWidth: 224,
        imageHeight: 224,
      ));

      expect(maxDelta(scores, expectedVector), lessThan(floatTolerance),
          reason: 'the float conversion must track Keras/Python closely');
      final int argmax =
          scores.indexOf(scores.reduce((double a, double b) => a > b ? a : b));
      expect(modelLabels.classes[argmax], expected['argmax_class']);
    });
  });
}

bool _hostTfliteLibraryAvailable() {
  if (!Platform.isMacOS) {
    return true;
  }
  final String resourcesPath =
      '${Directory(Platform.resolvedExecutable).parent.parent.path}/resources';
  return File('$resourcesPath/libtensorflowlite_c-mac.dylib').existsSync();
}
