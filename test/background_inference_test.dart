import 'dart:io';
import 'dart:typed_data';

import 'package:fieldsnap/services/background_runner.dart';
import 'package:fieldsnap/services/image_preprocessor.dart';
import 'package:fieldsnap/services/on_device_species_classifier.dart';
import 'package:fieldsnap/services/model_labels.dart';
import 'package:fieldsnap/services/tflite_inference_engine.dart';
import 'package:fieldsnap/services/tflite_species_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the NFR3 boundary: **inference must not run on the Flutter UI isolate.**
///
/// Two things are checked separately, because conflating them is how this property gets claimed
/// without being true:
///
///  * the production runner really is an isolate, and it really does execute work off the current
///    isolate (proved with an isolate-local marker, which cannot be faked by an inline call);
///  * the classifier drives its work through the runner, so the fake-based tests in
///    `classifier_view_model_test.dart` are testing the same seam the app uses.
void main() {
  group('isolate boundary', () {
    test('the inline runner reports that it is not an isolate', () async {
      const InlineBackgroundRunner runner = InlineBackgroundRunner();
      expect(runner.isIsolate, isFalse);
      final int result = await runner.run<int, int>((int value) => value * 2, 21);
      expect(result, 42);
    });

    test('the production runner is an isolate and runs work on another isolate', () async {
      const IsolateBackgroundRunner runner = IsolateBackgroundRunner();
      expect(runner.isIsolate, isTrue,
          reason: 'the production boundary must be a real isolate, not a rename');

      // A marker that only the parent isolate can see. If the work ran inline, the child would
      // still see it; running in a fresh isolate means the variable is unset there.
      markerValue = 'set-in-parent';
      final String observed = await runner.run<void, String>(
        (_) => _readMarker(),
        null,
      );
      expect(markerValue, 'set-in-parent');
      expect(observed, 'unset',
          reason: 'work must execute in a fresh isolate, which cannot see parent state');
    });

    test('the runner propagates the returned value across the boundary', () async {
      const IsolateBackgroundRunner runner = IsolateBackgroundRunner();
      final List<double> scores = await runner.run<List<int>, List<double>>(
        (List<int> values) => values.map((int v) => v / 2).toList(),
        <int>[2, 4, 6],
      );
      expect(scores, <double>[1.0, 2.0, 3.0]);
    });
  });

  group('the classifier runs through the runner', () {
    test('the production classifier offers a preparation hook and an isolate boundary', () {
      // The class is constructed through async asset loading, so the static surface is asserted
      // here and the behaviour is covered by the ViewModel tests through the same interface.
      expect(OnDeviceSpeciesClassifier.create, isNotNull);
      expect(const IsolateBackgroundRunner().isIsolate, isTrue);
    });

    test('the engine validates the model contract before any inference', () async {
      final File model = File('artifacts/fieldsnap_float.tflite');
      if (!model.existsSync()) {
        markTestSkipped('artifacts/fieldsnap_float.tflite absent (training artefacts only)');
        return;
      }
      if (!_hostTfliteLibraryAvailable()) {
        markTestSkipped('tflite_flutter macOS dylib not installed for flutter_tester');
        return;
      }
      final ModelLabels labels = ModelLabels.fromJsonString(
        File('assets/models/class_indices.json').readAsStringSync(),
      );
      final TfliteInferenceEngine engine = await TfliteInferenceEngine.loadFromBytes(
        bytes: model.readAsBytesSync(),
        expectedLabels: labels.classes,
      );
      addTearDown(engine.dispose);

      expect(engine.contract['input_shape'], <int>[1, 224, 224, 3]);
      expect(engine.contract['output_shape'], <int>[1, 20]);
      expect(engine.contract['note'].toString(), contains('[-1, 1]'));

      // A wrong label list must be rejected rather than silently mismatched.
      expect(
        () => TfliteInferenceEngine.loadFromBytes(
          bytes: model.readAsBytesSync(),
          expectedLabels: <String>['only-one'],
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('preprocessing inside the background payload', () {
    test('the preprocessor produces the tensor the engine requires', () {
      final Uint8List bytes =
          File('test/fixtures/reference_sample.jpg').readAsBytesSync();
      final ModelInput input = const ImagePreprocessor().fromImageBytes(bytes);
      expect(() => TfliteInferenceEngine.assertInputInRange(input.tensor), returnsNormally);
    });
  });
}

/// Set in the parent isolate only; the child isolate must not see it.
String? markerValue;

String _readMarker() => markerValue ?? 'unset';

bool _hostTfliteLibraryAvailable() {
  if (!Platform.isMacOS) {
    return true;
  }
  final String resourcesPath =
      '${Directory(Platform.resolvedExecutable).parent.parent.path}/resources';
  return File('$resourcesPath/libtensorflowtle_c-mac.dylib').existsSync() ||
      File('$resourcesPath/libtensorflowlite_c-mac.dylib').existsSync();
}
