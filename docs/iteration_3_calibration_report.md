# Iteration 3 calibration report

Date: 2026-09-11. Scope: freeze the FR2 quality-gate thresholds and the FR4 confidence threshold on
held-out data, plus real physical-camera verification. The classifier itself is **frozen**: no
retraining, no data expansion, no class changes, no QAT, and **the sealed test split was not opened**.

## 1. Model frozen as the final candidate

| Item | Value |
| --- | --- |
| Model | `assets/models/fieldsnap_float.tflite` (FP32 MobileNetV3-Small, data version 2) |
| Model SHA-256 (prefix) | `e6b10afdfc97d73d…` |
| Validation images used for calibration | 163 |
| Model top-1 on that split | 0.4785 |
| INT8 artefact | kept as experimental, not deployed (`docs/model_selection.md`) |

No training run was performed in this iteration.

## 2. Physical camera verification (Pixel 8 / Android 17)

Full record: `docs/physical_camera_verification.md`. All four required paths were exercised on
hardware with the real camera app (`app.grapheneos.camera`):

| Path | Result |
| --- | --- |
| Successful capture | shutter + confirm returned a genuine 1.8 MB photo; the app previewed it, and the quality gate then rejected it (sharpness 2.5) because the camera faced a featureless surface — correct FR2 behaviour |
| Cancellation | camera Back kept the previous image and its quality verdict; gallery Back left the screen unchanged |
| Permission denial | platform dialog → "Don't allow" → typed `permissionDenied`, explained in the UI, gallery route preserved |
| Gallery fallback | a gallery image was selected successfully on the same device after the refusal |

Screenshots: `docs/logs/iteration3_camera_01_permission_denied.png`, `..._02_capture_success.png`,
`..._03_cancel_keeps_image.png`. Zero crashes.

## 3. FR2 quality gate — calibrated and frozen

Protocol: `docs/quality_gate_calibration_protocol.md` (pre-registered, with recorded amendments).
Data: the validation split divided **by observation** into a calibration subset (81 images) and a
verification subset (82 images), each expanded deterministically into four conditions
(bright / dark / overexposed / blurred) — 652 images, no image or observation in both subsets.

**Frozen thresholds** (`QualityGateConfig`, pinned by a test against the artefact):

| Threshold | Value |
| --- | --- |
| `minBrightness` | **0.26** |
| `maxBrightness` | **0.89** |
| `minLaplacianVariance` | **100.0** |
| `analysisSize` | 224 |

Measured on the **independent verification subset**, in one pass after freezing:

| Condition | Reject recall | False-reject rate |
| --- | --- | --- |
| dark (should reject) | 1.000 | — |
| blurred (should reject) | 0.988 | — |
| overexposed (should reject) | **0.171** | — |
| bright (acceptable) | — | **0.012** |

Binary view over the verification subset (acceptable vs unacceptable):
precision **0.540**, recall **0.988**, false rejection **0.012**;
1 of 82 acceptable images were wrongly rejected.

**Calibrated: yes** for dark, blurred and the false-rejection budget. **Overexposure detection is weak**
and is reported as such: the clipped condition overlaps valid bright photos, so `maxBrightness` is a
safety ceiling rather than a detector, and the binary precision of 0.540 is dominated by that
overlap rather than by the dark/blur behaviour (recall 0.99 there).

## 4. FR4 confidence threshold — calibrated on the validation split

Protocol: `docs/confidence_threshold_calibration_protocol.md` (pre-registered). Data: the validation
split only (163 images), scored once with the shipped FP32 model through the production preprocessor.

Rule: keep thresholds with coverage ≥ 0.70, then take the highest accepted-prediction accuracy; ties
prefer higher coverage, then the lower threshold.

| Threshold | Coverage | Accepted accuracy |
| --- | --- | --- |
| 0.00 | 1.000 | 0.479 |
| 0.30 | 0.816 | 0.549 |
| **0.37 (chosen)** | **0.712** | **0.595** |
| 0.50 | 0.528 | 0.686 |
| 0.60 | 0.368 | 0.817 |
| 0.70 | 0.276 | 0.911 |

**Frozen threshold: 0.37** (coverage 0.712, accepted accuracy 0.595), recorded in
`artifacts/confidence_threshold_calibration.json` with model SHA-256
`e6b10afdfc97d73d…`, validation manifest SHA-256 `d4c53c176a559775…`, run id
`20260911T190219-e6b10afd`, git commit `5770fb2608e0` and protocol SHA-256 `fa79154f566daf88…`.

**M1's accepted-accuracy target of ≥ 0.90 is NOT met** at any threshold that keeps coverage at or above
0.70. It is reached only at 0.70, where coverage falls to 0.276 — i.e. by rejecting about three
quarters of the photos. Both facts are recorded; the target was not adjusted, and the threshold was
frozen by the pre-registered rule rather than by preferring the flattering point.

The margin rule is left **off** (`marginThreshold: null`): calibrating a second interacting rule on the
same split would weaken the calibration, and adding it is listed as future work.

## 5. Peak memory — observational, with a repeatable protocol

`tools/measure_peak_memory.sh` samples `dumpsys meminfo` on a physical device and reports the maximum.
Measured on the Pixel 8 (debug build):

| State | Peak TOTAL PSS |
| --- | --- |
| Idle capture screen | 362.8 MB |
| After gallery pick → quality gate → on-device classification | **421.0 MB** |

Details and caveats: `docs/peak_memory_protocol.md`. There is no pass/fail threshold; the debug-build
figures are stated as such, the per-sample log is kept, and `dumpsys` does not expose the Flutter
engine's native allocations as a usable column (reported as unavailable, not as zero).

## 6. Protocol amendments made during this iteration (recorded, not silent)

| # | Amendment | Measured reason |
| --- | --- | --- |
| 1 | FR2: each threshold chosen by a **univariate sweep** rather than a combined evaluation | the original rule evaluated one condition with another threshold applied, so one check censored another and every rate became meaningless (bright false rejection reported as 0.90) |
| 2 | FR2: overexposure transform raised from luma × 1.6 to × 2.5 | × 1.6 left the maximum brightness at 0.931, below the 0.95 ceiling, so the condition could not be detected (recall 0.062) |
| 3 | FR2 rule 2 (`maxBrightness`): smallest value in [0.80, 0.95] with zero bright false rejections | the original objective picked 0.80, costing 1.2% false rejections for +0.4 recall; the next revision picked 1.00, removing the ceiling entirely (overexposed recall 0.000) |
| 4 | FR2 acceptance: overexposure recall reported, not required | the clipped condition is not separable from bright valid photos, so the 0.90 goal was unachievable by construction |
| 5 | FR2 implementation: the reported `false_reject_rate` was defined as `accepted/n` for the acceptable condition instead of `rejected/n`, inverting every feasibility test | found by tracing a contradictory result; the definition is now stated in the code beside the metric |

Each amendment is written into the protocol document beside the original text.

## 7. Tests and checks

| Suite | Result |
| --- | --- |
| `flutter analyze` | clean |
| Deterministic tests | 99 passed, 2 skipped (calibration harnesses need local artefacts) |
| New pinned-threshold test | frozen FR2 values must equal the calibration artefact, and `calibrated: true` is asserted |
| Host integration | 7 passed |
| Device integration (Pixel 8) | 5 passed |

## 8. Explicitly still closed

* **The sealed test split has not been read.** It stays closed until explicit approval; the thresholds
  are now frozen, which is the precondition for that evaluation.
* No retraining, no data expansion, no class changes, no QAT.
* Usability testing has not started (no participants, no SUS, no fabricated data).
* The GitHub unreachable-object cleanup is deliberately left alone on the owner's instruction:
  rewriting history now would invalidate the SHAs the submission evidence references. The only
  privacy content ever exposed was the device serial, which is gone from `main`.
