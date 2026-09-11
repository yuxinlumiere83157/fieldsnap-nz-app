# Model selection record — FP32 baseline, INT8 experimental

Iteration 2 decision (2026-09-11), requested as part of the Core Product Integration iteration.

## Decision

**The prototype now deploys the FP32 TFLite model. The INT8 model is retained as an
experimental artefact and is not used by the app's default path.**

This is a change from the Milestone 1 design, which planned a quantized (INT8) model. It is
recorded as an evidence-based design change rather than a silent substitution.

## Evidence

Same validation split (163 images, 20 classes), same preprocessing specification, same
cross-checked conversion pipeline. Numbers from `artifacts/validation_results.json`
(run id and model hashes are recorded in that file):

| Model | Validation top-1 | Validation top-3 | Asset size | Source |
| --- | --- | --- | --- | --- |
| **FP32 `.tflite`** | **0.4969** | **0.7239** | **3.60 MiB** | `assets/models/fieldsnap_float.tflite` |
| INT8 `.tflite` | 0.3067 | 0.6135 | 1.17 MiB | `assets/models/fieldsnap_int8.tflite` |

The INT8 gap is **19 points of top-1**. Per-channel weight quantisation is enabled explicitly
(`int8_per_channel_disabled: false` in `artifacts/model_report.json`) and the gap persisted.
On this model the INT8 output stays close to a uniform distribution (top probability ≈ 0.22
versus ≈ 0.50 for FP32 on the same input), and the Python and Dart runtimes disagree by up to
~0.09 absolute probability on the *same* INT8 file and tensor — a difference that has **not**
been diagnosed (candidate causes: per-channel scales, the runtime's int8 kernels, or the
near-uniform softmax).

## Why FP32 is acceptable for this prototype

Milestone 1's requirement (NFR4) was a *quantized model ≤ 15 MB* and a *release package
≤ 80 MB*. The FP32 asset is **3.60 MiB**, still an order of magnitude inside the model-size
ceiling, so the size argument for INT8 does not outweigh a 19-point accuracy loss at this
stage. What the FP32 choice does **not** discharge:

* the release-package ≤ 80 MB target has still not been measured — that needs a **release**
  build, and no release APK/AAB has been produced yet;
* inference latency and memory (NFR2) are still unmeasured on a physical device;
* if the release package turns out to be too large, revisiting quantisation is the obvious
  lever, which is exactly why the INT8 artefact stays in the repository.

## Consequences recorded for Milestone 2

* The M1 plan's "convert to int8 where accuracy remains acceptable" is now "int8 was converted
  and measured; it was not adopted because the measured accuracy cost was unacceptable at this
  data scale; FP32 ships instead."
* The INT8 model is bundled so a teacher can run the comparison without retraining, and it is
  excluded from the app's default path (`TfliteInferenceEngine.defaultAsset` points at FP32).
* Both models must keep passing the runtime-conformance check against their recorded reference
  vectors, so a future mislabeling of which model ships would fail a test.

## Next questions (not resolved here)

1. Read the actual operator/quantisation parameters of the INT8 graph instead of inferring from
   the interface (float I/O) — the earlier "one quantisation step" reading was withdrawn.
2. Try FP16 weights as a cheaper trade-off (CPU converts to float32 at runtime); the size and
   latency claim would still need physical-device measurement.
3. Only after those: consider whether a larger training set changes the INT8 penalty.
