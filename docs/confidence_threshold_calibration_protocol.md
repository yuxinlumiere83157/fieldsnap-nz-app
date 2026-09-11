# Confidence-threshold calibration protocol — PRE-REGISTERED

Status: frozen before measurement, committed before the sweep was run. Any change is a new version
with a recorded reason.

## Scope

Choose the single global top-1 confidence threshold for the **deployed FP32 model**
(`assets/models/fieldsnap_float.tflite`, data version 2). The model is frozen: no retraining, no data
expansion, no class changes. The **sealed test split is not used** and is not opened by this work.

## Data

`data/manifest_val.csv` — the validation split (163 images, 20 classes), identified by its file
SHA-256. The model has never been trained on it and it is not the test split. Every image is
classified once with the production preprocessing (`ImagePreprocessor`) and the shipped model.

## Pre-registered selection rule

For every threshold `t` on a grid of 0.01 steps from 0.00 to 0.99:

* **coverage** `c(t)` = fraction of validation images whose top-1 score is `>= t`;
* **accepted accuracy** `a(t)` = accuracy among exactly those accepted images.

Selection:

1. keep only thresholds with `c(t) >= 0.70` (Milestone 1's coverage floor);
2. among those, take the threshold with the **highest** `a(t)`;
3. ties are broken by **higher coverage**; if still tied, the **lower** threshold.

If no threshold reaches `c(t) >= 0.70`, the sweep is reported as infeasible and the outcome is
recorded as **not calibrated**.

## What is reported

* the full sweep (`threshold`, `coverage`, `accepted_accuracy`, `accepted`, `rejected`);
* the frozen threshold with **model SHA-256, validation manifest SHA-256, run id and git commit**;
* whether M1's target of **accepted accuracy >= 0.90** is actually achieved at the chosen point;
* the accepted/rejected accuracy at a few reference points (0.0, 0.45 the old provisional default,
  the chosen value) so the choice is interpretable rather than a bare number.

The classifier metrics (top-1, top-3, macro-F1) on the validation split are already recorded in
`artifacts/validation_results.json`; this protocol only chooses the abstention threshold.

## Where the result is frozen

* `artifacts/confidence_threshold_calibration.json` — sweep and chosen value with provenance;
* `lib/services/confidence_policy.dart` — the deployed configuration, with `isValidated: true` only
  if the rule was satisfied;
* `docs/iteration_3_calibration_report.md` — the summary, including the honest statement of whether
  the 0.90 target was met.

The sealed test split remains closed until explicit approval.
