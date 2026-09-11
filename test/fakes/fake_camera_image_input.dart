import 'package:fieldsnap/models/pick_errors.dart';
import 'package:fieldsnap/models/picked_image.dart';
import 'package:fieldsnap/services/camera_image_input.dart';

/// Deterministic camera stub: gallery and camera are counted separately so tests can prove which
/// channel the UI actually used.
class FakeCameraImageInput implements CameraImageInput {
  FakeCameraImageInput({
    this.galleryResult,
    this.cameraResult,
    this.path = '/tmp/fieldsnap_fake.jpg',
    this.sizeBytes = 2048,
  });

  PickImageResult? galleryResult;
  PickImageResult? cameraResult;
  String path;
  int sizeBytes;

  int galleryCalls = 0;
  int cameraCalls = 0;

  PickImageResult _default() => PickImageResult.success(
        PickedImage(path: path, sizeBytes: sizeBytes, width: 64, height: 48),
      );

  @override
  Future<PickImageResult> pickFromGallery() async {
    galleryCalls += 1;
    return galleryResult ?? _default();
  }

  @override
  Future<PickImageResult> captureFromCamera() async {
    cameraCalls += 1;
    return cameraResult ?? _default();
  }

  static FakeCameraImageInput denyingPermission() => FakeCameraImageInput(
        cameraResult: const PickImageResult.failure(
          PickError(reason: PickErrorReason.permissionDenied, detail: 'denied in test'),
        ),
      );

  static FakeCameraImageInput cancellingCamera() => FakeCameraImageInput(
        cameraResult: const PickImageResult.failure(
          PickError(reason: PickErrorReason.cancelled),
        ),
      );
}
