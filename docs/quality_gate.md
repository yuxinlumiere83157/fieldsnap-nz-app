# FR2 quality gate — metrics, thresholds and how they were chosen

The gate is deliberately **not** a model. Two explainable metrics with configurable thresholds
(`lib/services/quality_gate.dart`):

| Metric | Definition | Why |
| --- | --- | --- |
| **Brightness** | mean luma of the image after converting to grayscale, reported in `[0, 1]` | Too dark and blown-out photos are the two most common beginner mistakes; the mean is trivially explainable to the user. |
| **Sharpness** | variance of the 4-neighbour Laplacian over grayscale pixels, computed on the **0-255** scale | The classic Laplacian blur detector: sharp edges give a large variance, a flat or smeared image gives ~0. Cheap, deterministic, no training, and explainable. |

## Thresholds (calibrated, Iteration 3)

```dart
QualityGateConfig(
  minBrightness: 0.26,
  maxBrightness: 0.89,
  minLaplacianVariance: 100.0,
  analysisSize: 224,
)
```

These are **frozen calibration results**, not development guesses. The pre-registered procedure is
`docs/quality_gate_calibration_protocol.md`; the measurement is
`artifacts/quality_gate_calibration.json` and the single verification pass is
`artifacts/quality_gate_verification.json`. On the independent verification subset the gate measured
dark recall 1.000, blurred recall 0.988 and a false-rejection rate of
0.012 on acceptable images; overexposure recall (0.171) is reported but not a
pass criterion, because the clipped condition overlaps valid bright photos.

A test pins the code values to that artefact (`test/quality_and_history_test.dart`), so changing a
threshold without re-running the calibration and updating the record fails the suite. Thresholds are
injectable, which is how tests exercise the failure branches
(`QualityGateConfig(minLaplacianVariance: 100000)` flips a passing image to "too blurry").

## Development samples (historical, kept for context)

The figures below were the *development* measurements used before calibration. They are kept because
the calibration protocol references them, but they are **no longer the deployed thresholds**: the
frozen values are the calibrated ones above.

Measured on 2026-09-11 using the same 224x224 area-resized analysis image the gate uses:

| Sample | Brightness | Laplacian variance | Verdict |
| --- | --- | --- | --- |
| 12 real data-set photos (JPEG, iNaturalist) | 0.25–0.57 | 898–4718 | pass |
| Flat mid-grey fill | 0.498 | 0.0 | too blurry |
| Flat near-white fill | 0.980 | 0.0 | too bright |
| Checkerboard, luma 0.02 | 0.010 | 15.1 | too dark |
| Checkerboard, 4 px blocks | 0.345 | 25046 | pass |
| Checkerboard, 8 px blocks | 0.345 | 4422 | pass |

What those samples established (still true of the calibrated values): a flat image measures 0
Laplacian variance, near-black sits near 0.01 brightness and near-white near 0.98, and real photos
span roughly 0.25-0.57 brightness with 898-4718 variance. The calibrated thresholds sit inside those
gaps.

## Calibration summary

| Threshold | Value | Verification-subset evidence |
| --- | --- | --- |
| `minBrightness` | {ct['min_brightness']} | dark reject recall {vs['dark']['reject_recall']:.3f} |
| `maxBrightness` | {ct['max_brightness']} | bright false rejection {vs['bright']['false_reject_rate']:.3f} (safety ceiling) |
| `minLaplacianVariance` | {ct['min_laplacian_variance']:.1f} | blurred reject recall {vs['blurred']['reject_recall']:.3f} |

## A bug this measurement caught

The first version computed the Laplacian on `[0, 1]` normalised pixels while the threshold was
written for `0-255` units, which divides the metric by 255² — every real photo was rejected as
"too blurry". The gate now keeps brightness normalised (for its threshold) and the Laplacian in
0-255 units, and `docs/quality_gate.md` (this file) records the units so the next person does not
repeat it.

## Limitations, stated plainly

* These thresholds come from **development samples**, not from a labelled usability or
  classification study: they are not claimed as tuned for accuracy.
* The gate must never be presented as protecting accuracy until someone measures precision/recall
  of the gate itself against human labels.
* The gate runs on the decoded image on the UI isolate. At 224x224 that is a few milliseconds, but
  it has not been profiled on a physical device; if it shows up in traces it should move to the same
  background isolate as inference.
* FR2's requirement is "assess basic image suitability and request another image"; the UI does
  exactly that (it blocks identification and explains the measured value), but the gate is advisory
  in the sense that the user can always pick a different photo.
