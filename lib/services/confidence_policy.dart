/// Turns raw model scores into an explicit accept/uncertain decision (FR4).
///
/// Configuration, not policy-by-code: the threshold lives in [ConfidencePolicyConfig] so it can
/// be replaced by evidence later and so tests can inject explicit values. **No production
/// threshold is claimed as validated yet** — the default below is deliberately marked as
/// unvalidated and must be derived from validation data and frozen before any test-set
/// evaluation, per Milestone 1 §7.
class ConfidencePolicyConfig {
  const ConfidencePolicyConfig({
    required this.acceptThreshold,
    this.marginThreshold,
    this.isValidated = false,
    this.provenance = 'not derived from validation data yet',
  });

  /// A prediction is accepted only when the top score is at least this high.
  final double acceptThreshold;

  /// Optional: also require the top score to lead the runner-up by this much.
  final double? marginThreshold;

  /// Whether the threshold came from a documented validation procedure. Defaults to false so an
  /// accidental use of an unvalidated threshold is visible in the record.
  final bool isValidated;

  /// Where the number came from, for the history record and the report.
  final String provenance;

  Map<String, Object?> toJson() => <String, Object?>{
        'accept_threshold': acceptThreshold,
        'margin_threshold': marginThreshold,
        'is_validated': isValidated,
        'provenance': provenance,
      };
}

/// Calibrated configuration (Iteration 3).
///
/// Derived on the validation split by the pre-registered procedure in
/// `docs/confidence_threshold_calibration_protocol.md` and frozen with its provenance in
/// `artifacts/confidence_threshold_calibration.json`:
///
///  * threshold **0.37** — the highest accepted accuracy among thresholds with coverage >= 0.70
///    (coverage 0.7117, accepted accuracy 0.5948);
///  * **M1's target of accepted accuracy >= 0.90 is NOT met** at any threshold that keeps coverage
///    at or above 0.70. Reported as measured, not adjusted by moving the target.
///
/// The margin rule remains **off**: calibrating a second, interacting rule on the same split would
/// reduce the calibration's credibility, and the offset is documented in the calibration report.
const ConfidencePolicyConfig kCalibratedConfidencePolicy = ConfidencePolicyConfig(
  acceptThreshold: 0.37,
  marginThreshold: null,
  isValidated: true,
  provenance: 'validation-split sweep, coverage >= 0.70 rule; see '
      'artifacts/confidence_threshold_calibration.json (run id recorded there)',
);

/// The configuration the app uses. Named for what it is, so no call site can read as if the
/// threshold were still a placeholder.
const ConfidencePolicyConfig kDeployedConfidencePolicy = kCalibratedConfidencePolicy;

/// The decision the UI renders.
enum ConfidenceVerdict {
  /// Show the species.
  accept,

  /// Show "Uncertain - try another photo" instead of asserting a species.
  uncertain,
}

class ConfidenceDecision {
  const ConfidenceDecision({
    required this.verdict,
    required this.topScore,
    required this.runnerUpScore,
    required this.config,
    required this.reason,
  });

  final ConfidenceVerdict verdict;
  final double topScore;
  final double runnerUpScore;
  final ConfidencePolicyConfig config;
  final String reason;

  bool get isUncertain => verdict == ConfidenceVerdict.uncertain;

  Map<String, Object?> toJson() => <String, Object?>{
        'verdict': verdict.name,
        'top_score': double.parse(topScore.toStringAsFixed(4)),
        'runner_up_score': double.parse(runnerUpScore.toStringAsFixed(4)),
        'reason': reason,
        'config': config.toJson(),
      };
}

/// Applies a [ConfidencePolicyConfig] to a score vector.
class ConfidencePolicy {
  const ConfidencePolicy(this.config);

  final ConfidencePolicyConfig config;

  ConfidenceDecision decide(List<double> scores) {
    if (scores.isEmpty) {
      return ConfidenceDecision(
        verdict: ConfidenceVerdict.uncertain,
        topScore: 0,
        runnerUpScore: 0,
        config: config,
        reason: 'the model returned no scores',
      );
    }
    final List<double> sorted = List<double>.from(scores)..sort((double a, double b) => b.compareTo(a));
    final double top = sorted.first;
    final double second = sorted.length > 1 ? sorted[1] : 0.0;

    if (top < config.acceptThreshold) {
      return ConfidenceDecision(
        verdict: ConfidenceVerdict.uncertain,
        topScore: top,
        runnerUpScore: second,
        config: config,
        reason: 'top confidence ${top.toStringAsFixed(3)} is below the accept threshold '
            '${config.acceptThreshold.toStringAsFixed(3)}',
      );
    }
    final double? margin = config.marginThreshold;
    if (margin != null && (top - second) < margin) {
      return ConfidenceDecision(
        verdict: ConfidenceVerdict.uncertain,
        topScore: top,
        runnerUpScore: second,
        config: config,
        reason: 'the top two candidates are too close (margin '
            '${(top - second).toStringAsFixed(3)} < ${margin.toStringAsFixed(3)})',
      );
    }
    return ConfidenceDecision(
      verdict: ConfidenceVerdict.accept,
      topScore: top,
      runnerUpScore: second,
      config: config,
      reason: 'accepted with confidence ${top.toStringAsFixed(3)}',
    );
  }
}
