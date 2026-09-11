# Physical-device run — Google Pixel 8 (Iteration 2)

This closes the "physical device" gap that was open through Iterations 0-2. Everything below was
executed on the device; nothing is extrapolated from the emulator.

## Device and build details

| Item | Value |
| --- | --- |
| Device | Google **Pixel 8** (`shiba`), USB (device serial redacted; recorded in the private notes, not in the repository) |
| OS | **Android 17**, build `CP2A.260805.005`, security patch 2026-08-05 |
| API level | **37** (app `targetSdk` 36, `minSdk` 26) |
| ABI | arm64-v8a |
| RAM | 7.5 GB total (`MemTotal: 7499984 kB`) |
| Free storage | 82 GB on `/data` |
| App under test | `nz.fieldsnap.app` debug (functional), **profile** (latency), **release** (size) |
| Model | `assets/models/fieldsnap_float.tflite` (FP32, 3.60 MiB, data version 2) |

## 1. Device conformance test (functional)

```
flutter test integration_test/on_device_inference_test.dart -d <device-id>
→ 4 tests passed: FP32 vector matches the Python reference within 1e-3 on hardware;
  the experimental INT8 artefact loads and normalises; two latency-protocol groups ran.
```

## 2. Latency — Milestone 1 §7 protocol

Measured in a **profile** build via `lib/benchmark_main.dart` (measurement-only entry point, not
shipped), warm-up excluded, **30 timed runs**, preprocess + inference:

| Measurement | Median | P95 | Min | Max |
| --- | --- | --- | --- | --- |
| Inference only (fixed 224x224 tensor) | **101.65 ms** | **155.27 ms** | 97.52 ms | 168.74 ms |
| Full CPU path (decode + resize + rescale + inference, 2.8 MP JPEG) | **314.42 ms** | **351.87 ms** | — | — |

**Against NFR2** (median inference ≤ 300 ms, P95 ≤ 500 ms on the designated device): the
inference-only measurement **passes with substantial margin** (101.65 / 155.27 ms). The full CPU
path is reported alongside because it is what the user actually waits for; its median (314 ms)
exceeds the inference target by 14 ms, and the extra time is image decoding and resampling, not
model execution.

Honest caveats:

* This is one device and one session; the protocol says "the designated Android test device", and
  M1's plan named Android 15 whereas this device runs Android 17. That difference is recorded
  rather than glossed over.
* The debug build measured earlier was ~119 ms median; profile is the number that counts, and both
  are from the same APK entry point.
* The Flutter UI's own displayed latency (430 ms in the release screenshot) is a **release**
  single-shot number including isolate start-up and asset load, so it is higher and noisier than
  the warmed benchmark.

## 3. Release package size — NFR4

| Artefact | Size | Target | Result |
| --- | --- | --- | --- |
| `app-release.apk` (fat, all ABIs) | **76.3 MB** (76,306,805 B) | ≤ 80 MB | **pass** |
| `app-release.aab` | 72.0 MB (72,026,902 B) | — | recorded |

The APK is a fat build containing `libflutter.so` and `libapp.so` for arm64-v8a, armeabi-v7a and
x86_64 plus `libtensorflowlite_jni.so`; a per-ABI split (`--split-per-abi`) would be much smaller
and would make the 80 MB target comfortable. The bundled model contributes 3.60 MiB.

## 4. Core workflow on the device

Executed end to end (screenshots in `docs/logs/iteration2_device_*.png`):

1. launch the **release** APK → capture screen renders, identification disabled;
2. **Select from gallery** → the platform picker opened (`PhotoPickerActivity`); the app's own
   sample image was chosen;
3. quality gate ran on device: `brightness 0.28, sharpness 378.7` → accepted;
4. **Identify species** → FP32 inference ran on device: result **Kōwhai 57.5%**, top-3 listed
   (Silver fern 8.7%, Common blackbird 5.2%), learning card rendered;
5. **history** persisted a row: `Kōwhai | 58% | threshold 45% (unvalidated) |
   fieldsnap_float.tflite (FP32, data v2) | brightness 0.28, sharpness 378.7`.

Zero `FATAL EXCEPTION` / `E/flutter` lines during the flow.

**Modelling note, reported rather than hidden**: the chosen photo is a kererū (a validation image
of a pigeon in blossom) and the model answered **Kōwhai at 57.5%** — a confident misclassification
across life forms. That is consistent with the failure mode hypothesised in
`docs/model_error_analysis.md` (background/colour shortcuts and similar "flowers on a branch"
scenes). It is one anecdotal sample and is not used to change anything.

## 5. A real defect this run surfaced

Building the **profile** APK failed with:

```
Execution failed for task ':app:processProfileMainManifest'.
> Error parsing android/app/src/profile/AndroidManifest.xml
```

The file contained `<!-- Used by `flutter run --profile` ... -->`, and a comment may not contain
`--`. Debug builds never parse that manifest, which is why the file had been broken since Iteration
0 without anyone noticing; the first `--profile` build exposed it. Fixed, and all three manifests
are now checked to parse as XML.

## 6. Privacy handling during this run

The device's own photo library was shown by the platform picker. An early automated tap landed on
the user's private screenshot instead of the pushed sample. That screenshot was:

* **never written into the repository** (the one captured frame was deleted immediately);
* **never classified** — no inference ran on it;
* **never persisted** — the history database contains exactly one row, the Kōwhai record above.

The app was uninstalled afterwards and the pushed sample photo removed, so no app-side data remains
on the device. Only the two screenshots referenced in §4 are kept.

## 7. What remains unverified

* **Camera capture on hardware**: the physical camera was not used; the camera path is implemented
  and covered by stub-based tests, and the emulator's virtual camera was not used to take a photo
  either. This is still an explicitly open item.
* **FR2/FR4 thresholds** remain development-sample defaults, not validated.
* **Self-hosted usability evaluation** (10 novice users, SUS) has not started, by instruction.
* Memory is recorded only as total device RAM; no peak-process-memory profiling was done.
