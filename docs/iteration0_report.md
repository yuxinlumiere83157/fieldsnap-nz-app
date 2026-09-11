# Iteration 0 report — FieldSnap NZ

Date: 2026-09-11. Author: Robin Huang (with AI coding assistance, see
`docs/progress.md`). This report is a handover summary for one iteration; it is not the
Milestone 2 final report.

## 1. Actual environment (detected, not assumed)

| Item | Actual value |
| --- | --- |
| Machine / OS | Apple M5 (arm64), 10 cores, 16 GB RAM, macOS 27.0 (build 26A5425a) |
| Disk free | ~42 GB |
| Flutter / Dart | 3.47.3 stable / Dart 3.13.3 (installed to `~/development/flutter`) |
| Android SDK | `~/Library/Android/sdk`: build-tools 36.0.0, platforms android-36 and android-37.0, platform-tools/adb, accepted SDK licence |
| Android gaps | no `cmdline-tools` at kickoff (**installed later the same day**, latest 19.0, during emulator setup); NDK/CMake were absent at kickoff and were auto-installed by the first Gradle build (NDK 28.2.13676358, CMake 3.22.1) |
| JDK | Temurin 21.0.12 used for builds (`JAVA_HOME` pinned); JDK 25.0.4 and Corretto 11 also installed |
| Git | 2.54.0 (Apple Git-157), local repo on `main`, no remote configured |
| Android device | `adb devices` → empty; **no physical device attached**, no emulator created |
| M1 baseline | `reference/` (git-ignored) (the Milestone 1 report, 21 Aug 2026, 23 pp., kept locally and not committed) — received after the first pass and fully read |

Version choices and reasons: Flutter **3.47.3** was taken from the official stable
release index for arm64 and its archive hash verified, because the M1 baseline requires
a stable, Android-capable Flutter/Dart toolchain. Its Android defaults are
compileSdk/targetSdk 36, AGP 9.1.0, Gradle 9.3.1, Kotlin 2.4.0, JDK 17+. No Android Studio
or iOS/macOS desktop toolchain was installed, because the iteration is Android-only.

Design-vs-reality differences worth flagging:

- The M1 snapshot described an Intel i5 / 8 GB / macOS 15.6.1 machine; the real machine
  is an M5 / 16 GB / macOS 27.0 (user-confirmed).
- M1 pp. 9–10 state that Flutter supports API 24+, but that `tflite_flutter` makes API 26
  the practical minimum, and p. 16 commits to an ARM64 device on API 26+. `minSdk` is
  therefore pinned to **26** and verified inside the built APK, rather than left at
  Flutter's default 24.
- The M1 report arrived after the first pass; the requirements, component names,
  navigation shape and measurement protocol were then read from the real document, and the
  corrections are listed in `docs/progress.md` and `README.md`.

## 2. What was actually implemented

- Flutter Android application skeleton with MVVM structure (`View → ViewModel →
  Services`) and constructor-based dependency injection in `lib/main.dart`.
- `CaptureScreen`: status card, image preview, select/replace/clear actions, typed error
  panel with a recovery action, and a recognition section that states plainly that
  recognition is unavailable.
- `ClassifierViewModel` with an explicit `ClassifierState` (idle/picking/ready, image,
  error, model availability) and commands `pickImage()` / `clearImage()`.
- Replaceable `ImageInput` boundary plus the real `FileSystemImageInput` adapter built on
  the official `image_picker` plugin (platform Photo Picker, single existing image).
  This boundary is an Iteration-0 implementation refinement, not an M1-specified class.
- `SpeciesClassifier` boundary and `UnavailableSpeciesClassifier`, which returns a typed
  `modelUnavailable` failure. No species, confidence, latency or accuracy is displayed
  anywhere in the app.
- Typed pick outcomes: success, user cancellation, unsupported image, read failure,
  platform/plugin failure.
- Unit tests (ViewModel state machine, adapter failure mapping, classifier boundary) and
  widget tests (initial state, success, replace, cancel, read failure, clear, missing
  model) using test-only fakes.

Still pending by design: camera capture, quality gate (FR2), real inference (FR3),
uncertainty threshold (FR4), learning cards (FR5), history persistence (FR6).

Component naming now follows M1's own requirements-to-component table (p. 12):
`CaptureScreen` is the `CaptureView` of that design, `ClassifierViewModel` matches by name,
and the added `ImageInput` boundary is an Iteration-0 refinement recorded in
`docs/progress.md`. The future `ImageQualityService`, `ImagePreprocessor`,
`InferenceService`, `Prediction`, `SpeciesRepository`, `HistoryRepository` and `LocalStore`
are named but not yet built.

## 3. Commands run and their real results

| Command | Result |
| --- | --- |
| `sw_vers`, `sysctl -n machdep.cpu.brand_string`, `df -h` | macOS 27.0; Apple M5; ~42 GB free |
| `git --version`, `git config --global user.name` | 2.54.0; existing identity present, left unchanged |
| `java -version`, `/usr/libexec/java_home -V` | Temurin 21.0.12 active; 25.0.4 and 11 also present |
| `adb devices -l` | empty device list |
| Flutter archive download + `shasum -a 256 -c -` | hash `66144a7c…f6583` matched the published value |
| `flutter --version` | 3.47.3 stable, Dart 3.13.3 |
| `flutter doctor -v` | see the verification block below |
| `flutter pub get` | see the verification block below |
| `flutter analyze` | see the verification block below |
| `flutter test` | see the verification block below |
| `flutter build apk --debug` | see the verification block below |
| `sha256sum reference/…Milestone1.pdf` | matches the supplied M1 file (`cee41e52…b1a9`) |
| `aapt2 dump badging app-debug.apk` | `minSdkVersion:'26'`, `targetSdkVersion:'36'`, package `nz.fieldsnap.app` |
| Device run | **not run** — no Android device or emulator available (`flutter doctor` listed only an iOS phone, macOS desktop and Chrome) |

### Actual results of the executed checks

All commands were run in `<project-root>` with
`PATH=$HOME/development/flutter/bin:$PATH`,
`ANDROID_HOME=$HOME/Library/Android/sdk` and `JAVA_HOME=$(/usr/libexec/java_home -v 21)`.

| Command | Exact result |
| --- | --- |
| `flutter --version` | Flutter 3.47.3 stable, Dart 3.13.3, DevTools 2.60.0, engine 06a2e2a110 |
| `flutter doctor -v` (historical — run before `cmdline-tools` was installed) | Flutter ✓; Android toolchain ⚠ (SDK 36.0.0 found, `cmdline-tools` missing at that time, license status unknown to doctor); Xcode ⚠ (CocoaPods missing, irrelevant here); Chrome ✓; network ✓ |
| `flutter pub get` | Resolved 47 dependencies; `image_picker 1.2.3`, `flutter_lints 6.0.0`; `pubspec.lock` committed |
| `flutter analyze` | `No issues found! (ran in 2.9s)` |
| `flutter test` | `30 tests passed` covering 16 ViewModel tests, 6 adapter tests, 8 widget tests |
| `flutter build apk --debug` | `✓ Built build/app/outputs/flutter-apk/app-debug.apk`; first run 226.5 s, re-run after the `minSdk` 26 change 9.0 s; debug artefact 144 MB (a debug APK is not the NFR4 package metric) |
| `aapt2 dump badging` (build-tools 36.0.0) | confirms `minSdkVersion:'26'` and `targetSdkVersion:'36'` inside the packaged APK |
| Gradle / Android toolchain side effects | Gradle 9.3.1 wrapper downloaded; AGP auto-installed NDK 28.2.13676358 and CMake 3.22.1 into the SDK (Flutter's `ndkVersion` default, accepted license) |
| Device run | not run — no Android device attached |

Known warning recorded deliberately: the build prints
"applies the Kotlin Gradle Plugin, which will cause build failures in future versions of
Flutter". Flutter 3.47.3's own Android template still ships
`android.builtInKotlin=false` with the Kotlin plugin, so this project matches the
canonical template; migration to built-in Kotlin
(https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers)
is a planned, tracked follow-up rather than a silent change.

Raw build log: `docs/logs/iteration0_build_debug_apk.log`. The analyze/test output is
reproduced above rather than pasted in full to keep this report readable.

## 4. Model and data status

No model, no labels file, no dataset and no training code exist in this repository, and
none were downloaded. The classification boundary returns `modelUnavailable`, and the UI
states that no result is being invented. Model/data feasibility is the first item of the
next iteration.

From M1 (pp. 5–6, 9–10): the committed scope is around twenty commonly encountered Auckland
species — roughly ten plants and ten birds — with training images drawn from openly licensed,
research-grade observation data such as iNaturalist exports, a MobileNetV3-Small (or
comparable lightweight MobileNet) baseline fine-tuned to that class set and converted to
int8 where accuracy remains acceptable, run through LiteRT via the TensorFlow-published
`tflite_flutter` binding. `tflite_flutter` is deliberately **not** added as a dependency
yet: it belongs with the feasibility spike, and adding it now would only introduce an
unused native dependency into Iteration 0.

## 5. Device verification

**Emulator: verified.** An Android 16 (API 36, arm64, Pixel 6 profile) AVD
`fieldsnap_api36` was created and the whole Iteration 0 flow was exercised on it: install,
launch, the real system Photo Picker
(`com.google.android.photopicker/.MainActivity`), selection returning
`/storage/emulated/0/Pictures/FieldSnap/green_1280x960.jpg` with the preview showing
`18.jpg / 32.8 KB / 1280 x 960 px`, replace, cancel (previous image kept — the two
screenshots are byte-identical), clear, and zero crash or Flutter-error lines in logcat.
Evidence: `docs/emulator_verification.md` plus `docs/logs/emulator_*.png` and
`docs/logs/emulator_verification_20260911.log`. This also cleared the earlier
`cmdline-tools` gap reported by `flutter doctor`.

**Physical device: still not verified.** No Android phone was attached (`adb devices`
empty; `flutter doctor` listed an iOS phone, macOS desktop and Chrome only). Emulator
results are not device results, and no timing or memory observation was taken. The
read-failure error panel was likewise not demonstrated on the emulator (it is covered by
tests only).

Exact manual steps to close the physical-device item (not yet performed):

1. On the phone: enable Developer options and USB debugging, then connect it by USB and
   accept the authorisation prompt.
2. `export PATH="$HOME/development/flutter/bin:$PATH"`, `export
   ANDROID_HOME="$HOME/Library/Android/sdk"`, `export JAVA_HOME="$(/usr/libexec/java_home -v 21)"`.
3. `flutter devices` (expect the phone), then `flutter run -d <device-id>`.
4. On the device, check in order: (a) tap **Select image**, pick a photo, confirm the
   preview plus file name/size/pixels; (b) tap **Replace image** and pick a different
   photo; (c) open the picker and press back — the first photo must stay and no error may
   appear; (d) delete/move the file outside the app and try again to see the read-failure
   panel; (e) confirm the **Identify species** button stays disabled and no species or
   confidence is ever shown.
5. Record the device model, Android version and observed result in `docs/progress.md`.
   Do **not** report inference timing from this build: the debug APK contains no model.

## 6. Key files changed

- `pubspec.yaml`, `analysis_options.yaml`, `.gitignore`, `.metadata`
- `lib/main.dart`, `lib/models/*.dart`, `lib/services/*.dart`, `lib/viewmodels/*.dart`,
  `lib/views/capture_screen.dart`
- `test/classifier_view_model_test.dart`, `test/capture_screen_test.dart`,
  `test/file_system_image_input_test.dart`, `test/fakes/*.dart`
- `android/` project files (manifest, Kotlin host activity, Gradle Kotlin DSL, resources)
- `README.md`, `ENGINEERING_RULES.md`, `docs/plan.md`, `docs/traceability.md`, `docs/progress.md`,
  `docs/iteration0_report.md`

## 7. Differences from Milestone 1 and open decisions

- Added `ImageInput` and `SpeciesClassifier` boundaries. M1 names `CaptureView`,
  `ClassifierViewModel`, `ImageQualityService`, `ImagePreprocessor`, `InferenceService`,
  `Prediction`, `SpeciesRepository`, `HistoryRepository` and `LocalStore` (Table 4, p. 12);
  the two added abstractions are an implementation refinement of that design, recorded in
  `docs/progress.md` rather than presented as M1 content.
- `minSdk` **26** (M1 pp. 9–10, 16) — enforced in the build and verified in the APK. This
  was briefly left at Flutter's default 24 before the M1 report arrived; the deviation is
  closed.
- `CaptureScreen` is a single capture surface for Iteration 0. M1's navigation (Figure 4)
  expects Home/Capture → Classifying → Result; the extra screens arrive with real
  inference, and the "Step 1 / Step 2" wording was removed because M1 does not describe a
  numbered wizard.
- No quality gate, learning cards, history or model yet, so M1's flow is only partially
  present.
- The M1 process model (two-week reviews, WIP ≤ 2 implementation items, one runnable
  physical-device build per development week, CRISP-DM loop inside the ML spike) has not
  been exercised yet; nothing was back-filled, and the cadence has to start from the next
  working session.

## 8. Blockers and next steps for the user

1. ~~Place the real Milestone 1 report at `reference/`~~ — done: the PDF is in
   `reference/` (git-ignored) and the traceability table has
   been re-checked against it.
2. Connect an Android device (or explicitly approve creating one AVD) to close the
   on-device verification item; if an emulator is used, its numbers must not be presented
   as real-device performance.
3. Approve creating the GitHub repository and the first push (nothing was published from
   this iteration), and confirm the board/review cadence to resume the Scrum/Kanban flow.
4. `minSdk` is now 26 to match M1; no decision is outstanding on it.
5. Next iteration: model/data feasibility — the ~20-class Auckland label list (about ten
   plants and ten birds per M1 §1.2), image sources and licences (openly licensed
   iNaturalist exports), train/validation/test split, and a small end-to-end
   train → int8 convert → on-device smoke test through `tflite_flutter` — before deepening
   UI work.

Stop point: Iteration 0 ends here. No training, dataset download, compute purchase or
full-app development was started.

## 9. Iteration 0 completion criteria — status and evidence

| Criterion | Status | Evidence |
| --- | --- | --- |
| Environment detected, gaps and real versions listed | **verified** | section 1 above; `flutter doctor -v` output; `docs/progress.md` |
| Flutter Android project created with M1 responsibility separation | **verified** | `lib/` layout, `flutter analyze` clean, `docs/traceability.md` architecture rows |
| Image import, preview, cancel and error handling implemented | **verified** (logic + UI + emulator) | 30 passing tests; `docs/emulator_verification.md` |
| Model-not-implemented state shown honestly, no fake recognition | **verified** | `lib/services/unavailable_species_classifier.dart`; widget test asserting no candidate/confidence text |
| This iteration's unit/widget tests and static analysis actually executed and reported | **verified** | `flutter analyze` → No issues found; `flutter test` → 30 tests passed |
| Android debug build result recorded | **verified** | `✓ Built …/app-debug.apk`, log at `docs/logs/iteration0_build_debug_apk.log`; packaged `minSdkVersion:'26'` |
| Emulator run of the flow | **verified** | `docs/emulator_verification.md`, `docs/logs/emulator_0*.png`, 0 crash lines |
| Physical-device run verified, or unverified items and manual steps listed | **blocked** (no phone attached) | section 5 states the emulator result and lists the exact manual steps |
| README, traceability, progress and handover match the current project | **verified** | this file, `docs/traceability.md`, `docs/progress.md`, `README.md` |
| Artefacts published where the marker can reach them | **verified** | <<repository-url>> (public, `main`), `reference/` and `build/` excluded |

