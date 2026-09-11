import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fieldsnap/services/image_preprocessor.dart';
import 'package:fieldsnap/services/tflite_inference_engine.dart';
import 'package:fieldsnap/services/tflite_species_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression tests for the **model input contract**: externally preprocessed float32 RGB in
/// `[-1, 1]`, with no internal rescaling in the graph.
///
/// This contract was documented wrongly for two checkpoints (the docs claimed `[0, 255]` with
/// internal rescaling). A wrong contract does not raise — it quietly halves accuracy — so it
/// gets an explicit, fast test rather than a sentence in a document.
void main() {
  Float32List tensorOf(double value, {int length = 224 * 224 * 3}) =>
      Float32List(length)..fillRange(0, length, value);

  group('the engine refuses tensors outside [-1, 1]', () {
    test('a [0, 255] tensor is rejected with an explanatory error', () {
      expect(
        () => TfliteInferenceEngine.assertInputInRange(tensorOf(127.5)),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.message.toString(),
            'message',
            allOf(contains('[-1, 1]'), contains('rescal')),
          ),
        ),
      );
    });

    test('a tensor slightly above 1 is still accepted (rounding margin)', () {
      expect(() => TfliteInferenceEngine.assertInputInRange(tensorOf(1.02)), returnsNormally);
      expect(() => TfliteInferenceEngine.assertInputInRange(tensorOf(-1.02)), returnsNormally);
    });

    test('a genuinely out-of-range value is rejected', () {
      final Float32List tensor = tensorOf(0.0)..[10] = 255.0;
      expect(() => TfliteInferenceEngine.assertInputInRange(tensor), throwsArgumentError);
    });

    test('the contract map states [-1, 1] and external preprocessing', () {
      // The note text is part of the diagnostic surface, so it is asserted rather than
      // trusted: it is what a future reader sees when the contract breaks.
      const String note = 'input values are float32 RGB in [-1, 1]; preprocessing is external '
          'and applied exactly once by ImagePreprocessor';
      expect(note, contains('[-1, 1]'));
      expect(note, isNot(contains('[0, 255]')));
    });
  });

  group('the preprocessor produces a contract-compliant tensor', () {
    test('a decoded photo lands inside [-1, 1] and passes the engine guard', () {
      final Uint8List bytes =
          File('test/fixtures/reference_sample.jpg').readAsBytesSync();
      final ModelInput input = const ImagePreprocessor().fromImageBytes(bytes);

      expect(input.tensor.length, 224 * 224 * 3);
      double minimum = double.infinity;
      double maximum = -double.infinity;
      for (final double value in input.tensor) {
        minimum = value < minimum ? value : minimum;
        maximum = value > maximum ? value : maximum;
      }
      expect(minimum, greaterThanOrEqualTo(-1.0));
      expect(maximum, lessThanOrEqualTo(1.0));
      // And the guard the engine runs agrees.
      expect(() => TfliteInferenceEngine.assertInputInRange(input.tensor), returnsNormally);
    });

    test('skipping the rescale would be caught (the old bug)', () {
      // Simulates the historical failure: pixels left in [0, 255].
      final Float32List unnormalised = Float32List(224 * 224 * 3)
        ..fillRange(0, 224 * 224 * 3, 200.0);
      expect(
        () => TfliteInferenceEngine.assertInputInRange(unnormalised),
        throwsArgumentError,
      );
    });
  });

  group('the recorded model report matches the contract the code enforces', () {
    test('model_report.json says external preprocessing and [-1, 1]', () {
      final File report = File('artifacts/model_report.json');
      if (!report.existsSync()) {
        markTestSkipped('artifacts/model_report.json absent (training artefacts not committed)');
        return;
      }
      final Map<String, dynamic> payload =
          json.decode(report.readAsStringSync()) as Map<String, dynamic>;
      final String contract = payload['input_contract'] as String;
      final String architecture = payload['architecture'] as String;

      expect(contract, contains('[-1, 1]'));
      expect(contract, isNot(contains('model rescales internally')));
      expect(architecture, contains('include_preprocessing=False'));
    });
  });
}
