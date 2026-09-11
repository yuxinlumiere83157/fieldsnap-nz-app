import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../models/picked_image.dart';
import 'classification_result.dart';
import 'species_classifier.dart';

/// Runs a piece of work off the Flutter UI isolate.
///
/// The whole point of this boundary is that inference must not run on the main isolate
/// (Milestone 1's NFR3). It is an interface, not a bare `compute()` call, so widget tests can
/// inject a fake and assert the UI never blocks, and so the real implementation is the only
/// place that knows about `Isolate`.
abstract class BackgroundRunner {
  /// Runs [work] on a background isolate and returns its result.
  ///
  /// [work] must be a top-level or static function (isolates cannot capture closures), and its
  /// argument and return value must be transferable.
  Future<R> run<A, R>(FutureOr<R> Function(A) work, A argument);

  /// Whether this runner actually executes elsewhere. A fake returns false, which lets a test
  /// assert "this path does not block the UI" without pretending it is a real isolate.
  bool get isIsolate;
}

/// Production implementation: a real `Isolate.run`.
class IsolateBackgroundRunner implements BackgroundRunner {
  const IsolateBackgroundRunner();

  @override
  bool get isIsolate => true;

  @override
  Future<R> run<A, R>(FutureOr<R> Function(A) work, A argument) {
    return Isolate.run<R>(() async => await work(argument));
  }
}

/// In-process runner used by tests and by platforms where spawning is undesirable.
///
/// It deliberately reports [isIsolate] = false so no test can accidentally claim that this path
/// proves off-main-isolate execution.
class InlineBackgroundRunner implements BackgroundRunner {
  const InlineBackgroundRunner();

  @override
  bool get isIsolate => false;

  @override
  Future<R> run<A, R>(FutureOr<R> Function(A) work, A argument) async {
    return await work(argument);
  }
}

/// The transferable payload for one classification: the accepted image and the model to use.
class ClassificationRequest {
  const ClassificationRequest({
    required this.imagePath,
    required this.modelBytes,
    required this.labels,
    this.modelLabel = 'model',
  });

  final String imagePath;

  /// Raw `.tflite` bytes, so the isolate needs no Flutter asset bundle.
  final Uint8List modelBytes;

  /// Label order, exactly as recorded with the model.
  final List<String> labels;

  /// Human-readable model name, echoed back in the result for the history record.
  final String modelLabel;
}

/// Outcome of one background classification, transferable across the isolate boundary.
class BackgroundClassification {
  const BackgroundClassification({
    required this.probabilities,
    required this.labels,
    required this.modelLabel,
    this.failureReason,
    this.failureDetail,
  });

  final List<double> probabilities;
  final List<String> labels;
  final String modelLabel;
  final String? failureReason;
  final String? failureDetail;

  bool get isSuccess => failureReason == null;
}

/// Reasons this layer can report without importing the inference implementation.
class BackgroundFailure {
  static const String invalidInput = 'invalidInput';
  static const String inferenceFailed = 'inferenceFailed';
}

/// Signature of the function that actually runs inside the background isolate.
///
/// Kept as a function type so tests can substitute a deterministic implementation.
typedef ClassifyInBackground = Future<BackgroundClassification> Function(
    ClassificationRequest request);

/// Classifier that performs preprocessing and inference on a background isolate and maps the
/// result into the domain [ClassificationResult] used by the ViewModel.
class BackgroundSpeciesClassifier implements SpeciesClassifier {
  BackgroundSpeciesClassifier({
    required BackgroundRunner runner,
    required ClassifyInBackground classify,
  })  : _runner = runner,
        _classify = classify;

  final BackgroundRunner _runner;
  final ClassifyInBackground _classify;

  ClassificationRequest? lastRequest;
  int callCount = 0;

  @override
  bool get isModelAvailable => true;

  /// True only when a real isolate is used. Surfaced so the UI/tests can state the fact instead
  /// of assuming it.
  bool get usesIsolate => _runner.isIsolate;

  @override
  Future<ClassificationResult> classify(PickedImage image) async {
    callCount += 1;
    try {
      final BackgroundClassification outcome =
          await _runner.run<ClassificationRequest, BackgroundClassification>(
        _classify,
        lastRequest!,
      );
      if (!outcome.isSuccess) {
        return ClassificationResult.failure(
          outcome.failureReason == BackgroundFailure.invalidInput
              ? ClassificationFailureReason.invalidInput
              : ClassificationFailureReason.inferenceFailed,
          failureDetail: outcome.failureDetail,
        );
      }
      return ClassificationResult.fromScores(
        labels: outcome.labels,
        scores: outcome.probabilities,
      );
    } catch (error) {
      return ClassificationResult.failure(
        ClassificationFailureReason.inferenceFailed,
        failureDetail: '$error',
      );
    }
  }
}
