import 'dart:io';

import 'package:fieldsnap/main.dart';
import 'package:fieldsnap/models/pick_errors.dart';
import 'package:fieldsnap/services/confidence_policy.dart';
import 'package:fieldsnap/services/history_repository.dart';
import 'package:fieldsnap/services/species_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'fakes/fake_background_classifier.dart';
import 'fakes/fake_camera_image_input.dart';

/// Widget tests for the Iteration 2 core workflow: capture (gallery **and** camera) -> quality gate
/// -> on-device classification -> species card / Uncertain -> history.
///
/// The classifier is a fake, so these prove UI wiring and the state machine; the real model path is
/// covered by the host and on-device conformance tests.
void main() {
  late Directory tempDir;
  late File sharpFile;
  late File flatFile;

  File writeSample(String name, {double luma = 0.5, bool detailed = true}) {
    final int base = (luma * 255).round().clamp(0, 255);
    final img.Image image = img.Image(width: 224, height: 224);
    for (int y = 0; y < 224; y++) {
      for (int x = 0; x < 224; x++) {
        final bool dark = detailed && ((x ~/ 8 + y ~/ 8) % 2 == 0);
        final int value = dark ? (base * 0.15).round() : base;
        image.setPixelRgb(x, y, value, value, value);
      }
    }
    final File file = File('${tempDir.path}/$name')
      ..writeAsBytesSync(img.encodePng(image));
    return file;
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('fieldsnap_widget_test');
    sharpFile = writeSample('sharp.png');
    flatFile = writeSample('flat.png', detailed: false);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  SpeciesCardRepository cards() => SpeciesCardRepository.fromJsonString(
        '{"species":['
        '{"slug":"kereru","common_name":"Kererū","scientific_name":"Hemiphaga novaeseelandiae",'
        '"group":"bird","maori_name":"Kererū",'
        '"identification":"Large white-chested pigeon with a whooshing wingbeat.",'
        '"habitat":"Forest canopy and urban trees.","status":"native"},'
        '{"slug":"tui","common_name":"Tūī","scientific_name":"Prosthemadera novaeseelandiae",'
        '"group":"bird","maori_name":"Tūī",'
        '"identification":"Dark honeyeater with a white throat tuft.",'
        '"habitat":"Native forest and gardens.","status":"native"},'
        '{"slug":"nikau","common_name":"Nīkau","scientific_name":"Rhopalostylis sapida",'
        '"group":"plant","maori_name":"Nīkau",'
        '"identification":"The only mainland New Zealand palm.",'
        '"habitat":"Lowland forest.","status":"native"}]}',
      );

  Future<void> pumpApp(
    WidgetTester tester, {
    required FakeCameraImageInput input,
    FakeScoresClassifier? classifier,
    HistoryRepository? history,
    ConfidencePolicy? policy,
  }) async {
    tester.view.physicalSize = const Size(1200, 3400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(FieldSnapApp(
      imageInput: input,
      classifier: classifier ??
          FakeScoresClassifier(
            labels: const <String>['kereru', 'tui', 'nikau'],
            scores: const <double>[0.82, 0.1, 0.08],
          ),
      cards: cards(),
      history: history,
      confidencePolicy: policy ?? const ConfidencePolicy(kDeployedConfidencePolicy),
      modelAsset: 'assets/models/fieldsnap_float.tflite',
      modelLabel: 'fieldsnap_float.tflite',
    ));
    await tester.pumpAndSettle();
  }

  Finder buttonWithLabel(String label) => find.byWidgetPredicate(
        (Widget widget) =>
            widget is ButtonStyleButton &&
            find
                .descendant(of: find.byWidget(widget), matching: find.text(label))
                .evaluate()
                .isNotEmpty,
        description: 'button labelled "$label"',
      );

  Future<void> tapControl(WidgetTester tester, String label) async {
    final Finder target = buttonWithLabel(label);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets('initial state offers both capture channels and blocks identification',
      (WidgetTester tester) async {
    await pumpApp(tester, input: FakeCameraImageInput(path: sharpFile.path));

    expect(find.text('FieldSnap NZ'), findsOneWidget);
    expect(buttonWithLabel('Select from gallery'), findsOneWidget);
    expect(buttonWithLabel('Take photo'), findsOneWidget);
    expect(find.text('No image selected yet'), findsOneWidget);

    final FilledButton identify =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Identify species'));
    expect(identify.onPressed, isNull,
        reason: 'no image yet, so identification stays disabled');

    // The threshold is now calibrated on the validation split; the UI must say so, and must not
    // claim it was validated when the policy is not.
    expect(find.textContaining('calibrated on the validation split'), findsOneWidget);
  });

  testWidgets('gallery pick runs the quality gate and enables identification',
      (WidgetTester tester) async {
    final FakeCameraImageInput input =
        FakeCameraImageInput(path: sharpFile.path, sizeBytes: sharpFile.lengthSync());
    await pumpApp(tester, input: input);

    await tapControl(tester, 'Select from gallery');

    expect(input.galleryCalls, 1);
    expect(input.cameraCalls, 0);
    expect(find.text('Step 2 - Image quality'), findsOneWidget);
    expect(find.textContaining('Image quality accepted'), findsOneWidget);
    expect(find.textContaining('Brightness'), findsOneWidget);
    final FilledButton identify =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Identify species'));
    expect(identify.onPressed, isNotNull);
  });

  testWidgets('camera capture uses the camera channel, not the gallery',
      (WidgetTester tester) async {
    final FakeCameraImageInput input =
        FakeCameraImageInput(path: sharpFile.path, sizeBytes: sharpFile.lengthSync());
    await pumpApp(tester, input: input);

    await tapControl(tester, 'Take photo');

    expect(input.cameraCalls, 1);
    expect(input.galleryCalls, 0);
    expect(find.textContaining('Image quality accepted'), findsOneWidget);
  });

  testWidgets('a denied camera permission explains itself and offers the gallery',
      (WidgetTester tester) async {
    await pumpApp(tester, input: FakeCameraImageInput.denyingPermission());

    await tapControl(tester, 'Take photo');

    expect(find.text('Camera unavailable'), findsOneWidget);
    expect(find.textContaining('choose an existing photo from the gallery'), findsOneWidget);
    expect(buttonWithLabel('Choose another image'), findsOneWidget);
    // The gallery path is still offered, which is the recovery route.
    expect(buttonWithLabel('Select from gallery'), findsOneWidget);
  });

  testWidgets('a poor-quality image is rejected with measured values',
      (WidgetTester tester) async {
    final FakeCameraImageInput input =
        FakeCameraImageInput(path: flatFile.path, sizeBytes: flatFile.lengthSync());
    await pumpApp(tester, input: input);

    await tapControl(tester, 'Select from gallery');

    expect(find.textContaining('Too little detail'), findsOneWidget);
    expect(find.textContaining('Sharpness'), findsOneWidget);
    final FilledButton identify =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Identify species'));
    expect(identify.onPressed, isNull, reason: 'a failed quality gate blocks identification');
  });

  testWidgets('identifying shows the species card with confidence and a learning card',
      (WidgetTester tester) async {
    final FakeCameraImageInput input =
        FakeCameraImageInput(path: sharpFile.path, sizeBytes: sharpFile.lengthSync());
    await pumpApp(tester, input: input);

    await tapControl(tester, 'Select from gallery');
    await tapControl(tester, 'Identify species');

    expect(find.text('Result'), findsOneWidget);
    expect(find.text('Kererū'), findsWidgets);
    expect(find.textContaining('Hemiphaga novaeseelandiae'), findsWidgets);
    expect(find.textContaining('Confidence 82.0%'), findsOneWidget);
    expect(find.text('Learning card'), findsOneWidget);
    expect(find.textContaining('white-chested pigeon'), findsOneWidget);
    // The other candidates are listed too (top-3, FR3).
    expect(find.textContaining('Tūī'), findsWidgets);
  });

  testWidgets('a high threshold produces the Uncertain state instead of a species assertion',
      (WidgetTester tester) async {
    final FakeCameraImageInput input =
        FakeCameraImageInput(path: sharpFile.path, sizeBytes: sharpFile.lengthSync());
    await pumpApp(
      tester,
      input: input,
      policy: const ConfidencePolicy(ConfidencePolicyConfig(acceptThreshold: 0.99)),
    );

    await tapControl(tester, 'Select from gallery');
    await tapControl(tester, 'Identify species');

    expect(find.textContaining('Uncertain - try another photo'), findsOneWidget);
    expect(find.textContaining('not asserting'), findsOneWidget);
    expect(find.text('Learning card'), findsNothing);
    expect(find.textContaining('Closest candidates'), findsOneWidget);
  });

  testWidgets('the result is saved locally and visible in the history screen',
      (WidgetTester tester) async {
    final InMemoryHistoryRepository history = InMemoryHistoryRepository();
    final FakeCameraImageInput input =
        FakeCameraImageInput(path: sharpFile.path, sizeBytes: sharpFile.lengthSync());
    await pumpApp(tester, input: input, history: history);

    await tapControl(tester, 'Select from gallery');
    await tapControl(tester, 'Identify species');

    expect(await history.count(), 1);
    await tester.tap(find.byTooltip('Identification history'));
    await tester.pumpAndSettle();

    expect(find.text('Identification history'), findsOneWidget);
    expect(find.textContaining('threshold'), findsWidgets);
    expect(find.textContaining('%'), findsWidgets);
  });

  testWidgets('clearing the selection returns to the empty state',
      (WidgetTester tester) async {
    final FakeCameraImageInput input =
        FakeCameraImageInput(path: sharpFile.path, sizeBytes: sharpFile.lengthSync());
    await pumpApp(tester, input: input);

    await tapControl(tester, 'Select from gallery');
    await tapControl(tester, 'Clear selection');

    expect(find.text('No image selected yet'), findsOneWidget);
    expect(find.text('Step 2 - Image quality'), findsNothing);
  });

  testWidgets('cancelling the camera keeps the existing image and shows no error',
      (WidgetTester tester) async {
    final FakeCameraImageInput input =
        FakeCameraImageInput(path: sharpFile.path, sizeBytes: sharpFile.lengthSync());
    await pumpApp(tester, input: input);

    await tapControl(tester, 'Select from gallery');
    input.cameraResult = const PickImageResult.failure(
      PickError(reason: PickErrorReason.cancelled),
    );
    await tapControl(tester, 'Take photo');

    expect(find.textContaining('Image quality accepted'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });
}
