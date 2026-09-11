import 'dart:convert';
import 'dart:typed_data';

import 'dart:io' show Platform;

import 'package:fieldsnap/services/image_preprocessor.dart';
import 'package:fieldsnap/services/model_labels.dart';
import 'package:fieldsnap/services/tflite_inference_engine.dart';
import 'package:fieldsnap/services/tflite_species_classifier.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// On-device **runtime conformance** for the model the app actually ships (checkpoint 1B/1C/1D and
/// Iteration 2).
///
/// The device is fed the *same canonical tensor* the Python reference used, so this compares
/// Android's execution of the model against Python's — a preprocessing difference cannot hide
/// behind it. The whole 20-value output vector is compared, not just the top class.
///
/// Run with a device or emulator attached:
///
/// ```sh
/// flutter test integration_test/on_device_inference_test.dart -d <device-id>
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Same model and same tensor, different runtime. FP32 reproduces Python to ~1e-6, so the bound
  // is tight; the experimental INT8 artefact is only checked for shape and normalisation here.
  const double runtimeTolerance = 1e-3;

  testWidgets('Android reproduces the Python output vector for the shipped FP32 model',
      (WidgetTester tester) async {
    final ModelLabels labels = await ModelLabels.fromAsset();

    final ByteData tensorBytes = await rootBundle.load('assets/test/reference_input.f32');
    final Float32List tensor =
        tensorBytes.buffer.asFloat32List(0, tensorBytes.lengthInBytes ~/ 4);
    expect(tensor.length, 224 * 224 * 3);

    final String rawReference =
        await rootBundle.loadString('assets/test/reference_output.json');
    final Map<String, dynamic> reference = json.decode(rawReference) as Map<String, dynamic>;
    final Map<String, dynamic> expectedFloat = reference['float'] as Map<String, dynamic>;
    final List<double> expected =
        (expectedFloat['probabilities'] as List<dynamic>).cast<double>();
    final String expectedClass = expectedFloat['argmax_class'] as String;

    final TfliteInferenceEngine engine = await TfliteInferenceEngine.load(
      expectedLabels: labels.classes,
    );
    addTearDown(engine.dispose);

    expect(engine.contract['input_shape'], <int>[1, 224, 224, 3]);
    expect(engine.contract['output_shape'], <int>[1, labels.classes.length]);
    expect(labels.classes.length, expected.length);

    final List<double> scores = await engine.run(
      ModelInput(tensor: tensor, imageWidth: 224, imageHeight: 224),
    );

    double maxDelta = 0;
    for (int i = 0; i < scores.length; i++) {
      final double delta = (scores[i] - expected[i]).abs();
      maxDelta = delta > maxDelta ? delta : maxDelta;
    }
    expect(maxDelta, lessThan(runtimeTolerance),
        reason: 'Android output vector differs from the Python reference by $maxDelta');

    final int argmax =
        scores.indexOf(scores.reduce((double a, double b) => a > b ? a : b));
    expect(labels.classes[argmax], expectedClass,
        reason: 'the on-device top class must match the recorded reference');
  });

  group('device latency (Milestone 1 §7 protocol)', () {
    _latencyProtocol();
    _endToEndLatency();
  });

  testWidgets('the experimental INT8 artefact still loads and normalises on device',
      (WidgetTester tester) async {
    final ModelLabels labels = await ModelLabels.fromAsset();
    final TfliteInferenceEngine engine = await TfliteInferenceEngine.load(
      assetPath: TfliteInferenceEngine.experimentalInt8Asset,
      expectedLabels: labels.classes,
    );
    addTearDown(engine.dispose);

    final ByteData tensorBytes = await rootBundle.load('assets/test/reference_input.f32');
    final Float32List tensor =
        tensorBytes.buffer.asFloat32List(0, tensorBytes.lengthInBytes ~/ 4);
    final List<double> scores = await engine.run(
      ModelInput(tensor: tensor, imageWidth: 224, imageHeight: 224),
    );

    expect(scores.length, labels.classes.length);
    expect(scores.reduce((double a, double b) => a + b), closeTo(1.0, 0.1));
  });
}

/// Latency protocol from Milestone 1 §7: warm-up runs, then at least 30 repeated single-image
/// runs, reporting median and P95 on a physical device. Run this with a **profile** build, not
/// debug, and read the numbers as device measurements only when it actually ran on hardware.
void _latencyProtocol() {
  testWidgets('measures the full CPU path (preprocess + inference) on this device',
      (WidgetTester tester) async {
    final ModelLabels labels = await ModelLabels.fromAsset();
    final ByteData tensorBytes = await rootBundle.load('assets/test/reference_input.f32');
    final Float32List tensor =
        tensorBytes.buffer.asFloat32List(0, tensorBytes.lengthInBytes ~/ 4);

    final TfliteInferenceEngine engine = await TfliteInferenceEngine.load(
      expectedLabels: labels.classes,
    );
    addTearDown(engine.dispose);
    final ModelInput prepared =
        ModelInput(tensor: tensor, imageWidth: 224, imageHeight: 224);

    // Warm-up: excluded from the statistics, as the protocol requires.
    for (int i = 0; i < 5; i++) {
      await engine.run(prepared);
    }

    const int runs = 30;
    final List<int> micros = <int>[];
    for (int i = 0; i < runs; i++) {
      final Stopwatch stopwatch = Stopwatch()..start();
      await engine.run(prepared);
      stopwatch.stop();
      micros.add(stopwatch.elapsedMicroseconds);
    }
    micros.sort();
    final double medianMs = micros[runs ~/ 2] / 1000;
    final double p95Ms = micros[(runs * 95) ~/ 100] / 1000;
    final double minMs = micros.first / 1000;
    final double maxMs = micros.last / 1000;

    // ignore: avoid_print
    print('LATENCY ${Platform.operatingSystem} runs=$runs '
        'median=${medianMs.toStringAsFixed(2)}ms p95=${p95Ms.toStringAsFixed(2)}ms '
        'min=${minMs.toStringAsFixed(2)}ms max=${maxMs.toStringAsFixed(2)}ms');

    expect(micros.length, runs);
    expect(medianMs, greaterThan(0));
  });
}

/// Times a full single-image flow the way the app runs it: decode + resize + rescale, then model.
void _endToEndLatency() {
  testWidgets('measures decode + preprocess + inference for a real photo',
      (WidgetTester tester) async {
    final ModelLabels labels = await ModelLabels.fromAsset();
    final TfliteInferenceEngine engine = await TfliteInferenceEngine.load(
      expectedLabels: labels.classes,
    );
    addTearDown(engine.dispose);

    final ByteData photo = await rootBundle.load('assets/test/reference_sample.jpg');
    final Uint8List bytes = photo.buffer.asUint8List();
    const ImagePreprocessor preprocessor = ImagePreprocessor();

    for (int i = 0; i < 3; i++) {
      await engine.run(preprocessor.fromImageBytes(bytes));
    }
    final List<int> micros = <int>[];
    for (int i = 0; i < 30; i++) {
      final Stopwatch stopwatch = Stopwatch()..start();
      await engine.run(preprocessor.fromImageBytes(bytes));
      stopwatch.stop();
      micros.add(stopwatch.elapsedMicroseconds);
    }
    micros.sort();
    // ignore: avoid_print
    print('END_TO_END runs=30 median=${(micros[15] / 1000).toStringAsFixed(2)}ms '
        'p95=${(micros[28] / 1000).toStringAsFixed(2)}ms');
    expect(micros.length, 30);
  });
}
