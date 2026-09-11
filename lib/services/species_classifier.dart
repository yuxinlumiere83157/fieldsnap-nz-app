import '../models/picked_image.dart';
import 'classification_result.dart';

/// Optional capability: a classifier that needs the image handed to it before classification
/// (for example to preprocess it on a background isolate). The ViewModel calls this when the
/// classifier supports it and otherwise does nothing.
abstract class ClassifierPreparation {
  Future<void> prepare(PickedImage image);
}

/// Boundary between the UI layer and whatever runs the model.
///
/// Milestone 1 requires that only the inference service touches the model
/// runtime, so widgets and view models must depend on this interface only.
abstract class SpeciesClassifier {
  /// True only when a real model is loaded and able to run inference.
  ///
  /// Iteration 0 ships no model, so this is false and the UI must say so
  /// instead of showing invented species or confidences.
  bool get isModelAvailable;

  /// Classifies [image]; returns a typed failure when no model is present.
  Future<ClassificationResult> classify(PickedImage image);
}
