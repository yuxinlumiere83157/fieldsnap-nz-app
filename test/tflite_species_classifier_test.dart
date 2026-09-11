import 'dart:typed_data';

import 'package:fieldsnap/models/picked_image.dart';
import 'package:fieldsnap/services/classification_result.dart';
import 'package:fieldsnap/services/tflite_species_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

/// Deterministic [InferenceEngine] so the classifier logic is testable without a
/// model file. It never pretends to be a real model: the labels it returns are
/// obvious placeholders that must not leak into the app.
class FakeInferenceEngine implements InferenceEngine {
  FakeInferenceEngine({
    required this.scores,
    List<String>? labels,
    this.failure,
  }) : labels = labels ?? List<String>.generate(scores.length, (int i) => 'label_$i');

  final List<double> scores;
  final Object? failure;

  @override
  final List<String> labels;

  @override
  List<int> get outputShape => <int>[1, labels.length];

  int runCount = 0;
  ModelInput? lastInput;

  @override
  Future<List<double>> run(ModelInput input) async {
    runCount += 1;
    lastInput = input;
    final Object? thrown = failure;
    if (thrown != null) {
      throw thrown;
    }
    return scores;
  }

  @override
  void dispose() {}
}

void main() {
  ModelInput anyInput() => ModelInput(
        tensor: Float32List(224 * 224 * 3),
        imageWidth: 224,
        imageHeight: 224,
      );

  PickedImage anyImage() =>
      const PickedImage(path: '/tmp/does_not_matter.jpg', sizeBytes: 1024);

  group('top-3 result shape', () {
    test('returns exactly three candidates ordered by confidence', () async {
      final FakeInferenceEngine engine = FakeInferenceEngine(
        scores: <double>[0.05, 0.72, 0.10, 0.13],
        labels: <String>['tui', 'kereru', 'nikau', 'kowhai'],
      );
      final TfliteSpeciesClassifier classifier = TfliteSpeciesClassifier(
        engine: engine,
        preprocess: (PickedImage _) => anyInput(),
      );

      final ClassificationResult result = await classifier.classify(anyImage());

      expect(result.isSuccess, isTrue);
      expect(result.candidates.length, 3);
      expect(
        result.candidates.map((SpeciesCandidate c) => c.commonName).toList(),
        <String>['kereru', 'kowhai', 'nikau'],
      );
      expect(result.candidates.first.confidence, 0.72);
      expect(engine.runCount, 1);
    });

    test('exposes model availability truthfully', () {
      final TfliteSpeciesClassifier classifier = TfliteSpeciesClassifier(
        engine: FakeInferenceEngine(scores: <double>[1.0], labels: <String>['only']),
        preprocess: (PickedImage _) => anyInput(),
      );

      expect(classifier.isModelAvailable, isTrue);
    });

    test('does not pad candidates when the model knows fewer than three classes',
        () async {
      final TfliteSpeciesClassifier classifier = TfliteSpeciesClassifier(
        engine: FakeInferenceEngine(scores: <double>[0.6, 0.4], labels: <String>['a', 'b']),
        preprocess: (PickedImage _) => anyInput(),
      );

      final ClassificationResult result = await classifier.classify(anyImage());

      expect(result.candidates.length, 2);
    });
  });

  group('honest failure reporting', () {
    test('a throwing engine becomes an inferenceFailed result, not a crash',
        () async {
      final TfliteSpeciesClassifier classifier = TfliteSpeciesClassifier(
        engine: FakeInferenceEngine(scores: <double>[0.5], failure: StateError('boom')),
        preprocess: (PickedImage _) => anyInput(),
      );

      final ClassificationResult result = await classifier.classify(anyImage());

      expect(result.isSuccess, isFalse);
      expect(result.failureReason, ClassificationFailureReason.inferenceFailed);
      expect(result.failureDetail, contains('boom'));
    });

    test('a preprocessing failure becomes an invalidInput result', () async {
      final TfliteSpeciesClassifier classifier = TfliteSpeciesClassifier(
        engine: FakeInferenceEngine(scores: <double>[0.5]),
        preprocess: (PickedImage _) => throw const FormatException('not an image'),
      );

      final ClassificationResult result = await classifier.classify(anyImage());

      expect(result.failureReason, ClassificationFailureReason.invalidInput);
    });

    test('a label/score mismatch is reported instead of silently truncated',
        () async {
      final TfliteSpeciesClassifier classifier = TfliteSpeciesClassifier(
        engine: FakeInferenceEngine(
          scores: <double>[0.5, 0.5], // two scores
          labels: <String>['a', 'b', 'c'], // three labels
        ),
        preprocess: (PickedImage _) => anyInput(),
      );

      final ClassificationResult result = await classifier.classify(anyImage());

      expect(result.isSuccess, isFalse);
      expect(result.failureReason, ClassificationFailureReason.inferenceFailed);
      expect(result.failureDetail, contains('label order'));
    });
  });

  group('input contract passed to the engine', () {
    test('hands the engine the tensor produced by the preprocessor', () async {
      final FakeInferenceEngine engine =
          FakeInferenceEngine(scores: <double>[1.0], labels: <String>['x']);
      final TfliteSpeciesClassifier classifier = TfliteSpeciesClassifier(
        engine: engine,
        preprocess: (PickedImage _) => anyInput(),
      );

      await classifier.classify(anyImage());

      expect(engine.lastInput, isNotNull);
      expect(engine.lastInput!.tensor.length, 224 * 224 * 3);
      expect(engine.lastInput!.imageWidth, 224);
    });
  });
}
