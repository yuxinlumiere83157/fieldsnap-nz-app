# Iteration 2 report — Core Product Integration

Date: 2026-09-11. Baseline: `9f3dea5` (checkpoint 1D). This iteration adds the core product
workflow on top of the verified model pipeline: camera capture, quality gate, on-device
classification in the UI, learning cards, history, and the Uncertain state.

## 1. Input-contract correction (done first, as instructed)

The documentation and the code comment claimed the deployed models expect `[0, 255]` input with
internal rescaling. That was stale: both exported models use `include_preprocessing=False` and
expect **externally preprocessed float32 RGB in `[-1, 1]`**.

* `lib/services/tflite_species_classifier.dart` and `tflite_inference_engine.dart` now state the
  `[-1, 1]` contract, and the engine's `contract` map reports it.
* `TfliteInferenceEngine.assertInputInRange` is a new runtime guard: a `[0, 255]` tensor raises an
  explanatory `ArgumentError` instead of silently degrading accuracy. It runs at the top of every
  `run()`.
* `tools/train_and_export.py`'s docstring now describes the contract that was actually produced
  (and why: the in-graph `Normalization` layer broke MLIR lowering, so the arithmetic moved out).
* **Regression tests**: `test/model_input_contract_test.dart` (7 tests) asserts that a `[0, 255]`
  tensor is rejected, that a `[-1, 1]` tensor from the real preprocessor passes, that skipping the
  rescale is caught, and that the recorded `model_report.json` agrees with the code.

## 2. Deployment baseline: INT8 → FP32

Recorded in `docs/model_selection.md` with the evidence:

| Model | Validation top-1 | Validation top-3 | Asset size |
| --- | --- | --- | --- |
| **FP32 (shipped)** | **0.4969** | **0.7239** | **3.60 MiB** |
| INT8 (experimental) | 0.3067 | 0.6135 | 1.17 MiB |

The FP32 asset is far inside M1's 15 MB model-size ceiling, so a 19-point accuracy loss is not a
good trade at this data scale. `TfliteInferenceEngine.defaultAsset` points at FP32,
`experimentalInt8Asset` keeps INT8 available, both are bundled, and both stay covered by
conformance tests. The M1 plan's "convert to int8 where accuracy remains acceptable" is now
recorded as "converted, measured, not adopted".

## 3. FR1 camera capture

* `CameraImageInput` extends the image-input boundary with `captureFromCamera()`.
* `FileSystemImageInput` implements it via `image_picker`; gallery failures keep
  `platformFailure`, camera failures map to the recoverable `permissionDenied` (a refused
  permission, a device with no camera app, or a missing plugin).
* `AndroidManifest.xml` declares `CAMERA` plus `uses-feature ... required="false"`, so the app
  stays installable on devices without a camera and falls back to the gallery.
* Cancellation keeps the previously selected image; the denial path is recoverable and the gallery
  remains available (asserted in both unit and widget tests).
* **Not verified**: a real camera on a physical device. The emulator's virtual camera was not used
  to capture a photo, so the claim here is "the code path is implemented and tested with a stub",
  not "photographing works on hardware".

## 4. FR3 on-device classification in the UI, off the UI isolate

* `BackgroundRunner` is the isolation boundary (`IsolateBackgroundRunner` in production,
  `InlineBackgroundRunner` for tests). It reports `isIsolate`, so no test can accidentally claim
  off-isolate execution.
* `OnDeviceSpeciesClassifier` runs preprocessing **and** inference inside `Isolate.run`, transfers
  only plain numbers and labels, and maps failures to typed results.
* `TfliteInferenceEngine` validates the tensor contract at load (float32 NHWC, output width ==
  label count) and asserts the input range per run.
* Tests: `test/background_inference_test.dart` proves the production runner really executes on a
  different isolate (an isolate-local marker set in the parent is invisible to the child), and the
  ViewModel tests prove the classifier is driven through its runner.
* UI: `ResultPanel` shows the species, the italic scientific name, the confidence with the
  threshold, the top-3 candidate list, an isolate latency line, and the learning card.
* **Emulator run, measured**: 4628 ms for one classification. This is an **emulator** number on a
  CPU-only simulator host and must not be reported as device performance; NFR2 remains unmeasured.

## 5. FR2 quality gate (no new model)

`ImageQualityGate` computes two explainable metrics — mean luma (brightness) and the variance of
the Laplacian on the 0-255 scale (sharpness) — with thresholds in `QualityGateConfig`. The UI shows
the verdict with the measured value and the threshold, and blocks identification when the gate
fails.

Thresholds were chosen from **development samples** and the reasoning is in `docs/quality_gate.md`:
12 real photos measured 0.25–0.57 brightness and 898–4718 Laplacian variance; flat images measure
0.0; near-black 0.01 brightness; near-white 0.98. Defaults: 0.12 / 0.95 / 250.

That measurement caught a real bug: the first version computed the Laplacian on `[0, 1]` values
while the threshold was in 0-255 units, so **every** real photo was rejected as blurry. It is now
recorded with its units.

## 6. FR5 offline learning cards

`assets/data/species_cards.json` holds all **20** species (common name, scientific name, Māori
name, identification marks, where to look, native/introduced/pest status). `SpeciesCardRepository`
loads it from the bundle; a test asserts that every model label has a card, that no slug is
duplicated, and that an unknown label returns null instead of an invented species.

## 7. FR6 local history

SQLite schema and the decision not to store photographs are documented in `docs/history.md`.
Records keep the species, confidence, runner-up, the Uncertain flag, the threshold **and whether it
was validated**, the quality metrics, and the model identity. `main.dart` opens
`SqfliteHistoryRepository` with an in-memory fallback.

**Verified on the emulator**: after a real classification the history screen listed the Tūī record
with `68% | threshold 45% (unvalidated)` and `fieldsnap_float.tflite (FP32, data v2) | brightness
0.60, sharpness 1773.3`. Delete-one and clear-all are implemented; the widget tests cover both.

## 8. FR4 ConfidencePolicy and the Uncertain state

`ConfidencePolicyConfig` + `ConfidencePolicy` implement an accept threshold and an optional
margin rule. The Uncertain state is fully rendered (it says the app is *not* asserting a species
and lists the closest candidates as non-assertions).

**No production threshold is locked or claimed as validated.** The default (0.45 / 0.10) is marked
`isValidated: false`, the UI says so in words, and every history row records the flag. Tests inject
explicit thresholds to hit both branches. Deriving the real threshold is documented as the next
step in `docs/confidence_policy.md`.

## 9. Test and check status

| Suite | Result |
| --- | --- |
| `flutter analyze` | clean |
| Deterministic tests | **91 passed**, 0 failed, 0 skipped |
| Host integration (`--tags integration`) | 7 passed |
| On-device integration (emulator) | 2 passed (shipped FP32 vector match at 1e-3; INT8 artefact still loads) |
| Emulator end-to-end run | gallery pick → quality pass → FP32 classification (Tūī 67.5%) → history row; 0 crashes |

New tests this iteration: input-contract regression (7), camera capture (5), quality gate and
history components (22), isolate boundary (6), plus the rewritten ViewModel (24) and widget (10)
suites.

## 10. A real bug found by running the app

The first emulator launch failed with `Unable to load asset: "assets/data/species_cards.json"`
because the cards file was written but never registered in `pubspec.yaml`. Caught by actually
running the app rather than by tests, fixed, and re-verified. Worth recording: unit and widget tests
cannot catch an unregistered asset, because they read the file from disk.

## 11. Physical device — now verified (Google Pixel 8, Android 17)

A Pixel 8 running Android 17 (API 37, arm64, 7.5 GB RAM) was connected and the full run was done on
hardware; details, commands and screenshots are in `docs/physical_device_run.md`. Summary:

| Item | Result |
| --- | --- |
| Device conformance test | 4 passed on hardware (FP32 vector matches the Python reference within 1e-3) |
| Latency, profile build, M1 §7 protocol (warm-up + 30 runs) | inference median **101.65 ms**, P95 **155.27 ms** → **NFR2 passes** (≤300/≤500 ms) |
| Full CPU path (decode + preprocess + inference) | median 314.42 ms, P95 351.87 ms (reported; the extra ~213 ms is decoding/resampling, not model execution) |
| Release APK size (NFR4 ≤ 80 MB) | **76.3 MB → pass** (fat APK; AAB 72.0 MB) |
| Core workflow on device | gallery → quality gate (brightness 0.28, sharpness 378.7) → FP32 inference → Kōwhai 57.5% → history row; 0 crashes |

Two things this run produced that belong in the record:

* **A real defect**: the first `--profile` build failed because
  `android/app/src/profile/AndroidManifest.xml` contained `--` inside an XML comment. Debug builds
  never parse that file, so it had been broken since Iteration 0. Fixed; all manifests now verified
  to parse.
* **A confident misclassification**: the chosen photo (a kererū validation image) was answered
  **Kōwhai 57.5%** on device, crossing life forms — consistent with the background/shortcut
  hypothesis in `docs/model_error_analysis.md`. One anecdotal sample; nothing was changed because
  of it.

Note on the test OS: M1 planned Android 15 as the principal test OS; the available device runs
Android 17. That difference is recorded rather than glossed over.

## 12. Deliberately not done

* No expansion of the data set, no change to the 20 classes, no QAT.
* The sealed test split was not read.
* No formal usability evaluation was started (no participants, no SUS, no fabricated numbers).
* The quality-gate thresholds and the confidence threshold are **not** claimed as validated.
* `docs/model_error_analysis.md` records the weakest validation classes and hypotheses for them;
  no model change was made on the basis of that analysis.

## 13. Evidence

| Item | Path |
| --- | --- |
| Model selection record | `docs/model_selection.md` |
| Input-contract regression tests | `test/model_input_contract_test.dart` |
| Quality gate design + calibration | `docs/quality_gate.md`, `lib/services/quality_gate.dart` |
| Confidence policy | `docs/confidence_policy.md`, `lib/services/confidence_policy.dart` |
| History schema + no-photo decision | `docs/history.md`, `lib/services/sqflite_history_repository.dart` |
| Isolation boundary | `lib/services/background_runner.dart`, `test/background_inference_test.dart` |
| On-device classifier | `lib/services/on_device_species_classifier.dart` |
| Learning cards | `assets/data/species_cards.json`, `lib/services/species_cards.dart` |
| UI | `lib/views/capture_screen.dart`, `lib/views/result_panel.dart`, `lib/views/history_screen.dart` |
| Emulator screenshots | `docs/logs/iteration2_01_initial.png`, `iteration2_02_picked.png`, `iteration2_03_result.png`, `iteration2_04_history.png` |
| Error analysis | `docs/model_error_analysis.md` |
