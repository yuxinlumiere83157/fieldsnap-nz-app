import 'picked_image.dart';

/// Why an image could not be handed to the app as a usable preview.
enum PickErrorReason {
  /// The user closed the system picker without choosing anything.
  cancelled,

  /// The file exists but Flutter could not decode it (unsupported or corrupt).
  unsupportedImage,

  /// The file could not be read from disk (permissions, file moved, I/O error).
  readFailed,

  /// The platform channel itself failed for an unexpected reason.
  platformFailure,

  /// Camera permission was refused, or the device has no camera app available. The UI must offer
  /// the gallery as a recovery path instead of dead-ending the task (M1 runtime characteristics).
  permissionDenied,
}

/// A pick failure with a short machine-stable reason plus developer detail.
///
/// The UI maps [reason] to user-facing copy; [detail] is for diagnostics only.
class PickError {
  const PickError({required this.reason, this.detail});

  final PickErrorReason reason;
  final String? detail;

  bool get isUserCancellation => reason == PickErrorReason.cancelled;

  @override
  String toString() => 'PickError(reason: $reason, detail: $detail)';
}

/// Result of asking the user for one image. Exactly one of [image] / [error]
/// is non-null.
class PickImageResult {
  const PickImageResult.success(this.image) : error = null;

  const PickImageResult.failure(this.error) : image = null;

  final PickedImage? image;
  final PickError? error;

  bool get isSuccess => image != null;

  @override
  String toString() => isSuccess
      ? 'PickImageResult.success($image)'
      : 'PickImageResult.failure($error)';
}
