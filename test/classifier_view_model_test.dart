import 'dart:io';

import 'package:fieldsnap/models/pick_errors.dart';
import 'package:fieldsnap/services/confidence_policy.dart';
import 'package:fieldsnap/services/history_repository.dart';
import 'package:fieldsnap/services/quality_gate.dart';
import 'package:fieldsnap/services/species_cards.dart';
import 'package:fieldsnap/viewmodels/classifier_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'fakes/fake_background_classifier.dart';
import 'fakes/fake_camera_image_input.dart';
import 'fakes/fake_image_input.dart';

/// Builds a decodable image file so the quality gate has something real to measure.
///
/// [detailed] controls the blur metric: a checkerboard has high Laplacian variance (sharp) while
/// a flat colour is about as blurry as an image can get. [luma] controls brightness.
File writeSample({
  required Directory dir,
  String name = 'sample.png',
  double luma = 0.5,
  bool detailed = true,
}) {
  final int base = (luma * 255).round().clamp(0, 255);
  final img.Image image = img.Image(width: 224, height: 224);
  for (int y = 0; y < 224; y++) {
    for (int x = 0; x < 224; x++) {
      // An 8-pixel checkerboard measures ~4400 Laplacian variance on the 0-255 scale, well above
      // the 250 threshold, while a flat image measures 0. See docs/quality_gate.md.
      final bool dark = detailed && ((x ~/ 8 + y ~/ 8) % 2 == 0);
      final int value = dark ? (base * 0.15).round() : base;
      image.setPixelRgb(x, y, value, value, value);
    }
  }
  final File file = File('${dir.path}/$name')..writeAsBytesSync(img.encodePng(image));
  return file;
}

void main() {
  late Directory tempDir;
  late File sharpFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('fieldsnap_vm_test');
    sharpFile = writeSample(dir: tempDir, luma: 0.5, detailed: true);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  FakeCameraImageInput pickerFor(File file) =>
      FakeCameraImageInput(path: file.path, sizeBytes: file.lengthSync());

  SpeciesCardRepository twoCards() => SpeciesCardRepository.fromJsonString('''
{"species":[
 {"slug":"kereru","common_name":"Kererū","scientific_name":"Hemiphaga novaeseelandiae",
  "group":"bird","maori_name":"Kererū","identification":"Large white-chested pigeon.",
  "habitat":"Forest canopy and urban trees.","status":"native"},
 {"slug":"tui","common_name":"Tūī","scientific_name":"Prosthemadera novaeseelandiae",
  "group":"bird","maori_name":"Tūī","identification":"Dark honeyeater with white throat tuft.",
  "habitat":"Native forest and gardens.","status":"native"}
]}''');

  ClassifierViewModel build({
    FakeCameraImageInput? picker,
    FakeScoresClassifier? classifier,
    HistoryRepository? history,
    ConfidencePolicy? policy,
    SpeciesCardRepository? cards,
  }) {
    return ClassifierViewModel(
      imageInput: picker ?? pickerFor(sharpFile),
      classifier: classifier ??
          FakeScoresClassifier(
            labels: const <String>['kereru', 'tui', 'nikau', 'kowhai'],
            scores: const <double>[0.8, 0.1, 0.05, 0.05],
          ),
      history: history,
      confidencePolicy: policy,
      cards: cards,
      modelAsset: 'test-model.tflite',
      modelLabel: 'test-model',
    );
  }

  group('initial state', () {
    test('starts idle with no image and no quality verdict', () {
      final ClassifierViewModel model = build();
      expect(model.state.status, SelectionStatus.idle);
      expect(model.state.hasImage, isFalse);
      expect(model.state.quality, isNull);
      expect(model.state.resultKind, ResultKind.none);
      expect(model.state.canClassify, isFalse);
      expect(model.state.modelAvailable, isTrue);
    });

    test('classify does nothing without an image', () async {
      final FakeScoresClassifier classifier = FakeScoresClassifier(
        labels: const <String>['a'],
        scores: const <double>[1],
      );
      final ClassifierViewModel model = build(classifier: classifier);
      await model.classify();
      expect(classifier.callCount, 0);
      expect(model.state.resultKind, ResultKind.none);
    });
  });

  group('camera capture (FR1)', () {
    test('the camera channel is used when asked', () async {
      final FakeCameraImageInput picker = pickerFor(sharpFile);
      final ClassifierViewModel model = build(picker: picker);

      await model.pickImage(channel: CaptureChannel.camera);

      expect(picker.cameraCalls, 1);
      expect(picker.galleryCalls, 0);
      expect(model.state.hasImage, isTrue);
      expect(model.state.hasQualityPass, isTrue);
    });

    test('a denied camera permission is recoverable, and the gallery still works', () async {
      final FakeCameraImageInput picker = FakeCameraImageInput.denyingPermission();
      final ClassifierViewModel model = build(picker: picker);

      await model.pickImage(channel: CaptureChannel.camera);
      expect(model.state.error?.reason, PickErrorReason.permissionDenied);
      expect(model.state.hasImage, isFalse);
      expect(model.state.canClassify, isFalse);

      await model.pickImage(channel: CaptureChannel.gallery);
      expect(model.state.hasImage, isTrue);
      expect(model.state.error, isNull);
    });

    test('cancelling the camera keeps the previous image', () async {
      final FakeCameraImageInput picker = pickerFor(sharpFile);
      final ClassifierViewModel model = build(picker: picker);
      await model.pickImage(channel: CaptureChannel.gallery);
      final String kept = model.state.image!.path;

      picker.cameraResult = const PickImageResult.failure(
        PickError(reason: PickErrorReason.cancelled),
      );
      await model.pickImage(channel: CaptureChannel.camera);

      expect(model.state.image!.path, kept);
      expect(model.state.error, isNull);
    });

    test('a build without a camera channel reports it instead of pretending', () async {
      final FakeImageInput galleryOnly = FakeImageInput(path: sharpFile.path);
      final ClassifierViewModel model = ClassifierViewModel(
        imageInput: galleryOnly,
        classifier: FakeScoresClassifier(
          labels: const <String>['a'],
          scores: const <double>[1],
        ),
      );

      await model.pickImage(channel: CaptureChannel.camera);

      expect(model.state.error?.reason, PickErrorReason.permissionDenied);
      expect(galleryOnly.callCount, 0);
    });
  });

  group('quality gate (FR2)', () {
    test('a dark image is rejected with a measured explanation', () async {
      final File dark = writeSample(dir: tempDir, name: 'dark.png', luma: 0.02);
      final ClassifierViewModel model = build(picker: pickerFor(dark));

      await model.pickImage();

      expect(model.state.quality!.isAcceptable, isFalse);
      expect(model.state.quality!.kind, QualityFailureKind.tooDark);
      expect(model.state.quality!.explanation, contains('Too dark'));
      expect(model.state.canClassify, isFalse);
    });

    test('a flat image is rejected as having too little detail', () async {
      final File flat = writeSample(dir: tempDir, name: 'flat.png', detailed: false);
      final ClassifierViewModel model = build(picker: pickerFor(flat));

      await model.pickImage();

      expect(model.state.quality!.kind, QualityFailureKind.tooBlurry);
      expect(model.state.canClassify, isFalse);
    });

    test('a blown-out image is rejected as overexposed', () async {
      // Uniformly bright (a checkerboard at luma 1.0 averages only ~0.6, which is not blown out).
      final File bright = writeSample(
        dir: tempDir,
        name: 'bright.png',
        luma: 1.0,
        detailed: false,
      );
      final ClassifierViewModel model = build(picker: pickerFor(bright));

      await model.pickImage();

      expect(model.state.quality!.kind, QualityFailureKind.tooBright);
      expect(model.state.quality!.explanation, contains('Overexposed'));
    });

    test('classify refuses to run when the quality gate failed', () async {
      final File flat = writeSample(dir: tempDir, name: 'flat2.png', detailed: false);
      final FakeScoresClassifier classifier = FakeScoresClassifier(
        labels: const <String>['a'],
        scores: const <double>[1],
      );
      final ClassifierViewModel model = build(picker: pickerFor(flat), classifier: classifier);

      await model.pickImage();
      await model.classify();

      expect(classifier.callCount, 0);
      expect(model.state.resultKind, ResultKind.failed);
      expect(model.state.errorMessage, isNotNull);
    });
  });

  group('classification (FR3) through a background boundary', () {
    test('a confident result names the species and scores it', () async {
      final ClassifierViewModel model = build();

      await model.pickImage();
      await model.classify();

      expect(model.state.resultKind, ResultKind.identified);
      expect(model.state.candidates, isNotEmpty);
      expect(model.state.candidates.first.confidence, 0.8);
      expect(model.state.latencyMs, greaterThanOrEqualTo(0));
    });

    test('inference is driven through the background runner', () async {
      final FakeScoresClassifier classifier = FakeScoresClassifier(
        labels: const <String>['kereru', 'tui'],
        scores: const <double>[0.9, 0.1],
      );
      final ClassifierViewModel model = build(classifier: classifier);

      await model.pickImage();
      await model.classify();

      expect(classifier.runner.calls, 1,
          reason: 'the classifier must be driven through its runner');
      expect(classifier.runner.isIsolate, isTrue);
    });

    test('the runner reports whether it is a real isolate, and fakes can be inline', () {
      final FakeScoresClassifier inline = FakeScoresClassifier(
        labels: const <String>['kereru'],
        scores: const <double>[0.9],
        runner: RecordingBackgroundRunner(isolate: false),
      );
      expect(inline.runner.isIsolate, isFalse);
    });

    test('an inference failure is reported with its detail', () async {
      final FakeScoresClassifier failing = FakeScoresClassifier(
        labels: const <String>['kereru'],
        scores: const <double>[0.9],
        failure: 'interpreter could not be created',
      );
      final ClassifierViewModel model = build(classifier: failing);

      await model.pickImage();
      await model.classify();

      expect(model.state.resultKind, ResultKind.failed);
      expect(model.state.errorMessage, contains('interpreter could not be created'));
    });

    test('the species card is attached when cards are available', () async {
      final ClassifierViewModel model = build(cards: twoCards());

      await model.pickImage();
      await model.classify();

      expect(model.state.card, isNotNull);
      expect(model.state.card!.commonName, 'Kererū');
      expect(model.state.candidates.first.scientificName, 'Hemiphaga novaeseelandiae');
    });

    test('an unavailable model keeps recognition disabled and honest', () {
      final ClassifierViewModel model = build(
        classifier: FakeScoresClassifier(
          labels: const <String>['a'],
          scores: const <double>[1],
          available: false,
        ),
      );
      expect(model.state.canClassify, isFalse);
      expect(model.classificationUnavailableMessage, contains('not available'));
    });
  });

  group('confidence policy (FR4)', () {
    test('an explicit low threshold accepts the top candidate', () async {
      final ClassifierViewModel model = build(
        policy: const ConfidencePolicy(ConfidencePolicyConfig(
          acceptThreshold: 0.30,
          marginThreshold: 0.05,
        )),
      );

      await model.pickImage();
      await model.classify();

      expect(model.state.resultKind, ResultKind.identified);
      expect(model.state.confidence!.verdict, ConfidenceVerdict.accept);
    });

    test('an explicit high threshold produces the Uncertain state', () async {
      final ClassifierViewModel model = build(
        policy: const ConfidencePolicy(ConfidencePolicyConfig(
          acceptThreshold: 0.95,
          marginThreshold: 0.01,
        )),
      );

      await model.pickImage();
      await model.classify();

      expect(model.state.resultKind, ResultKind.uncertain);
      expect(model.state.confidence!.isUncertain, isTrue);
      expect(model.state.confidence!.reason, contains('below the accept threshold'));
      expect(model.state.card, isNull);
    });

    test('a narrow margin produces Uncertain even with a decent top score', () async {
      final ClassifierViewModel model = build(
        classifier: FakeScoresClassifier(
          labels: const <String>['kereru', 'tui'],
          scores: const <double>[0.42, 0.40],
        ),
        policy: const ConfidencePolicy(ConfidencePolicyConfig(
          acceptThreshold: 0.30,
          marginThreshold: 0.10,
        )),
      );

      await model.pickImage();
      await model.classify();

      expect(model.state.resultKind, ResultKind.uncertain);
      expect(model.state.confidence!.reason, contains('too close'));
    });

    test('the default threshold is the calibrated one and is marked validated', () {
      final ClassifierViewModel model = build();
      expect(model.confidenceConfig.isValidated, isTrue);
      expect(model.confidencePolicyNote, contains('calibrated on the validation split'));
      // It came from the validation sweep, so its value must match the calibration artefact.
      expect(model.confidenceConfig.acceptThreshold, 0.37);
    });
  });

  group('history (FR6)', () {
    test('an identified result is saved without the photograph', () async {
      final InMemoryHistoryRepository history = InMemoryHistoryRepository();
      final ClassifierViewModel model = build(history: history);

      await model.pickImage();
      await model.classify();

      final List<HistoryRecord> records = await history.loadAll();
      expect(records.length, 1);
      expect(records.first.topCommonName, 'kereru');
      expect(records.first.wasUncertain, isFalse);
      expect(records.first.confidencePolicyValidated, isTrue);
      expect(records.first.modelLabel, 'test-model');
      final String keys = records.first.toJson().keys.join(',');
      expect(keys.contains('path'), isFalse);
      expect(keys.contains('image'), isFalse);
    });

    test('an uncertain result is saved as uncertain', () async {
      final InMemoryHistoryRepository history = InMemoryHistoryRepository();
      final ClassifierViewModel model = build(
        history: history,
        policy: const ConfidencePolicy(ConfidencePolicyConfig(acceptThreshold: 0.99)),
      );

      await model.pickImage();
      await model.classify();

      expect((await history.loadAll()).single.wasUncertain, isTrue);
    });

    test('the quality measurements are recorded with each row', () async {
      final InMemoryHistoryRepository history = InMemoryHistoryRepository();
      final ClassifierViewModel model = build(history: history);

      await model.pickImage();
      await model.classify();

      final HistoryRecord record = (await history.loadAll()).single;
      expect(record.qualityBrightness, greaterThan(0));
      expect(record.qualityLaplacianVariance, greaterThan(0));
      expect(record.qualityAccepted, isTrue);
    });
  });


  group('stale-result regression (audit Phase A)', () {
    test('replacing the image clears candidates, confidence, card, latency and result kind',
        () async {
      final FakeCameraImageInput picker = pickerFor(sharpFile);
      final ClassifierViewModel model = build(picker: picker, cards: twoCards());
      await model.pickImage();
      await model.classify();

      // Sanity: there is a full result to clear.
      expect(model.state.resultKind, ResultKind.identified);
      expect(model.state.candidates, isNotEmpty);
      expect(model.state.confidence, isNotNull);
      expect(model.state.card, isNotNull);

      // Replace the image: point the same fake at a different file and pick again.
      final File other = writeSample(dir: tempDir, name: 'replacement.png');
      picker.path = other.path;
      picker.sizeBytes = other.lengthSync();
      await model.pickImage();

      expect(model.state.image!.path, other.path, reason: 'the replacement is selected');
      // Nothing from the previous identification may survive the replacement.
      expect(model.state.resultKind, ResultKind.none,
          reason: 'the result panel must stop rendering after a replacement');
      expect(model.state.candidates, isEmpty);
      expect(model.state.confidence, isNull);
      expect(model.state.card, isNull);
      expect(model.state.latencyMs, 0, reason: 'a stale latency must not be shown for a new image');
      expect(model.state.errorMessage, isNull);
    });

    test('an in-flight classification cannot attach its result to a different image',
        () async {
      final FakeScoresClassifier slow = FakeScoresClassifier(
        labels: const <String>['kereru', 'tui'],
        scores: const <double>[0.95, 0.05],
        delay: const Duration(milliseconds: 150),
      );
      final FakeCameraImageInput picker = pickerFor(sharpFile);
      final ClassifierViewModel model = build(picker: picker, classifier: slow);

      await model.pickImage();
      final Future<void> inFlight = model.classify();

      // While classification is running, the user replaces the image.
      final File other = writeSample(dir: tempDir, name: 'raced.png');
      picker.path = other.path;
      picker.sizeBytes = other.lengthSync();
      await model.pickImage();
      await inFlight;

      expect(model.state.image!.path, other.path, reason: 'the new image stays selected');
      expect(model.state.resultKind, ResultKind.none,
          reason: 'the completion belongs to the previous image and must be dropped');
      expect(model.state.candidates, isEmpty);
      expect(slow.callCount, greaterThan(0), reason: 'the classification did run');
    });

    test('an in-flight classification cannot attach its result after the image is cleared',
        () async {
      final FakeScoresClassifier slow = FakeScoresClassifier(
        labels: const <String>['kereru', 'tui'],
        scores: const <double>[0.9, 0.1],
        delay: const Duration(milliseconds: 150),
      );
      final ClassifierViewModel model = build(classifier: slow);

      await model.pickImage();
      final Future<void> inFlight = model.classify();
      model.clearImage();
      await inFlight;

      expect(model.state.image, isNull);
      expect(model.state.resultKind, ResultKind.none);
      expect(model.state.candidates, isEmpty);
      expect(model.state.confidence, isNull);
    });
  });

  group('clearing', () {
    test('clearImage resets everything derived from the image', () async {
      final ClassifierViewModel model = build();
      await model.pickImage();
      await model.classify();
      expect(model.state.candidates, isNotEmpty);

      model.clearImage();

      expect(model.state.status, SelectionStatus.idle);
      expect(model.state.image, isNull);
      expect(model.state.quality, isNull);
      expect(model.state.candidates, isEmpty);
      expect(model.state.resultKind, ResultKind.none);
    });
  });
}
