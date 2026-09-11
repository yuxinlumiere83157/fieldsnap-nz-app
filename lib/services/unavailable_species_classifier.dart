import '../models/picked_image.dart';
import 'classification_result.dart';
import 'species_classifier.dart';

/// Honest placeholder for a not-yet-integrated on-device model.
///
/// Iteration 0 has no trained or quantized model and therefore no labels file,
/// so this implementation reports `modelUnavailable` for every request. It must
/// never invent a species, a confidence value, or a latency figure.
class UnavailableSpeciesClassifier implements SpeciesClassifier {
  const UnavailableSpeciesClassifier();

  @override
  bool get isModelAvailable => false;

  @override
  Future<ClassificationResult> classify(PickedImage image) async {
    return const ClassificationResult.failure(
      ClassificationFailureReason.modelUnavailable,
      failureDetail: 'No LiteRT/TFLite model is bundled in Iteration 0.',
    );
  }
}
