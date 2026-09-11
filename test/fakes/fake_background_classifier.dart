import 'dart:async';

import 'package:fieldsnap/models/picked_image.dart';
import 'package:fieldsnap/services/background_runner.dart';
import 'package:fieldsnap/services/classification_result.dart';
import 'package:fieldsnap/services/species_classifier.dart';

/// Records how the classifier was driven, so tests can assert that a background runner was used
/// rather than claiming it.
class RecordingBackgroundRunner implements BackgroundRunner {
  RecordingBackgroundRunner({this.isolate = true});

  final bool isolate;
  int calls = 0;

  @override
  bool get isIsolate => isolate;

  @override
  Future<R> run<A, R>(FutureOr<R> Function(A) work, A argument) async {
    calls += 1;
    return await work(argument);
  }
}

/// Fake classifier whose scores are explicit, with a switch for the runner type.
class FakeScoresClassifier implements SpeciesClassifier {
  FakeScoresClassifier({
    required this.scores,
    required this.labels,
    this.available = true,
    this.failure,
    this.delay = Duration.zero,
    RecordingBackgroundRunner? runner,
  }) : runner = runner ?? RecordingBackgroundRunner();

  final List<double> scores;
  final List<String> labels;
  final bool available;
  final String? failure;
  final Duration delay;
  final RecordingBackgroundRunner runner;

  int callCount = 0;

  @override
  bool get isModelAvailable => available;

  @override
  Future<ClassificationResult> classify(PickedImage image) async {
    callCount += 1;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (failure != null) {
      return ClassificationResult.failure(
        ClassificationFailureReason.inferenceFailed,
        failureDetail: failure,
      );
    }
    // Route through the runner so "used a background boundary" is observable, and so the fake
    // fails loudly if the scores and labels disagree.
    return runner.run<void, ClassificationResult>(
      (_) => ClassificationResult.fromScores(labels: labels, scores: scores),
      null,
    );
  }
}
