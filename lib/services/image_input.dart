import '../models/pick_errors.dart';

/// Replaceable boundary for "give me one local image".
///
/// This is an Iteration 0 implementation refinement, NOT something Milestone 1
/// specified: M1 only said the user can shoot or import a single image (FR1).
/// Isolating the boundary means the ViewModel and the widget tests can run
/// against a deterministic fake without a device or the real Photo Picker.
///
/// Real implementation: `FileSystemImageInput`
/// (lib/services/file_system_image_input.dart).
abstract class ImageInput {
  /// Returns the selected image, a user cancellation, or a typed failure.
  ///
  /// Implementations must never throw for expected conditions; they return a
  /// [PickImageResult.failure] instead so the UI always has a recovery path.
  Future<PickImageResult> pickFromGallery();
}
