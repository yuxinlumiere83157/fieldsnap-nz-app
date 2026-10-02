# Traceability — Milestone 1 requirements → current code → verification

Implementation status and verification status are deliberately **separate** columns.
"Implemented" means code exists in this repository; "Verified" means it was actually
executed and observed. A test using a fake never verifies real-device behaviour.

Status legend: `done` · `partial` · `pending` · `blocked` · `not run` · `not verified`

Last updated: 2026-09-11 (Iteration 0).

**Baseline verified against the real report.** The Milestone 1 PDF is now present at
`the local Milestone 1 report` (the Milestone 1 report, kept locally and not committed). The
requirement wording, process plan, logical decomposition, runtime behaviour, physical
deployment targets and evaluation thresholds below were read from that document: scope and
requirements on pp. 5–6, process on pp. 7–8, technology and logical decomposition on
pp. 9–13, runtime characteristics on pp. 13–15, physical characteristics on pp. 16–17 and
evaluation criteria on pp. 17–19. Component names in the "Expected component" column are
taken from M1's own requirements-to-component table (p. 12) and its class/component
diagrams (Figures 2–3).

## Functional requirements (from the M1 design baseline)

| ID | Requirement (M1 design) | Expected component (M1 Table 4) | Implementation | Verification | Evidence path |
| --- | --- | --- | --- | --- | --- |
| FR1 | Capture a single photograph or import an existing image | `CaptureView`, `ClassifierViewModel` | **partial** — `CaptureScreen` + `ClassifierViewModel` + `ImageInput`/`FileSystemImageInput`; gallery import done and verified on an Android 16 emulator; **camera capture pending** | unit + widget tests pass; real system Photo Picker exercised on emulator; **physical device not yet** | `lib/services/file_system_image_input.dart`, `docs/emulator_verification.md` |
| FR2 | Assess basic image suitability; request another image when blur/brightness heuristics fail | `ClassifierViewModel`, `ImageQualityService` | **pending** — not started, nothing faked | `not run` | — |
| FR3 | Classify fully on-device; return top-3 candidates with confidence values | `ImagePreprocessor`, `InferenceService`, `Prediction` | **partial** — `SpeciesClassifier` boundary and `ClassificationResult` (top-3 shape) exist; `UnavailableSpeciesClassifier` reports `modelUnavailable` | unit tests confirm the boundary never invents candidates | `lib/services/species_classifier.dart`, `lib/services/classification_result.dart`, `lib/services/unavailable_species_classifier.dart` |
| FR4 | Return `Uncertain` below a validation-derived threshold instead of asserting a species | `ClassifierViewModel`, `Prediction` | **pending** — threshold must be derived from validation data and frozen before test evaluation | `not run` | — |
| FR5 | Offline learning card (common + scientific name, ID hints) | future `LearningCardView` + local species data | **pending** | `not run` | — |
| FR6 | Save/view/delete local recognition history | future `HistoryRepository` + data access | **pending** — no SQL yet | `not run` | — |

Iteration 0 acceptance slice (start → pick one local image → preview → replace/clear,
with cancellation and failure recovery) is implemented and covered by
`test/capture_screen_test.dart` and `test/classifier_view_model_test.dart`.

## Non-functional requirements and evaluation targets

M1 states these as targets to validate, not achieved results.

| ID | Target (M1) | Implementation | Verification | Evidence path |
| --- | --- | --- | --- | --- |
| NFR1 | Complete capture-to-learning-card path works in airplane mode, no account, no image upload | **partial** — no networking code, no INTERNET permission in the main manifest and no account; the full path cannot exist yet (FR2–FR6 pending) | static check of manifest and dependency list | `android/app/src/main/AndroidManifest.xml`, `pubspec.yaml` |
| NFR2 | Median inference ≤ 300 ms, P95 ≤ 500 ms on the designated Android device | **pending** — no inference exists | `not run` (impossible before a model exists) | — |
| NFR3 | Classification must not block Flutter's main UI isolate | **pending** — nothing to isolate yet; M1 names `IsolateInterpreter` in `tflite_flutter` as the intended mechanism | `not run` | `docs/plan.md` |
| NFR4 | Quantized model ≤ 15 MB, release package ≤ 80 MB, measured from a release build | **pending** — no model; a debug APK is explicitly not this metric | `not run` | — |
| NFR5 | UI, state management, inference and persistence separately testable | **partial** — UI/state/adapter boundaries exist and are tested with substituted dependencies (M1 logical-view criterion); inference and persistence not built | `flutter analyze`, `flutter test`; no view imports the interpreter or SQLite | `lib/`, `test/` |
| NFR6 | ≥ 90% first-task completion without facilitator intervention, SUS ≥ 70, critical interaction errors = 0, with at least five representative novice users (target five per the lecturer's clarification; ≥ 90% applies as 5/5 at that sample size) | **pending** — requires real participants; fabricating this is prohibited. The analysis script reports an interim individual result below five sessions and does not declare the criterion | `not run` | — |
| Model targets | Held-out test set: top-1 ≥ 80%, top-3 ≥ 95%, macro-F1 ≥ 0.80, reported per class | **pending** — no dataset, no training | `not run` | — |
| Uncertainty | Accuracy among accepted predictions ≥ 90% at ≥ 70% coverage, threshold chosen on validation data and frozen before test evaluation | **pending** — no model and no validation split | `not run` | — |
| Runtime protocol | At least 30 repeated single-image runs after warm-up; profile/release build on a physical device; Flutter DevTools frame inspection | `not run` — protocol recorded here so it is fixed before measurement | `not run` | M1 p. 18 |
| Error paths | Denied permission, unsuitable image and low confidence all terminate in a recoverable UI state with no crash and no misleading identification | **partial** — cancellation, unreadable file, unsupported/plugin failure and recovery are implemented and tested; denied-permission and low-confidence paths need the camera and model work | widget tests cover the implemented paths; camera path `not run` | `test/capture_screen_test.dart` |
| Memory | Peak process memory recorded as an observational metric; no fixed RAM threshold | `not run` | — | M1 p. 17 |

## Platform targets

| Target (M1) | Reality in this repository | Decision recorded |
| --- | --- | --- |
| ARM64 Android physical device, API 26 or later | `minSdk` pinned to **26** in `android/app/build.gradle.kts`, `targetSdk`/`compileSdk` 36 | aligned with M1 pp. 9–10 and p. 16 rather than left at Flutter's default 24 |
| Android 15 as principal test OS, real device | verified on an **emulator** (Android 16 / API 36, arm64, Pixel 6 profile) instead; no physical device attached | physical-device verification remains open; emulator numbers must never be reported as device performance |
| CPU inference is the mandatory baseline; GPU/NNAPI delegates optional and never a functional dependency | no inference yet | to be honoured in the inference integration |
| iOS delivery | not part of the Milestone 2 acceptance baseline | no iOS platform folder exists |

## Build and check results for this iteration

| Check | Result | Evidence |
| --- | --- | --- |
| `flutter analyze` | clean — `No issues found!` | reproduced in `docs/iteration0_report.md` §3 |
| `flutter test` | 30 passed (16 ViewModel, 6 adapter, 8 widget) | `test/` |
| `flutter build apk --debug` | succeeded, `app-debug.apk` (144 MB debug artefact), packaged `minSdkVersion:'26'` | `docs/logs/iteration0_build_debug_apk.log` |
| `flutter doctor -v` (2026-09-11, historical: `cmdline-tools` was missing then) | Flutter valid; Android SDK present; that gap was closed later the same day — see `docs/emulator_verification.md` | `docs/iteration0_report.md` §1 |
| Emulator end-to-end run | **verified**: install → launch → real Photo Picker → preview with correct file metadata → replace → cancel keeps state → clear; 0 crash/Flutter-error lines in logcat | `docs/emulator_verification.md`, `docs/logs/emulator_verification_20260911.log`, `docs/logs/emulator_0*.png` |
| Physical-device run | **not run** — no Android phone attached | manual steps in `docs/emulator_verification.md` §6 |

The debug APK exists only to prove the Android build chain works. Its size is not the
NFR4 package metric and its startup time is not the NFR2 inference metric.


