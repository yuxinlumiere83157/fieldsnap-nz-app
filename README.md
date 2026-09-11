# FieldSnap NZ

Offline, Android-first species recognition prototype for beginner nature learners in
Auckland. This repository is at **Iteration 0**: project skeleton, one-image import
with preview, tests, and honest documentation. **No model is bundled yet and the app
performs no species recognition.**

Course context: the course Milestone 2 development artefacts (Flutter UI + on-device
LiteRT/TFLite inference + local history). Milestone 1 is the design baseline; this
repository records what has actually been built so far.

---

## Current status (be precise: planned is not done)

| Area | State | Evidence |
| --- | --- | --- |
| Environment check | done on this machine (M5 / 16 GB / macOS 27) | `docs/iteration0_report.md`, `docs/progress.md` |
| Flutter Android project skeleton | created | `pubspec.yaml`, `lib/`, `android/` |
| Select one local image | implemented (platform Photo Picker via `image_picker`) | `lib/services/file_system_image_input.dart` |
| Preview + replace + clear | implemented | `lib/views/capture_screen.dart` |
| Cancel without losing state | implemented + tested | `test/classifier_view_model_test.dart` |
| Read/unsupported/plugin failure handling | implemented + tested | `test/capture_screen_test.dart` |
| Static analysis | **verified clean** — `flutter analyze`: No issues found | `docs/iteration0_report.md` §3 |
| Automated tests | **verified** — `flutter test`: 30 tests passed | `test/` |
| Android debug build | **verified** — `flutter build apk --debug` succeeded | `docs/logs/iteration0_build_debug_apk.log` |
| Android emulator run of the whole Iteration 0 flow | **verified on emulator** (API 36 arm64, Pixel 6 profile): real Photo Picker, preview, replace, cancel, clear, zero crashes | `docs/emulator_verification.md`, `docs/logs/emulator_*.png` |
| Camera capture (FR1, second half) | **not implemented** | — |
| Image quality gate (FR2) | **not implemented** | — |
| Local classification / top-3 / confidence (FR3) | **not implemented**; the app reports `modelUnavailable` | `lib/services/unavailable_species_classifier.dart` |
| Uncertain threshold (FR4) | **not implemented** | — |
| Learning cards (FR5) | **not implemented** | — |
| History persistence (FR6) | **not implemented** | — |
| Physical-device verification | **verified on a Google Pixel 8 (Android 17, API 37)** — full workflow, latency protocol and release size measured on hardware | `docs/physical_device_run.md` |
| Camera capture on hardware | **not run** — the camera path is implemented and stub-tested; no photo was taken with a physical camera | `docs/iteration_2_report.md` §3 |
| Candidate species list (~20 Auckland classes) | **candidate only** — 10 birds + 10 plants with sources and licence status | `docs/species_candidates.md` |
| Data set (1A) | **prepared** — 1,199 CC0/CC BY images, 614 observations, observation-grouped split frozen, leakage/ licence/ integrity checks pass, test split sealed | `data/README.md`, `docs/model_pipeline.md` |
| Model path (1B) | **pipeline verified** — MobileNetV3-Small trained, float + INT8 `.tflite` exported, runs on the Android emulator; validation top-1 0.411 (float) / 0.252 (INT8), so M1 accuracy targets are **not** met and are not claimed | `docs/model_pipeline.md`, `artifacts/model_report.json` |
| Correctness fixes (1C) | **done** — fine-tuning now actually runs, reporting fields corrected, one preprocessing spec, three separate conformance checks, enforced data freeze, shareable provenance, shipped INT8 model committed | `docs/checkpoint_1c_report.md` |
| Verification gaps (1D) | **done** — channel/orientation tests that can fail, EXIF parsed correctly (the `image` package does not read EXIF and rotates orientation 6 the wrong way), FP32-only strict Keras check with run metadata, fresh-clone checks verified | `docs/checkpoint_1d_report.md` |
| Controlled data expansion (1D) | **done, one experiment** — training set 849 → 2,995 images with validation/test untouched; validation top-1 0.448 → **0.503**, top-3 0.675 → **0.749**, macro-F1 0.424 → **0.499** | `docs/checkpoint_1d_report.md`, `artifacts/comparison_*.json` |
| Model choice | **FP32 is the baseline; INT8 is experimental** — the INT8 gap is ~19 points of top-1 on the expanded model, so no deployment decision is made | `docs/checkpoint_1d_report.md` |

Anything not listed as implemented above is still planned work.

**Scope of the "no invented results" claim**: this build performs no species inference and
generates no predictions, so no species name, confidence value, latency, accuracy figure or
usability number is produced or displayed anywhere in the app. The code, tests and
documentation were produced by the author with **AI coding assistance** (used as a
programming reference and for optimisation, with all output reviewed and verified by the
author); that is recorded in `docs/progress.md` and is a separate matter from inventing
results.

---

## Environment (recorded, not assumed)

Detected on 2026-09-11:

| Tool | Actual |
| --- | --- |
| Machine / OS | Apple M5 (arm64), 16 GB RAM, macOS 27.0 |
| Flutter | 3.47.3 stable (Dart 3.13.3) |
| Android SDK | `~/Library/Android/sdk` — build-tools 36.0.0, platforms android-36, platform-tools (adb) |
| JDK | Temurin 21.0.12 (`JAVA_HOME` pinned to JDK 21 for Gradle) |
| Git | 2.54.0 (Apple Git-157) |

Notes:

- The M1 design snapshot described an Intel i5 / 8 GB / macOS 15.6.1 Mac. The real
  machine differs; this is recorded in `docs/iteration0_report.md` instead of being
  silently adopted or silently ignored.
- Flutter 3.47.3 was chosen because it is the current **stable** release for this
  architecture; Android defaults for this channel are compileSdk/targetSdk 36,
  AGP 9.1.0, Gradle 9.3.1, Kotlin 2.4.0.
- `minSdk` is pinned to **26**, not Flutter's default 24. M1 §3 records that
  `tflite_flutter` makes API 26 the practical minimum for this MVP and M1 §6 commits to an
  ARM64 device on API 26 or later, so the build now matches the declared baseline
  (verified in the built APK: `minSdkVersion:'26'`, `targetSdkVersion:'36'`).
- Why JDK 21: current Flutter/AGP toolchains support Java 17-21; JDK 25 is not the
  tested baseline. `flutter build apk` inherits `JAVA_HOME`, so export it before
  building (see below).

---

## Install / run / test

```sh
# 1. Flutter SDK (stable 3.47.3, arm64)
#    already installed at ~/development/flutter in this environment
export PATH="$HOME/development/flutter/bin:$PATH"

# 2. Android toolchain: point Flutter at the existing SDK
export ANDROID_HOME="$HOME/Library/Android/sdk"

# 3. Build tools need a supported JDK
export JAVA_HOME="$(/usr/libexec/java_home -v 21)"

# 4. Project dependencies
flutter pub get

# 5. Static analysis + tests
flutter analyze
flutter test

# 6. Debug APK (only meaningful when the Android toolchain is healthy)
flutter build apk --debug
```

Run on a connected Android device (developer options + USB debugging enabled):

```sh
flutter devices
flutter run -d <device-id>
```

Or on the Android emulator used for Iteration 0 verification:

```sh
SDK="$HOME/Library/Android/sdk"
export ANDROID_HOME="$SDK" ANDROID_SDK_ROOT="$SDK" JAVA_HOME="$(/usr/libexec/java_home -v 21)"
"$SDK/emulator/emulator" -avd fieldsnap_api36 -no-snapshot-load -no-boot-anim -gpu auto -no-audio &
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n nz.fieldsnap.app/.MainActivity
```

Full emulator evidence (screenshots, logcat, hashes, steps): `docs/emulator_verification.md`.

Results of these checks on the development machine (2026-09-11). Rows marked "historical"
describe the state at that moment and are kept for the audit trail; current state is noted
in the status table above:

| Command | Result |
| --- | --- |
| `flutter analyze` | `No issues found!` (re-run after every change; the current suite is 34 tests) |
| `flutter test` | `30 tests passed` at this point; `34 tests passed` after the import guards and extra adapter cases were added |
| `flutter build apk --debug` | succeeded in 226.5 s → `build/app/outputs/flutter-apk/app-debug.apk` (144 MB; a debug APK is not the NFR4 package metric) |
| `flutter doctor -v` (historical) | Flutter valid; Android SDK found (SDK 36.0.0) but `cmdline-tools` missing and doctor could not confirm licence status; CocoaPods missing (irrelevant, Android-only) |
| Physical-device run (historical) | not performed — no Android phone attached. An Android 16 emulator run was completed later; see `docs/emulator_verification.md` |

There is no web, iOS, macOS, Linux or Windows target in this repository; Iteration 0
is Android-only by design. `flutter create --platforms=<other>` would be needed to
add one.

---

## Architecture (MVVM: View → ViewModel → Services/Repositories)

```
lib/
  main.dart                                  # composition root, constructor DI
  models/                                    # plain value types, no Flutter widgets
    picked_image.dart                        # PickedImage (path, bytes, pixels)
    pick_errors.dart                         # PickError / PickErrorReason / result
  services/
    image_input.dart                         # ImageInput boundary (replaceable)
    file_system_image_input.dart             # real adapter: platform Photo Picker
    species_classifier.dart                  # SpeciesClassifier boundary
    unavailable_species_classifier.dart      # honest "no model yet" implementation
    classification_result.dart               # candidates / typed failure
  viewmodels/
    classifier_view_model.dart               # ClassifierState + commands (ChangeNotifier)
  views/
    capture_screen.dart                      # CaptureScreen: renders state only
```

Rules that hold in this codebase:

- Widgets never run inference, never read files directly for business decisions and
  never touch SQL; they render `ClassifierState` and call ViewModel commands.
- `ImageInput` and `SpeciesClassifier` are the only seams the ViewModel knows, which
  is what makes the unit and widget tests deterministic.
- Only the (future) inference implementation may touch the LiteRT runtime.

## Known limitations in this iteration

- No model, no labels, no preprocessing: recognition is disabled and reports why.
- No camera capture, quality gate, learning cards or history database yet.
- No release signing configuration; the release build type reuses the debug signing
  config so that `flutter build apk` works at all.
- Launcher icon, app branding and theming are stock Flutter defaults. The five
  `mipmap-*/ic_launcher.png` files are the placeholder icons generated by
  `flutter create`; they are in-repo only so the Android build has an icon resource, and
  they must be replaced before any public release.
- Tests use fakes; they do not replace on-device verification of the real picker.
- The build warns that applying the Kotlin Gradle Plugin will break in a future Flutter
  version. Flutter 3.47.3's own Android template still generates
  `android.builtInKotlin=false` with that plugin, so this project matches the canonical
  template; migrating to built-in Kotlin is a tracked follow-up, not a silent change.
- `cmdline-tools` **is now installed** (latest, 19.0) as part of the emulator setup, so the
  earlier `flutter doctor` warning about it is resolved. The historical check result is kept
  above for the audit trail.
- The Android emulator (`fieldsnap_api36`, API 36 arm64) is the only device this has run on.
  Physical-device performance evidence is still outstanding, and emulator numbers must never
  be reported as device numbers.
- `android/gradle.properties` sets a 4 GB Gradle heap instead of Flutter's 8 GB template
  default, deliberately: this machine also runs other work while builds happen. Raise it
  if a future release build with the model fails on memory.

## Baseline reconciliation (after reading the real M1 report)

The Milestone 1 report was read from a local copy (`reference/`, git-ignored, not published). Reading it changed three
things and confirmed the rest:

| Finding from M1 | Action taken |
| --- | --- |
| §3/§6: Flutter supports API 24+, but `tflite_flutter` makes API 26 the practical MVP minimum; committed device is ARM64 on API 26+ | `minSdk` pinned to 26 and verified inside the built APK (was Flutter's default 24) |
| §4 Table 4: component names are `CaptureView`, `ClassifierViewModel`, `ImageQualityService`, `ImagePreprocessor`, `InferenceService`, `Prediction`, `SpeciesRepository`, `HistoryRepository`, `LocalStore` | `docs/traceability.md` now uses M1's own component names; `CaptureScreen` corresponds to `CaptureView`, and the added `ImageInput` boundary is recorded as an implementation refinement |
| §5 Figure 4: navigation is a shallow Home/Capture → Classifying → Result flow, not a numbered wizard | removed the "Step 1/Step 2" headings from the capture screen |
| §4/§7: no view may touch the interpreter or SQLite; §7 requires 100% FR/NFR mapping and substitutable dependencies in tests | holds: no widget imports the classifier implementation or any SQL; ViewModel/UI tests use injected fakes |
| §7: measurement protocol (≥ 30 warm single-image runs on a profile/release build on a physical device; threshold chosen on validation data then frozen) | recorded verbatim in `docs/traceability.md` so it is fixed before any measurement |
| §1.2/§2: target classes are ~20 commonly encountered Auckland species, about ten plants and ten birds, drawn from openly licensed iNaturalist observation data; `tflite_flutter` 0.12.1 is the cited binding | next iteration's starting point; nothing downloaded yet |

## Documentation map

- `ENGINEERING_RULES.md` — scope, architecture boundaries and required checks for contributors.
- `docs/traceability.md` — FR/NFR → component → implementation status → verification status.
- `docs/progress.md` — dated record of what was actually done, including blockers.
- `docs/iteration0_report.md` — one-to-two-page handover summary for this iteration.
- `docs/plan.md` — the execution plan that was proposed for this iteration.
- `docs/emulator_verification.md` — emulator run: environment, steps, results, screenshots, hashes.
- `docs/species_candidates.md` — the ~20 candidate Auckland classes with sources, licence status and API fetch commands.
- `tools/run_checks.py` — runs every suite and reports passed / failed / errors / **skipped** separately.
- `docs/model_pipeline.md` — checkpoints 1A/1B: data policy, split rules, training/export, measured results, known limitations.
- `docs/checkpoint_1c_report.md` — what the review found, what was wrong, what changed, and the corrected numbers.
- `docs/checkpoint_1d_report.md` — verification-gap closure, the controlled data expansion experiment, and the corrected claims about earlier root causes.
- `docs/preprocessing_spec.md` — the single preprocessing specification the three implementations follow.
- `data/README.md` — how the data set is fetched, split and kept out of version control.
- `third_party/tflite_flutter/README-FIELDSNAP.md` — the one local dependency patch and why it exists.

`reference/` (course materials, the Milestone 1 report, other people's examples) is git-ignored on
purpose and must not be published. It holds this iteration's task brief and the Milestone 1 report,
both local-only copies that were verified after copying.
