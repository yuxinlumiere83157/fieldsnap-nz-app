import 'dart:io';

import 'package:fieldsnap/models/pick_errors.dart';
import 'package:fieldsnap/services/file_system_image_input.dart';
import 'package:flutter/services.dart' show MissingPluginException, PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

/// Camera-path behaviour of the real adapter (FR1's second half).
///
/// These use a stub [ImagePicker] so they are deterministic. They prove the adapter maps camera
/// failures onto the recoverable `permissionDenied` / `cancelled` outcomes; they do **not** prove
/// that a physical device's camera works, which needs a device run.
void main() {
  late Directory tempDir;
  late File sample;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('fieldsnap_camera_test');
    sample = File('${tempDir.path}/shot.jpg')
      ..writeAsBytesSync(<int>[
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature is enough for the
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // adapter's size/dimension step
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
        0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
        0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
        0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
        0x42, 0x60, 0x82,
      ]);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('a captured photo is returned as a PickedImage', () async {
    final FileSystemImageInput input = FileSystemImageInput(
      picker: _StubPicker(sample.path, source: ImageSource.camera),
    );

    final PickImageResult result = await input.captureFromCamera();

    expect(result.isSuccess, isTrue);
    expect(result.image!.path, sample.path);
  });

  test('backing out of the camera is a cancellation, not an error', () async {
    final FileSystemImageInput input = FileSystemImageInput(
      picker: _StubPicker(null, source: ImageSource.camera),
    );

    final PickImageResult result = await input.captureFromCamera();

    expect(result.isSuccess, isFalse);
    expect(result.error!.reason, PickErrorReason.cancelled);
  });

  test('a denied camera permission is reported as recoverable', () async {
    final FileSystemImageInput input = FileSystemImageInput(
      picker: _ThrowingPicker(
        PlatformException(code: 'camera_access_denied', message: 'denied'),
        source: ImageSource.camera,
      ),
    );

    final PickImageResult result = await input.captureFromCamera();

    expect(result.error!.reason, PickErrorReason.permissionDenied);
    expect(result.error!.detail, contains('camera_access_denied'));
  });

  test('a gallery platform failure keeps its own reason', () async {
    final FileSystemImageInput input = FileSystemImageInput(
      picker: _ThrowingPicker(
        PlatformException(code: 'multiple_request', message: 'busy'),
        source: ImageSource.gallery,
      ),
    );

    final PickImageResult result = await input.pickFromGallery();

    expect(result.error!.reason, PickErrorReason.platformFailure);
  });

  test('a missing camera plugin is reported as recoverable, not as a crash', () async {
    final FileSystemImageInput input = FileSystemImageInput(
      picker: _ThrowingPicker(
        MissingPluginException('no implementation'),
        source: ImageSource.camera,
      ),
    );

    final PickImageResult result = await input.captureFromCamera();

    expect(result.error!.reason, PickErrorReason.permissionDenied);
  });
}

class _StubPicker extends ImagePicker {
  _StubPicker(this.path, {required this.source});

  final String? path;
  final ImageSource source;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    expect(source, this.source);
    return path == null ? null : XFile(path!);
  }
}

class _ThrowingPicker extends ImagePicker {
  _ThrowingPicker(this.error, {required this.source});

  final Object error;
  final ImageSource source;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    expect(source, this.source);
    throw error;
  }
}
