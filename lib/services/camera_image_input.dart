import '../models/pick_errors.dart';
import 'image_input.dart';

/// Source of the image the user is providing.
enum ImageSourceKind { gallery, camera }

/// Adds camera capture (FR1's second half) to the image-input boundary.
///
/// Kept as a separate interface from [ImageInput] so existing fakes and tests keep working, and
/// so the ViewModel can depend on "something that can do both" while tests inject only what they
/// exercise. Camera-specific failures (permission denied, no camera app, capture cancelled) are
/// reported through the same typed [PickError] channel as gallery picks.
abstract class CameraImageInput implements ImageInput {
  /// Opens the platform camera for one photo.
  ///
  /// Implementations must:
  ///  * return a [PickImageResult.failure] with reason `cancelled` when the user backs out;
  ///  * return `permissionDenied` (not a crash) when camera permission is refused or the camera
  ///    app is unavailable, so the UI can offer the gallery as a recovery path.
  Future<PickImageResult> captureFromCamera();
}
