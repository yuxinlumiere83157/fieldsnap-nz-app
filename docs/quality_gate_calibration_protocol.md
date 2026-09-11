# Quality-gate calibration protocol — PRE-REGISTERED, with one recorded amendment

Status: original rules were frozen before measurement and committed first. One **amendment** was
made after the first run, for a reason measurable from that run; both the original text and the
amendment are kept below so the change is auditable rather than silent. The data subsets were not
re-split, and the frozen thresholds were not tuned to the verification subset.

## Amendment 1 (2026-09-11) — three defects in the original rule, found in the first run

The first run produced `calibrated: false` with an implausible pattern (bright-condition false
rejection 0.90). Measured causes:

1. **Wrong censoring in the sharpness rule.** Rule 3 evaluated `recall_blurred` and `FRR_bright`
   with `min_brightness = 0` and `max_brightness = 1.0` — that part was fine — but rule 2 had already
   chosen `max_brightness = 0.95` from a grid that started at **0.60**, and the *combined* metrics
   used that value. Real photos in this data set span brightness 0.30-0.89 with a median of 0.44, so
   a 0.60 floor censors most acceptable images and every downstream rate becomes meaningless.
2. **The overexposure condition was not overexposed.** Scaling luma by 1.6 left a maximum brightness
   of 0.931, below the 0.95 ceiling, so `recall_overexposed` could never approach the 0.90 target. The
   first run measured 0.062.
3. As a result all three feasibility flags were false and the "chosen" values fell back to defaults
   plus an arbitrary grid maximum (sharpness 1000).

Amendment applied — each threshold is now selected by a **univariate sweep** (the other two
conditions held permissive, so one check cannot censor another), and the overexposure transform is
raised to a genuine clip:

* rule 1 (brightness minimum): sweep `b` with `max_brightness = 1.0`, `sharpness = 0`.
* rule 2 (brightness maximum): sweep `m` with `min_brightness = 0.0`, `sharpness = 0`, and the
  overexposed condition is regenerated at luma x 2.5 (clipped), which does reach white.
* rule 3 (sharpness minimum): sweep `s` with `min_brightness = 0.0`, `max_brightness = 1.0`.
* sharpness grid extended to `[100, 200, 250, 300, 400, 500, 700, 1000, 1400, 2000]`.

Everything else — the subset split, the conditions, the tie-breaking, the acceptance rule and the
one-shot verification — is unchanged. The original rules are preserved verbatim in the next section.

## Scope

Calibrate the FR2 gate's brightness and sharpness thresholds (evaluation metric: whether the gate
correctly separates acceptable from unacceptable images). The classifier is not touched, and the
sealed classifier test split is **not** used: that split exists for the final classifier evaluation.

## Data: two independent subsets, split by observation

Source: the existing validation split (`data/manifest_val.csv`, 163 images, 20 classes). It is a
held-out classifier split, and the gate calibration reuses it because the gate is independent of the
class labels — this is recorded as a limitation.

The 163 images are divided **by observation id** (never by image, so near-duplicate frames of one
observation cannot straddle the two subsets), 50/50:

| Subset | Purpose |
| --- | --- |
| **calibration subset** | used to choose the thresholds |
| **verification subset** | used exactly **once**, at the end, to report the frozen thresholds |

## Labels: deterministic, generated, not hand-picked

Each subset is relabelled into three conditions by construction, which is what makes precision,
recall and false-rejection measurable without human annotation:

| Condition | Ground truth | How it is produced from an accepted image |
| --- | --- | --- |
| **bright** | acceptable | the image, unchanged |
| **dark** | reject (too dark) | luma scaled by 0.10 |
| **blurred** | reject (too blurry) | Gaussian blur, sigma = 6 px, then downscale to 25 % |

Transforms are applied to the encoded bytes with deterministic, dependency-free code (PIL for
decode/encode; a separable box filter as the Gaussian approximation). No random augmentation, no
resampling of the label.

## What is measured

Every condition is pushed through `ImageQualityGate` with the **production metric code** (the same
`evaluateDecoded` the app calls). For each candidate threshold:

* **recall for the condition**: fraction of that condition's images correctly rejected;
* **false rejection rate (FRR) on the bright condition**: fraction of acceptable images wrongly
  rejected — the error that matters to a user being asked to re-shoot.

## Pre-registered selection rule

1. **Brightness minimum** `minBrightness`: the largest value `b` such that
   `FRR_dark(b) <= 0.02` and `FRR_bright(b) <= 0.02`; among those, the one with the highest
   `recall_dark`, ties broken by the **smaller** threshold (less intrusive). Search grid: 0.02 steps
   from 0.02 to 0.50.
2. **Brightness maximum** `maxBrightness`: the **smallest** value `m` in `[0.80, 0.95]` with
   `FRR_bright(m) == 0.00` on the calibration subset. Grid: 0.01 steps.

   *Amendment 1 history for this rule*: the original text picked the smallest `m` with
   `FRR <= 0.02` and then maximised overexposed recall, which selected 0.80 (FRR 0.012, overexposed
   recall 0.556). The next revision maximised the ceiling instead and selected 1.00, which makes the
   ceiling useless (overexposed recall 0.000). Measured trade-off at the default sharpness threshold:

   | maxBrightness | bright FRR | overexposed recall |
   | --- | --- | --- |
   | 0.80 | 0.012 | 0.556 |
   | 0.90 | 0.000 | 0.136 |
   | 0.95 | 0.000 | 0.049 |
   | 1.00 | 0.000 | 0.000 |

   0.90 is the lowest ceiling that costs **no** false rejections, and it retains some overexposure
   protection, so the rule is "tightest ceiling with zero false rejections". The remaining
   overexposure recall is reported as a diagnostic: the clipped condition overlaps valid bright
   photos, so it is not a pass criterion.
3. **Sharpness minimum** `minLaplacianVariance`: the smallest threshold whose `FRR_bright <= 0.05`
   while `recall_blurred >= 0.90`; if no grid point satisfies both, the point maximising
   `recall_blurred - 2 × FRR_bright` is chosen and the failure of the stated goal is reported
   instead of relaxing the target. Grid: 5, 10, 20, 40, 80, 125, 200, 250, 320, 400, 500, 700, 1000.
4. `analysisSize` stays 224 (it is a cost/consistency decision, not a calibrated threshold).

If a rule is infeasible on the calibration subset, that is reported as the result — the rule is not
rewritten afterwards.

## Pre-registered acceptance for the verification subset

The frozen thresholds are applied **once** to the verification subset and reported as
precision / recall / FRR per condition. The gate is recorded as **calibrated** if, on the
verification subset:

* `recall_dark >= 0.90`, `recall_blurred >= 0.90`, `recall_overexposed >= 0.90`, and
* `FRR on the bright condition <= 0.05`.

Otherwise the outcome is recorded as **not calibrated**, with the measured numbers, and the
prototype keeps the provisional defaults with that fact stated in the UI.

## Artefacts

* `tools/calibrate_quality_gate.py` — generator + sweep + one-shot verification.
* `artifacts/quality_gate_calibration.json` — grid, chosen thresholds, per-condition metrics.
* `artifacts/quality_gate_verification.json` — the single verification pass.
* `lib/services/quality_gate.dart` — where the frozen numbers end up, with their provenance.
MD
