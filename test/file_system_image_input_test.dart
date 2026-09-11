import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fieldsnap/models/pick_errors.dart';
import 'package:fieldsnap/services/file_system_image_input.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

/// A research-grade, CC0 New Zealand record used to prove the import guard does
/// not reject realistic input.
///
/// Source: iNaturalist observation of *Hemiphaga novaeseelandiae* (kererū) in New
/// Zealand (`place_id=6803`), photo 160561636, `license_code: cc0`,
/// attribution "no rights reserved", original 2048x1365 = 2.8 MP, 815 KB.
/// It is downloaded at test time and never committed. Measured 2026-09-11: NZ
/// research-grade CC0/CC BY photos sit around 2.8 MP median, so this should
/// always be accepted by the guard.
const String _realSampleUrl =
    'https://inaturalist-open-data.s3.amazonaws.com/photos/160561636/original.jpg';

/// Tests for the adapter's own behaviour at the file-system level.
///
/// These use a temporary directory and a stub picker on purpose: no device and no
/// Photo Picker. They do NOT prove that the real Android Photo Picker returns
/// files; that stays an on-device verification item (see docs/traceability.md).
void main() {
  /// 1x1 PNG, so the header-parsing path can be checked against real bytes.
  final Uint8List pngBytes = Uint8List.fromList(<int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82,
  ]);

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fieldsnap_adapter_test');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('a real image file becomes a PickedImage with size and pixel dimensions',
      () async {
    final File file = File('${tempDir.path}/sample.png')..writeAsBytesSync(pngBytes);
    final FileSystemImageInput input = FileSystemImageInput(
      picker: _StubImagePicker(file.path),
    );

    final result = await input.pickFromGallery();

    expect(result.isSuccess, isTrue);
    final image = result.image!;
    expect(image.path, file.path);
    expect(image.sizeBytes, pngBytes.length);
    expect(image.width, 1);
    expect(image.height, 1);
    expect(image.readableSize, endsWith('B'));
    expect(image.readableDimensions, '1 x 1 px');
  });

  test('a non-image file is still previewable data but reports unknown pixels',
      () async {
    final File file = File('${tempDir.path}/notes.txt')
      ..writeAsStringSync('definitely not an image');
    final FileSystemImageInput input = FileSystemImageInput(
      picker: _StubImagePicker(file.path),
    );

    final result = await input.pickFromGallery();

    expect(result.isSuccess, isTrue);
    expect(result.image!.width, isNull);
    expect(result.image!.height, isNull);
    expect(result.image!.readableDimensions, 'dimensions unavailable');
  });

  test('a file that disappears between pick and read is a typed read failure',
      () async {
    final File file = File('${tempDir.path}/gone.png')..writeAsBytesSync(pngBytes);
    file.deleteSync();
    final FileSystemImageInput input = FileSystemImageInput(
      picker: _StubImagePicker(file.path),
    );

    final PickImageResult result = await input.pickFromGallery();

    expect(result.isSuccess, isFalse);
    expect(result.error!.reason, PickErrorReason.readFailed);
  });

  test('an empty file is rejected instead of producing a broken preview',
      () async {
    final File file = File('${tempDir.path}/empty.png')..writeAsBytesSync(<int>[]);
    final FileSystemImageInput input = FileSystemImageInput(
      picker: _StubImagePicker(file.path),
    );

    final PickImageResult result = await input.pickFromGallery();

    expect(result.isSuccess, isFalse);
    expect(result.error!.reason, PickErrorReason.readFailed);
  });

  test('a file above the import size limit is rejected before it is read',
      () async {
    final File file = File('${tempDir.path}/huge.jpg');
    // Sparse file: 33 MiB logical size without allocating the bytes.
    final RandomAccessFile raf = file.openSync(mode: FileMode.write);
    raf.truncateSync(FileSystemImageInput.maxFileSizeBytes + 1024);
    raf.closeSync();

    final FileSystemImageInput input = FileSystemImageInput(
      picker: _StubImagePicker(file.path),
    );

    final PickImageResult result = await input.pickFromGallery();

    expect(result.isSuccess, isFalse);
    expect(result.error!.reason, PickErrorReason.readFailed);
    expect(result.error!.detail, contains('import limit'));
  });

  test('an image above the pixel limit is rejected from its header alone',
      () async {
    // A structurally valid PNG declaring 30000x30000 (900 MP): the IHDR chunk and
    // its CRC are correct, and the file is only 196 bytes, so this proves the
    // guard reads the declared size and never needs the pixels to exist.
    const String hugePngBase64 =
        'iVBORw0KGgoAAAANSUhEUgAAdTAAAHUwCAYAAABmJ/i6AAAAi0lEQVR42u3BgQAAAADDoPlT3+AEVQEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAcA3U0AABniyooAAAAABJRU5ErkJggg==';
    final File file = File('${tempDir.path}/huge_pixels.png')
      ..writeAsBytesSync(base64Decode(hugePngBase64));

    final FileSystemImageInput input = FileSystemImageInput(
      picker: _StubImagePicker(file.path),
    );

    final PickImageResult result = await input.pickFromGallery();

    expect(result.isSuccess, isFalse);
    expect(result.error!.reason, PickErrorReason.readFailed);
    expect(result.error!.detail, contains('pixel limit'));
  });

  test('a large file whose pixels cannot be parsed is rejected by the size guard',
      () async {
    // The pixel limit can only apply to a parseable header, so an unparseable file
    // must fall back to its encoded size; otherwise the guard is bypassable.
    final File file = File('${tempDir.path}/undecodable.bin');
    final RandomAccessFile raf = file.openSync(mode: FileMode.write);
    raf.writeFromSync('NOPE-not-an-image'.codeUnits);
    raf.truncateSync(FileSystemImageInput.maxUndecodableFileSizeBytes + 4096);
    raf.closeSync();

    final FileSystemImageInput input = FileSystemImageInput(
      picker: _StubImagePicker(file.path),
    );

    final PickImageResult result = await input.pickFromGallery();

    expect(result.isSuccess, isFalse);
    expect(result.error!.reason, PickErrorReason.readFailed);
    expect(result.error!.detail, contains('undecodable'));
  });

  test('a real ~2.8 MP JPEG from the data set is accepted by the import guard',
      () async {
    final File file = File('${tempDir.path}/real_sample.jpg');
    final ProcessResult curl = await Process.run('curl', <String>[
      '-fsSL',
      '-A',
      'FieldSnapNZ-the course/0.1 (student feasibility check)',
      '-o',
      file.path,
      _realSampleUrl,
    ]);
    if (curl.exitCode != 0 || !file.existsSync() || file.lengthSync() == 0) {
      markTestSkipped('no network access to fetch a real sample photo');
      return;
    }

    final FileSystemImageInput input = FileSystemImageInput(
      picker: _StubImagePicker(file.path),
    );

    final PickImageResult result = await input.pickFromGallery();

    expect(result.isSuccess, isTrue, reason: 'real photos must not be rejected');
    expect(result.image!.width, greaterThan(1));
    expect(result.image!.height, greaterThan(1));
    expect(result.image!.sizeBytes, lessThanOrEqualTo(
      FileSystemImageInput.maxFileSizeBytes,
    ));
  });

  test('a plugin-level failure becomes a typed error instead of a crash',
      () async {
    final FileSystemImageInput input = FileSystemImageInput(
      picker: _FailingImagePicker(),
    );

    final PickImageResult result = await input.pickFromGallery();

    expect(result.isSuccess, isFalse);
    expect(result.error!.reason, PickErrorReason.platformFailure);
    expect(result.error!.detail, contains('boom'));
  });

  test('a user cancellation is not treated as an error', () async {
    final FileSystemImageInput input = FileSystemImageInput(
      picker: _CancellingImagePicker(),
    );

    final PickImageResult result = await input.pickFromGallery();

    expect(result.isSuccess, isFalse);
    expect(result.error!.reason, PickErrorReason.cancelled);
    expect(result.error!.isUserCancellation, isTrue);
  });
}

/// Returns the given path, like the real picker returns a cache file path.
class _StubImagePicker extends ImagePicker {
  _StubImagePicker(this.path);

  final String path;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    return XFile(path);
  }
}

/// Returns no file, which is what the real picker does when the user backs out.
class _CancellingImagePicker extends ImagePicker {
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    return null;
  }
}

/// Throws the way a broken or missing platform implementation does.
class _FailingImagePicker extends ImagePicker {
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    throw StateError('boom: platform implementation not registered');
  }
}
