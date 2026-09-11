import 'dart:io';

import 'package:fieldsnap/models/pick_errors.dart';
import 'package:fieldsnap/models/picked_image.dart';
import 'package:fieldsnap/services/image_input.dart';

/// Deterministic test double for [ImageInput].
///
/// Test-only code: it proves ViewModel behaviour (initial state, success,
/// cancellation, failure) and does NOT prove that the real Android Photo Picker
/// works. Real-device verification stays a separate, explicitly recorded step.
class FakeImageInput implements ImageInput {
  FakeImageInput({
    this.result,
    this.error,
    this.delay = Duration.zero,
    this.path,
    this.sizeBytes = 2048,
    this.width = 64,
    this.height = 48,
  });

  /// Result returned by the next call. When null a synthetic image is built.
  PickImageResult? result;

  /// When set, the next call throws this instead of returning, so tests can
  /// check behaviour on unexpected failures.
  Object? error;

  /// Optional latency so tests can observe the `picking` state.
  Duration delay;

  /// Real on-disk file the fake points at, when one is provided by the test.
  String? path;
  int sizeBytes;
  int? width;
  int? height;

  int callCount = 0;

  @override
  Future<PickImageResult> pickFromGallery() async {
    callCount += 1;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    final Object? thrown = error;
    if (thrown != null) {
      throw thrown;
    }
    final PickImageResult? fixed = result;
    if (fixed != null) {
      return fixed;
    }
    return PickImageResult.success(
      PickedImage(
        path: path ?? '${Directory.systemTemp.path}/fieldsnap_fake.jpg',
        sizeBytes: sizeBytes,
        width: width,
        height: height,
      ),
    );
  }

  /// Convenience: a fake that always reports a user cancellation.
  static FakeImageInput cancelling() => FakeImageInput(
        result: const PickImageResult.failure(
          PickError(reason: PickErrorReason.cancelled),
        ),
      );

  /// Convenience: a fake that always reports an unreadable image.
  static FakeImageInput unreadable({String? detail}) => FakeImageInput(
        result: PickImageResult.failure(
          PickError(reason: PickErrorReason.readFailed, detail: detail),
        ),
      );
}
