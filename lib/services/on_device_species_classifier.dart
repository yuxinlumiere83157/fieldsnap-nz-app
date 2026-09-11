import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import '../models/picked_image.dart';
import 'background_runner.dart';
import 'classification_result.dart';
import 'image_preprocessor.dart';
import 'model_labels.dart';
import 'species_classifier.dart';
import 'tflite_inference_engine.dart';
import 'tflite_species_classifier.dart';

/// Result of one background inference run, in plain transferable types.
class _BackgroundResult {
  const _BackgroundResult({
    required this.probabilities,
    this.failureReason,
    this.failureDetail,
  });

  final List<double> probabilities;
  final String? failureReason;
  final String? failureDetail;
}

class _Request {
  const _Request({required this.imagePath, required this.modelBytes, required this.labels});

  final String imagePath;
  final Uint8List modelBytes;
  final List<String> labels;
}

/// The function that actually runs on the background isolate.
///
/// Top-level so isolates can call it. It decodes, resizes and rescales the image
/// (`ImagePreprocessor` implements the documented spec) and then runs the TFLite interpreter —
/// all off the UI isolate, which is Milestone 1's NFR3.
Future<_BackgroundResult> _classifyInBackground(_Request request) async {
  try {
    final ModelInput input = const ImagePreprocessor()
        .fromImageBytes(_readFile(request.imagePath));
    final TfliteInferenceEngine engine = await TfliteInferenceEngine.loadFromBytes(
      bytes: request.modelBytes,
      expectedLabels: request.labels,
      threads: 2,
    );
    try {
      final List<double> scores = await engine.run(input);
      return _BackgroundResult(probabilities: scores);
    } finally {
      engine.dispose();
    }
  } catch (error) {
    return _BackgroundResult(
      probabilities: const <double>[],
      failureReason: BackgroundFailure.inferenceFailed,
      failureDetail: '$error',
    );
  }
}

Uint8List _readFile(String path) => File(path).readAsBytesSync();

/// Real on-device classifier: preprocessing and inference on a background isolate, with the UI
/// isolate only receiving the final scores.
///
/// It also exposes [prepare], which loads the label list and model bytes ahead of the first
/// classification so the user-visible latency is inference rather than asset loading.
class OnDeviceSpeciesClassifier implements SpeciesClassifier, ClassifierPreparation {
  OnDeviceSpeciesClassifier._({
    required BackgroundRunner runner,
    required this.labels,
    required this.modelAsset,
    required Uint8List modelBytes,
  })  : _runner = runner,
        _modelBytes = modelBytes;

  final BackgroundRunner _runner;
  final List<String> labels;
  final String modelAsset;
  final Uint8List _modelBytes;

  bool _prepared = false;

  /// Whether a real isolate is used. False only when a test injects the inline runner.
  bool get usesIsolate => _runner.isIsolate;

  static Future<OnDeviceSpeciesClassifier> create({
    required ModelLabels labels,
    String assetPath = TfliteInferenceEngine.defaultAsset,
    BackgroundRunner runner = const IsolateBackgroundRunner(),
  }) async {
    final ByteData data = await rootBundle.load(assetPath);
    return OnDeviceSpeciesClassifier._(
      runner: runner,
      labels: labels.classes,
      modelAsset: assetPath,
      modelBytes: data.buffer.asUint8List(),
    );
  }

  @override
  bool get isModelAvailable => true;

  /// Preprocessing is deferred to the background isolate, so this only records readiness. Kept so
  /// the ViewModel can express "the user has an image; get ready" without knowing the details.
  @override
  Future<void> prepare(PickedImage image) async {
    _prepared = true;
  }

  bool get isPrepared => _prepared;

  @override
  Future<ClassificationResult> classify(PickedImage image) async {
    final _BackgroundResult outcome;
    try {
      outcome = await _runner.run<_Request, _BackgroundResult>(
        _classifyInBackground,
        _Request(imagePath: image.path, modelBytes: _modelBytes, labels: labels),
      );
    } catch (error) {
      return ClassificationResult.failure(
        ClassificationFailureReason.inferenceFailed,
        failureDetail: 'Background inference failed: $error',
      );
    }
    if (outcome.failureReason != null) {
      return ClassificationResult.failure(
        ClassificationFailureReason.inferenceFailed,
        failureDetail: outcome.failureDetail,
      );
    }
    try {
      return ClassificationResult.fromScores(
        labels: labels,
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
