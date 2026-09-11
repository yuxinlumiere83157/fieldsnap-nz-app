// MEASUREMENT-ONLY ENTRY POINT — NOT PART OF THE APP.
//
// There is no "deployment baseline" here: this file exists so the Milestone 1 §7 latency protocol
// can be run in a **profile** build on a physical device, which `flutter test` cannot do (it builds
// debug). It renders one throwaway widget, runs warm-up + 30 timed single-image inferences, prints
// the numbers with `debugPrint`, and prints `BENCH_DONE` when finished.
//
// Do not ship this entry point and do not modify it to change any measurement definition: the
// protocol is warm-up excluded, ≥30 runs, preprocess + inference, median and P95.
//
// Usage:
//   flutter build apk --profile --target=lib/benchmark_main.dart
//   adb install -r build/app/outputs/flutter-apk/app-profile.apk
//   adb shell am start -n nz.fieldsnap.app/.MainActivity
//   adb logcat -s flutter:I | grep -E "LATENCY|END_TO_END|BENCH_DONE"
//
// The Android package id is unchanged (nz.fieldsnap.app); only the Dart entry point differs.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'services/image_preprocessor.dart';
import 'services/model_labels.dart';
import 'services/tflite_inference_engine.dart';
import 'services/tflite_species_classifier.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _BenchmarkApp());
}

class _BenchmarkApp extends StatefulWidget {
  const _BenchmarkApp();

  @override
  State<_BenchmarkApp> createState() => _BenchmarkAppState();
}

class _BenchmarkAppState extends State<_BenchmarkApp> {
  String _status = 'running...';

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final ModelLabels labels = await ModelLabels.fromAsset();
      final TfliteInferenceEngine engine = await TfliteInferenceEngine.load(
        expectedLabels: labels.classes,
      );

      // 1) Inference only, on a fixed tensor (isolates model execution from decoding).
      final ByteData tensorBytes = await rootBundle.load('assets/test/reference_input.f32');
      final Float32List tensor =
          tensorBytes.buffer.asFloat32List(0, tensorBytes.lengthInBytes ~/ 4);
      final ModelInput fixed =
          ModelInput(tensor: tensor, imageWidth: 224, imageHeight: 224);

      for (int i = 0; i < 5; i++) {
        await engine.run(fixed);
      }
      final List<int> inferenceMicros = <int>[];
      for (int i = 0; i < 30; i++) {
        final Stopwatch stopwatch = Stopwatch()..start();
        await engine.run(fixed);
        stopwatch.stop();
        inferenceMicros.add(stopwatch.elapsedMicroseconds);
      }
      inferenceMicros.sort();
      debugPrint('LATENCY inference_only runs=30 '
          'median=${(inferenceMicros[15] / 1000).toStringAsFixed(2)}ms '
          'p95=${(inferenceMicros[28] / 1000).toStringAsFixed(2)}ms '
          'min=${(inferenceMicros.first / 1000).toStringAsFixed(2)}ms '
          'max=${(inferenceMicros.last / 1000).toStringAsFixed(2)}ms');

      // 2) The full CPU path the app uses: decode + resize + rescale, then inference.
      final ByteData photo = await rootBundle.load('assets/test/reference_sample.jpg');
      final Uint8List bytes = photo.buffer.asUint8List();
      const ImagePreprocessor preprocessor = ImagePreprocessor();
      for (int i = 0; i < 3; i++) {
        await engine.run(preprocessor.fromImageBytes(bytes));
      }
      final List<int> fullMicros = <int>[];
      for (int i = 0; i < 30; i++) {
        final Stopwatch stopwatch = Stopwatch()..start();
        await engine.run(preprocessor.fromImageBytes(bytes));
        stopwatch.stop();
        fullMicros.add(stopwatch.elapsedMicroseconds);
      }
      fullMicros.sort();
      debugPrint('END_TO_END decode+preprocess+inference runs=30 '
          'median=${(fullMicros[15] / 1000).toStringAsFixed(2)}ms '
          'p95=${(fullMicros[28] / 1000).toStringAsFixed(2)}ms');

      engine.dispose();
      debugPrint('BENCH_DONE');
      if (mounted) {
        setState(() => _status = 'done - see logcat');
      }
    } catch (error, stack) {
      debugPrint('BENCH_FAILED $error');
      debugPrint('$stack');
      if (mounted) {
        setState(() => _status = 'failed: $error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(child: Text('FieldSnap latency benchmark: $_status')),
      ),
    );
  }
}
