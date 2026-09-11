import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/pick_errors.dart';
import '../models/picked_image.dart';
import 'camera_image_input.dart';
import 'image_input.dart';

/// Production [ImageInput]: opens the platform's own picker for ONE existing
/// local image and reports it as app-owned data.
///
/// Design notes (Iteration 0):
/// - Uses the platform Photo Picker through `image_picker` (no custom UI, no
///   cloud, no network access).
/// - Shows no image-quality judgement yet; FR2 (blur/brightness gate) is still
///   pending and is not faked here.
/// - Never throws for expected outcomes; every failure is a typed [PickError].
class FileSystemImageInput implements CameraImageInput {
  FileSystemImageInput({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<PickImageResult> pickFromGallery() =>
      _pickFrom(ImageSource.gallery, PickErrorReason.readFailed);

  /// FR1's camera half.
  ///
  /// A refused camera permission, a device with no camera app, or a plugin-level failure all come
  /// back as [PickErrorReason.permissionDenied] so the UI offers the gallery as a recovery path
  /// instead of dead-ending the task.
  @override
  Future<PickImageResult> captureFromCamera() =>
      _pickFrom(ImageSource.camera, PickErrorReason.permissionDenied);

  Future<PickImageResult> _pickFrom(ImageSource source, PickErrorReason fallbackReason) async {
    XFile? file;
    try {
      file = await _picker.pickImage(source: source, requestFullMetadata: false);
    } on PlatformException catch (error) {
      // image_picker reports denied camera permission as a platform exception with the code
      // `camera_access_denied`; anything else from the camera path is treated the same way so the
      // user always gets the gallery fallback.
      final PickErrorReason reason = source == ImageSource.camera
          ? PickErrorReason.permissionDenied
          : PickErrorReason.platformFailure;
      return PickImageResult.failure(
        PickError(reason: reason, detail: '${error.code}: ${error.message}'),
      );
    } on MissingPluginException catch (error) {
      return PickImageResult.failure(
        PickError(
          reason: source == ImageSource.camera
              ? PickErrorReason.permissionDenied
              : PickErrorReason.platformFailure,
          detail: 'Image picker plugin is not available on this platform: $error',
        ),
      );
    } catch (error) {
      // A broken or unregistered platform implementation must never crash the
      // screen; it becomes a typed failure with a recovery path.
      return PickImageResult.failure(
        PickError(
          reason: fallbackReason == PickErrorReason.permissionDenied &&
                  source == ImageSource.camera
              ? PickErrorReason.permissionDenied
              : PickErrorReason.platformFailure,
          detail: 'Unexpected picker failure: $error',
        ),
      );
    }

    if (file == null) {
      return const PickImageResult.failure(
        PickError(reason: PickErrorReason.cancelled),
      );
    }

    final File local = File(file.path);
    final int sizeBytes;
    try {
      sizeBytes = await local.length();
    } on FileSystemException catch (error) {
      return PickImageResult.failure(
        PickError(
          reason: PickErrorReason.readFailed,
          detail: error.message,
        ),
      );
    }

    if (sizeBytes <= 0) {
      return const PickImageResult.failure(
        PickError(
          reason: PickErrorReason.readFailed,
          detail: 'Selected file is empty.',
        ),
      );
    }

    if (sizeBytes > maxFileSizeBytes) {
      return PickImageResult.failure(
        PickError(
          reason: PickErrorReason.readFailed,
          detail: 'Selected file is ${_mib(sizeBytes)}, above the '
              '${_mib(maxFileSizeBytes)} import limit.',
        ),
      );
    }

    final _DimensionsReading reading = await _readDimensions(local);
    if (reading.tooLarge) {
      return PickImageResult.failure(
        PickError(
          reason: PickErrorReason.readFailed,
          detail: 'Selected image has ${reading.pixels} pixels, above the '
              '$maxPixelCount-pixel limit.',
        ),
      );
    }

    if (reading.undecodable && sizeBytes > maxUndecodableFileSizeBytes) {
      // Nothing could be learned about the pixels, so the only remaining guard is
      // the encoded size. Passing a multi-megabyte unparseable file on to the
      // renderer would be the one way to bypass the pixel limit.
      return PickImageResult.failure(
        PickError(
          reason: PickErrorReason.readFailed,
          detail: 'Selected file is ${_mib(sizeBytes)}, is not a decodable '
              'image, and is above the ${_mib(maxUndecodableFileSizeBytes)} '
              'undecodable-file limit.',
        ),
      );
    }

    return PickImageResult.success(
      PickedImage(
        path: local.path,
        sizeBytes: sizeBytes,
        width: reading.width,
        height: reading.height,
      ),
    );
  }

  /// Guards the import path before a model exists.
  ///
  /// Measured on real iNaturalist photos (2026-09-11, research-grade NZ CC0/CC BY):
  /// median ~2.8 MP, maximum ~4.2 MP with typical files well under 1 MiB, so these
  /// limits sit far above real input and only stop pathological files. They are
  /// import guards, not a quality policy: FR2's blur/brightness gate is still
  /// unimplemented.
  static const int maxFileSizeBytes = 32 * 1024 * 1024; // 32 MiB
  static const int maxPixelCount = 50 * 1000 * 1000; // 50 MP
  /// Applied only when the header cannot be parsed, so the pixel limit cannot be
  /// sidestepped by a file whose dimensions are unreadable.
  static const int maxUndecodableFileSizeBytes = 4 * 1024 * 1024; // 4 MiB

  static String _mib(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MiB';

  /// Reads the encoded image's header for its pixel size without decoding pixels.
  ///
  /// This does read the whole encoded file into memory first
  /// (`File.readAsBytes()`), then asks `ui.ImageDescriptor.encoded` to parse the
  /// header; the pixel buffer is never decoded. The earlier comment claiming it
  /// only read the header was inaccurate.
  ///
  /// Outcomes are explicit rather than encoded in nullability:
  /// - `tooLarge` — the header parsed but exceeds [maxPixelCount];
  /// - `undecodable` — the header could not be parsed, so the caller falls back to
  ///   the encoded-size guard before deciding whether to accept the file;
  /// - otherwise `width`/`height` carry the parsed pixel size.
  Future<_DimensionsReading> _readDimensions(File file) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      final Uint8List bytes = await file.readAsBytes();
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final int pixels = descriptor.width * descriptor.height;
      if (pixels > maxPixelCount) {
        return _DimensionsReading(tooLarge: true, pixels: pixels);
      }
      return _DimensionsReading(width: descriptor.width, height: descriptor.height);
    } catch (_) {
      return const _DimensionsReading(undecodable: true);
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}

/// Outcome of reading an image's header. See [FileSystemImageInput._readDimensions].
class _DimensionsReading {
  const _DimensionsReading({
    this.width,
    this.height,
    this.tooLarge = false,
    this.undecodable = false,
    this.pixels,
  });

  final int? width;
  final int? height;
  final bool tooLarge;
  final bool undecodable;
  final int? pixels;
}
