import 'package:fieldsnap/models/picked_image.dart';
import 'package:fieldsnap/services/classification_result.dart';
import 'package:fieldsnap/services/species_classifier.dart';

/// Deterministic classifier double for tests.
///
/// It exists so a widget test can render the "model available" branch without
/// shipping a model. Any candidate it returns is explicitly labelled as fake and
/// must never be wired into the production app.
class FakeSpeciesClassifier implements SpeciesClassifier {
  FakeSpeciesClassifier({this.available = true, this.candidates});

  final bool available;
  final List<SpeciesCandidate>? candidates;

  int callCount = 0;

  @override
  bool get isModelAvailable => available;

  @override
  Future<ClassificationResult> classify(PickedImage image) async {
    callCount += 1;
    if (!available) {
      return const ClassificationResult.failure(
        ClassificationFailureReason.modelUnavailable,
      );
    }
    return ClassificationResult.success(
      candidates ??
          const <SpeciesCandidate>[
            SpeciesCandidate(
              commonName: 'FAKE - test only',
              scientificName: 'Fakus testus',
              confidence: 0.99,
            ),
          ],
    );
  }
}
