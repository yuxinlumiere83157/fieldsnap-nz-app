import 'package:flutter/foundation.dart';

import '../models/pick_errors.dart';
import '../models/picked_image.dart';
import '../services/camera_image_input.dart';
import '../services/classification_result.dart';
import '../services/confidence_policy.dart';
import '../services/history_repository.dart';
import '../services/image_input.dart';
import '../services/quality_gate.dart';
import '../services/species_cards.dart';
import '../services/species_classifier.dart';

/// Device or library the user picked from.
enum CaptureChannel { gallery, camera }

enum SelectionStatus { idle, picking, ready }

/// High-level outcome the view renders.
enum ResultKind {
  /// No attempt yet.
  none,

  /// Inference is running on a background isolate.
  running,

  /// Models were applied but the confidence policy asked for another photo (FR4).
  uncertain,

  /// A species is being asserted; the card carries its details.
  identified,

  /// Something failed; [ClassifierState.errorMessage] explains it.
  failed,
}

/// Immutable UI state. One object per frame keeps the view free of business rules.
@immutable
class ClassifierState {
  const ClassifierState({
    this.status = SelectionStatus.idle,
    this.image,
    this.error,
    this.quality,
    this.resultKind = ResultKind.none,
    this.candidates = const <SpeciesCandidate>[],
    this.confidence,
    this.card,
    this.errorMessage,
    this.latencyMs = 0,
    this.modelAvailable = false,
    this.modelAsset = '',
  });

  final SelectionStatus status;
  final PickedImage? image;
  final PickError? error;
  final QualityDecision? quality;

  final ResultKind resultKind;
  final List<SpeciesCandidate> candidates;
  final ConfidenceDecision? confidence;
  final SpeciesCard? card;
  final String? errorMessage;
  final int latencyMs;
  final bool modelAvailable;
  final String modelAsset;

  bool get isPicking => status == SelectionStatus.picking;
  bool get hasImage => image != null;
  bool get isClassifying => resultKind == ResultKind.running;
  bool get hasQualityPass => quality?.isAcceptable ?? false;
  bool get canClassify =>
      hasImage && hasQualityPass && modelAvailable && !isClassifying;

  /// The species being asserted, or null in every other state (including uncertain).
  SpeciesCandidate? get topCandidate =>
      candidates.isEmpty ? null : candidates.first;

  ClassifierState copyWith({
    SelectionStatus? status,
    PickedImage? image,
    PickError? error,
    QualityDecision? quality,
    ResultKind? resultKind,
    List<SpeciesCandidate>? candidates,
    ConfidenceDecision? confidence,
    SpeciesCard? card,
    String? errorMessage,
    int? latencyMs,
    bool? modelAvailable,
    String? modelAsset,
    bool clearImage = false,
    bool clearError = false,
    bool clearQuality = false,
    bool clearResult = false,
  }) {
    return ClassifierState(
      status: status ?? this.status,
      image: clearImage ? null : (image ?? this.image),
      error: clearError ? null : (error ?? this.error),
      quality: clearQuality ? null : (quality ?? this.quality),
      // `clearResult` wipes *everything* derived from a classification. The earlier version only
      // cleared `card` and `errorMessage`, so replacing the image left `resultKind`,
      // `candidates`, `confidence` and `latencyMs` pointing at the previous photo: the result panel
      // kept rendering a species (and a latency) for an image that was no longer selected.
      resultKind: (clearResult || clearImage) ? ResultKind.none : (resultKind ?? this.resultKind),
      candidates: (clearResult || clearImage)
          ? const <SpeciesCandidate>[]
          : (candidates ?? this.candidates),
      confidence: (clearResult || clearImage) ? null : (confidence ?? this.confidence),
      card: (clearResult || clearImage) ? null : (card ?? this.card),
      errorMessage: (clearResult || clearImage) ? null : (errorMessage ?? this.errorMessage),
      latencyMs: (clearResult || clearImage) ? 0 : (latencyMs ?? this.latencyMs),
      modelAvailable: modelAvailable ?? this.modelAvailable,
      modelAsset: modelAsset ?? this.modelAsset,
    );
  }

  @override
  String toString() => 'ClassifierState(status: $status, result: $resultKind, '
      'hasImage: $hasImage, quality: ${quality?.kind}, modelAvailable: $modelAvailable)';
}

/// ViewModel for the capture screen (MVVM `View -> ViewModel -> Services`).
///
/// It owns no widgets and no model runtime: it talks to [ImageInput], the quality gate, the
/// [SpeciesClassifier] boundary, [SpeciesCardRepository] and [HistoryRepository] only. Every
/// dependency is injected, so the whole flow is unit testable with fakes — including the
/// "inference must not run on the UI isolate" property, because the classifier fake reports
/// whether a background runner was used.
class ClassifierViewModel extends ChangeNotifier {
  ClassifierViewModel({
    required ImageInput imageInput,
    required SpeciesClassifier classifier,
    ImageQualityGate qualityGate = const ImageQualityGate(),
    SpeciesCardRepository? cards,
    HistoryRepository? history,
    ConfidencePolicy? confidencePolicy,
    String modelAsset = '',
    String modelLabel = '',
  })  : _imageInput = imageInput,
        _classifier = classifier,
        _qualityGate = qualityGate,
        _cards = cards,
        _history = history,
        _policy = confidencePolicy ?? const ConfidencePolicy(kDeployedConfidencePolicy),
        _modelAsset = modelAsset,
        _modelLabel = modelLabel {
    _state = ClassifierState(
      modelAvailable: _classifier.isModelAvailable,
      modelAsset: _modelAsset,
    );
  }

  final ImageInput _imageInput;
  /// Visible for tests that assert which runner the classifier used.
  SpeciesClassifier get classifier => _classifier;
  final SpeciesClassifier _classifier;
  final ImageQualityGate _qualityGate;
  final SpeciesCardRepository? _cards;
  final HistoryRepository? _history;
  final ConfidencePolicy _policy;
  final String _modelAsset;
  final String _modelLabel;

  late ClassifierState _state;

  /// Bumped whenever the selected image changes (new pick, clear). A classification captures it
  /// and discards its own completion if the value has moved on, so a slow result can never be
  /// attached to a photo the user chose afterwards.
  int _selectionGeneration = 0;

  ClassifierState get state => _state;

  /// The policy actually in force, so the UI can state whether the threshold is validated.
  ConfidencePolicyConfig get confidenceConfig => _policy.config;

  /// Honest, state-dependent explanation of what recognition can do right now.
  String get classificationUnavailableMessage {
    if (!_classifier.isModelAvailable) {
      return 'Species recognition is not available in this build: no model is bundled, and no '
          'result is being invented.';
    }
    if (!_state.hasImage) {
      return 'Choose a photo to run the bundled model on this device.';
    }
    if (!_state.hasQualityPass) {
      return 'The image did not pass the quality check yet.';
    }
    return 'Ready to classify on this device.';
  }

  /// Explains the confidence policy, including whether its threshold came from the validation
  /// calibration (it does, as of Iteration 3) or is still a placeholder.
  String get confidencePolicyNote {
    final ConfidencePolicyConfig config = _policy.config;
    final String base =
        'Accept threshold ${(config.acceptThreshold * 100).toStringAsFixed(0)}%'
        '${config.marginThreshold == null ? '' : ', at least '
            '${(config.marginThreshold! * 100).toStringAsFixed(0)}% ahead of the runner-up'}';
    return config.isValidated
        ? '$base (calibrated on the validation split; coverage and accepted accuracy are recorded '
            'in docs/iteration_3_calibration_report.md).'
        : '$base. This threshold is a placeholder and has NOT been derived from validation data.';
  }

  Future<void> pickImage({CaptureChannel channel = CaptureChannel.gallery}) async {
    if (_state.isPicking) {
      return;
    }
    // A new selection supersedes anything in flight.
    _selectionGeneration++;
    _update(_state.copyWith(
      status: SelectionStatus.picking,
      clearError: true,
      clearResult: true,
    ));

    final PickImageResult result = await _select(channel);

    if (!result.isSuccess) {
      final PickError error = result.error!;
      if (error.isUserCancellation) {
        _update(_state.copyWith(
          status: _state.hasImage ? SelectionStatus.ready : SelectionStatus.idle,
          clearError: true,
        ));
        return;
      }
      _update(ClassifierState(
        status: SelectionStatus.idle,
        error: error,
        modelAvailable: _state.modelAvailable,
        modelAsset: _state.modelAsset,
      ));
      return;
    }

    final PickedImage image = result.image!;
    _update(_state.copyWith(
      status: SelectionStatus.ready,
      image: image,
      clearError: true,
      clearResult: true,
    ));
    _runQualityGate(image);
  }

  Future<PickImageResult> _select(CaptureChannel channel) {
    if (channel == CaptureChannel.gallery) {
      return _imageInput.pickFromGallery();
    }
    final ImageInput input = _imageInput;
    if (input is CameraImageInput) {
      return input.captureFromCamera();
    }
    // No camera channel wired up: report it as a typed failure rather than pretending.
    return Future<PickImageResult>.value(const PickImageResult.failure(
      PickError(
        reason: PickErrorReason.permissionDenied,
        detail: 'This build has no camera channel; use the gallery instead.',
      ),
    ));
  }

  /// Runs the explainable brightness/blur gate on the accepted image.
  void _runQualityGate(PickedImage image) {
    try {
      final QualityDecision decision = _qualityGate.evaluateFile(image);
      _update(_state.copyWith(quality: decision, clearResult: true));
    } catch (error) {
      _update(_state.copyWith(
        quality: const QualityDecision.failed(
          kind: QualityFailureKind.undecodable,
          metrics: QualityMetrics(brightness: 0, laplacianVariance: 0),
          measured: 0,
          threshold: 0,
        ),
        resultKind: ResultKind.none,
        errorMessage: 'The selected file could not be read for a quality check.',
      ));
    }
  }

  /// Asks the classifier to prepare the current image (preprocessing happens off the UI isolate).
  Future<void> prepare() async {
    final PickedImage? image = _state.image;
    if (image == null || !_state.modelAvailable) {
      return;
    }
    final SpeciesClassifier classifier = _classifier;
    if (classifier is ClassifierPreparation) {
      await (classifier as ClassifierPreparation).prepare(image);
    }
  }

  /// Runs the model on a background isolate and interprets the result (FR3 + FR4).
  Future<void> classify() async {
    final PickedImage? image = _state.image;
    if (image == null || _state.isClassifying || !_state.modelAvailable) {
      return;
    }
    final QualityDecision? quality = _state.quality;
    if (quality == null || !quality.isAcceptable) {
      _update(_state.copyWith(
        resultKind: ResultKind.failed,
        errorMessage:
            quality?.explanation ?? 'The image did not pass the quality check.',
      ));
      return;
    }

    final int generation = _selectionGeneration;
    _update(_state.copyWith(resultKind: ResultKind.running, clearResult: true));
    final Stopwatch stopwatch = Stopwatch()..start();
    final ClassificationResult result = await _classifier.classify(image);
    stopwatch.stop();

    if (generation != _selectionGeneration) {
      // The user replaced or cleared the image while the model was running. This result describes
      // the previous photo, so it is dropped rather than rendered against the new one.
      return;
    }

    if (!result.isSuccess) {
      _update(_state.copyWith(
        resultKind: ResultKind.failed,
        errorMessage: result.failureDetail ??
            'The model could not classify this image (${result.failureReason}).',
        latencyMs: stopwatch.elapsedMilliseconds,
      ));
      return;
    }

    final List<double> scores = result.candidates
        .map((SpeciesCandidate candidate) => candidate.confidence)
        .toList(growable: false);
    final ConfidenceDecision decision = _policy.decide(scores);
    final SpeciesCandidate top = result.candidates.first;
    final SpeciesCard? card = _cards?.bySlug(top.commonName);
    final SpeciesCandidate decorated = card == null
        ? top
        : SpeciesCandidate(
            commonName: card.commonName,
            scientificName: card.scientificName,
            confidence: top.confidence,
          );
    final List<SpeciesCandidate> candidates = <SpeciesCandidate>[
      decorated,
      ...result.candidates.skip(1),
    ];

    _update(_state.copyWith(
      resultKind: decision.isUncertain ? ResultKind.uncertain : ResultKind.identified,
      candidates: candidates,
      confidence: decision,
      card: card,
      latencyMs: stopwatch.elapsedMilliseconds,
    ));

    await _saveHistory(decorated, decision, quality);
  }

  /// Persists the outcome (FR6). No photograph is written to the database.
  Future<void> _saveHistory(
    SpeciesCandidate top,
    ConfidenceDecision decision,
    QualityDecision quality,
  ) async {
    final HistoryRepository? history = _history;
    if (history == null) {
      return;
    }
    final String runnerUp =
        _state.candidates.length > 1 ? _state.candidates[1].commonName : '';
    final double runnerUpConfidence =
        _state.candidates.length > 1 ? _state.candidates[1].confidence : 0.0;
    await history.save(HistoryRecord(
      createdAt: DateTime.now(),
      topSlug: top.commonName,
      topCommonName: top.commonName,
      topScientificName: top.scientificName,
      topConfidence: top.confidence,
      runnerUpSlug: runnerUp,
      runnerUpConfidence: runnerUpConfidence,
      wasUncertain: decision.isUncertain,
      confidenceThreshold: decision.config.acceptThreshold,
      confidencePolicyValidated: decision.config.isValidated,
      qualityBrightness: quality.metrics?.brightness ?? 0,
      qualityLaplacianVariance: quality.metrics?.laplacianVariance ?? 0,
      qualityAccepted: quality.isAcceptable,
      modelLabel: _modelLabel,
      modelAsset: _modelAsset,
    ));
  }

  /// Clears the preview and the derived result, so recognition cannot be triggered without an
  /// image (the rule Iteration 0 established).
  void clearImage() {
    _selectionGeneration++;
    _update(ClassifierState(
      status: SelectionStatus.idle,
      modelAvailable: _state.modelAvailable,
      modelAsset: _modelAsset,
    ));
  }

  void _update(ClassifierState next) {
    _state = next;
    notifyListeners();
  }
}
