import 'dart:typed_data';

import '../models/picked_image.dart';
import 'classification_result.dart';
import 'species_classifier.dart';

/// One decoded input tensor, in the exact layout the exported model expects.
///
/// The contract comes from `artifacts/model_report.json`, which records what the
/// TFLite converter actually produced rather than what we hoped it produced: the exported
/// models use `include_preprocessing=False` + external preprocessing, so the tensor is
/// float32 RGB **in [-1, 1]** — `(pixel - 127.5) / 127.5` applied exactly once by
/// `ImagePreprocessor`. Feeding raw `[0, 255]` values here (the stale earlier assumption)
/// degrades accuracy silently. See docs/preprocessing_spec.md.
class ModelInput {
  const ModelInput({
    required this.tensor,
    required this.imageWidth,
    required this.imageHeight,
  });

  /// Flat float32 tensor, row-major RGB.
  final Float32List tensor;
  final int imageWidth;
  final int imageHeight;
}

/// Anything that can run one inference over a prepared [ModelInput].
///
/// Kept abstract so the ViewModel-facing classifier can be unit tested with a fake,
/// while the real `tflite_flutter` interpreter stays in the adapter below.
abstract class InferenceEngine {
  /// Label order, exactly as recorded in the exported model's class index file.
  List<String> get labels;

  /// Output tensor layout, from the model itself.
  List<int> get outputShape;

  Future<List<double>> run(ModelInput input);

  void dispose();
}

/// Species classifier backed by an [InferenceEngine].
///
/// It performs no preprocessing decisions of its own: turn an accepted image into a
/// [ModelInput] with `ImagePreprocessor` (which reads the same contract) and hand it
/// here. Abstention (FR4) is deliberately absent because the threshold must come from
/// validation data.
class TfliteSpeciesClassifier implements SpeciesClassifier {
  TfliteSpeciesClassifier({
    required InferenceEngine engine,
    required this.preprocess,
  }) : _engine = engine;

  final InferenceEngine _engine;

  /// Converts the user's image into the model's input tensor.
  final ModelInput Function(PickedImage image) preprocess;

  @override
  bool get isModelAvailable => true;

  @override
  Future<ClassificationResult> classify(PickedImage image) async {
    final ModelInput input;
    try {
      input = preprocess(image);
    } catch (error) {
      return ClassificationResult.failure(
        ClassificationFailureReason.invalidInput,
        failureDetail: 'Could not prepare the image: $error',
      );
    }

    final List<double> scores;
    try {
      scores = await _engine.run(input);
    } catch (error) {
      return ClassificationResult.failure(
        ClassificationFailureReason.inferenceFailed,
        failureDetail: 'Inference failed: $error',
      );
    }

    if (scores.length != _engine.labels.length) {
      return ClassificationResult.failure(
        ClassificationFailureReason.inferenceFailed,
        failureDetail: 'Model returned ${scores.length} scores for '
            '${_engine.labels.length} labels; label order and output size disagree.',
      );
    }

    return ClassificationResult.fromScores(
      labels: _engine.labels,
      scores: scores,
    );
  }
}
