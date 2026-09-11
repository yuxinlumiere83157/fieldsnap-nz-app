# Physical camera verification — Pixel 8, Iteration 3

Closes the "camera capture on hardware" item that was open through Iterations 0-2. Everything below
was executed on the connected device (Google Pixel 8, Android 17 / API 37, arm64); nothing is
inferred from the emulator or from stub tests.

| Item | Value |
| --- | --- |
| Device | Google Pixel 8 (`shiba`), USB (serial redacted; see `docs/data_privacy.md`) |
| OS | Android 17, API 37 |
| Build under test | `flutter build apk --debug`, entry point `lib/main.dart` |
| Camera app the platform resolved | `app.grapheneos.camera/.ui.activities.CaptureActivity` |
| Photo picker | `com.android.providers.media.module/.../photopicker.PhotoPickerActivity` |

## 1. Permission denial and recovery

Method: `pm revoke nz.fieldsnap.app android.permission.CAMERA`, then tap **Take photo**.

Observed (semantic tree, not pixel guessing):

```
GrantPermissionsActivity: "Allow FieldSnap NZ to take pictures and record video?"
                         [While using the app] [Only this time] [Don't allow]
→ tapped "Don't allow"
→ CAMERA granted=false, flags=[USER_SET|USER_SENSITIVE_WHEN_GRANTED|USER_SENSITIVE_WHEN_DENIED]
```

App response after the denial:

```
Step 1: The last image could not be used. See the message below.
Camera unavailable
  "FieldSnap could not use the camera: permission was refused or no camera app is available.
   You can still choose an existing photo from the gallery."
[Choose another image]  [Select from gallery]  [Take photo]
```

**Result: pass.** The refusal is a typed `permissionDenied`, it is explained, and the recovery route
(another image, or the gallery) is offered. Screenshot:
`docs/logs/iteration3_camera_01_permission_denied.png`.

## 2. Successful physical capture

Method: tap **Take photo**, grant "While using the app", press the shutter
(`KEYCODE_CAMERA`), then tap **Confirm** in the camera's review UI.

Observed: the GrapheneOS camera activity started (a real camera app, not a mock), the shutter fired,
the review UI offered Retake/Confirm, and confirming returned to the app with the file:

```
Preview: File: 99c9da5d-...jpg   Size: 1.8 MB
Step 2 - Image quality
  "Too little detail: sharpness 2.5 is below the 250 minimum. Hold still and refocus."
```

**Result: pass for capture.** The app received and previewed a genuine camera capture of 1.8 MB.
The quality gate then **rejected** it (sharpness 2.5 against the 250 threshold) — correct behaviour,
not a failure: the camera was pointed at a featureless surface under this rig. It is recorded as
evidence that FR2 acts on a real capture end to end. Screenshot:
`docs/logs/iteration3_camera_02_capture_success.png`.

## 3. Cancellation

* **Camera**: tap **Take photo** → real camera opens → system Back without pressing the shutter →
  returns to the app with the previous selection and quality verdict intact:
  `Image accepted. It passed the brightness and sharpness checks.` / `File: 474.jpg, 643.6 KB`
  Screenshot: `docs/logs/iteration3_camera_03_cancel_keeps_image.png`.
* **Gallery**: open the picker → Back → returns to the app unchanged (no error, no state damage).

**Result: pass** for both channels.

## 4. Gallery fallback after a camera refusal

Verified in `docs/logs/iteration3_camera_01_permission_denied.png` (the gallery affordance stays
available) and by subsequently selecting a gallery image successfully on the same device after the
refusal (`File: 474.jpg`, quality accepted, brightness 0.60 / sharpness 1773.3).

**Result: pass.**

## Notes and limits

* Zero `FATAL EXCEPTION` / `E/flutter` lines throughout.
* The push of the test photo this time used a dedicated folder (`/sdcard/Pictures/FieldSnap/`) so
  the picker could be driven to our own asset; the device folder and the app were cleaned up
  afterwards (`docs/data_privacy.md`).
* The camera path itself is exercised here through `image_picker`'s `ImageSource.camera` intent. A
  device with no camera app at all was not available to test that branch on hardware; it is covered
  by the stub test asserting `permissionDenied` for a missing plugin.
