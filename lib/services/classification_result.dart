/// One candidate species returned by the (future) on-device classifier.
class SpeciesCandidate {
  const SpeciesCandidate({
    required this.commonName,
    required this.scientificName,
    required this.confidence,
  });

  final String commonName;
  final String scientificName;

  /// Calibrated probability in the range 0.0 - 1.0.
  final double confidence;
}

/// Why classification could not produce candidates.
enum ClassificationFailureReason {
  /// No quantized model is bundled with the app yet (Iteration 0 state).
  modelUnavailable,

  /// A model exists but the runtime could not load or run it.
  inferenceFailed,

  /// The image could not be preprocessed into the model's input tensor.
  invalidInput,
}

/// Result of a classification attempt: either candidates, or a typed failure.
class ClassificationResult {
  const ClassificationResult.success(this.candidates)
      : failureReason = null,
        failureDetail = null;

  const ClassificationResult.failure(
    this.failureReason, {
    this.failureDetail,
  }) : candidates = const <SpeciesCandidate>[];

  final List<SpeciesCandidate> candidates;
  final ClassificationFailureReason? failureReason;
  final String? failureDetail;

  bool get isSuccess => failureReason == null;

  /// Top-3 candidates, best first (FR3's required output shape).
  List<SpeciesCandidate> get top3 =>
      candidates.length <= 3 ? candidates : candidates.sublist(0, 3);

  /// Builds a result from a raw score vector and its label order.
  ///
  /// Used by the background/isolate layer, which transfers plain numbers rather than domain
  /// objects. Throws [ArgumentError] when labels and scores disagree, because that means the
  /// label order no longer matches the model.
  factory ClassificationResult.fromScores({
    required List<String> labels,
    required List<double> scores,
  }) {
    if (labels.length != scores.length) {
      throw ArgumentError(
        'label/score mismatch: ${labels.length} labels for ${scores.length} scores',
      );
    }
    final List<int> order = List<int>.generate(scores.length, (int i) => i)
      ..sort((int a, int b) => scores[b].compareTo(scores[a]));
    return ClassificationResult.success(
      order
          .take(3)
          .map((int i) => SpeciesCandidate(
                commonName: labels[i],
                scientificName: '',
                confidence: scores[i],
              ))
          .toList(growable: false),
    );
  }
}
