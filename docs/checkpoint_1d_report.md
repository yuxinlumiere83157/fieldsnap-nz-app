# Checkpoint 1D — gap closure, controlled data expansion, and honest corrections

Date: 2026-09-11. Scope: close the three verification gaps from the 1C review, then run **one**
controlled experiment that changes only the training data. No new species, no extra unfrozen
layers, no QAT, no deep quantisation research.

## 0. Wording corrections applied to earlier claims

Three statements in the previous report were stronger than the evidence. They are corrected here,
and the earlier files were updated rather than quietly rewritten.

| Earlier claim | Corrected statement |
| --- | --- |
| "A numpy slice view caused the contaminated reference" | **Unconfirmed hypothesis.** The evidence supports "the old reference did not match the current model and tensor; after generating every fixture from one canonical tensor they agree". `np.ascontiguousarray` may return the same object for already-contiguous input, and no minimal reproduction isolating the slice was run. Still recorded as a hypothesis in `docs/checkpoint_1c_report.md`. |
| "The runtimes differ by one or two quantisation steps (1/64, 1.5/64)" | **Not established.** The standard INT8 softmax output scale is 1/256, so observing 1/64 does not prove "one step". The actual operators and quantisation parameters have not been read out. The 1/32 and now 0.12 bounds are **provisional empirical tolerances**, labelled as such in the test files. |
| "The 0.30 → 0.41 improvement came from the fine-tuning phase finally running" | **Overstated.** That round changed fine-tuning execution, augmentation handling *and* evaluation preprocessing at the same time. The correct statement: **after fixing the training and evaluation pipeline, validation results improved; the individual contributions were not separated by a controlled experiment.** |
| "Android real-device runtime" | **"Android native runtime, run on the emulator"** — no physical device has been used. |

## 1. Gap 1 — preprocessing evidence (closed)

`test/integration/preprocessing_conformance_test.dart` no longer relies on whole-image statistics.

* **Synthetic asymmetric fixtures** with red / blue / green blocks in known corners; assertions read
  named regions per channel, so an R/B swap, a horizontal flip or a vertical flip fails.
* **All eight EXIF orientation values** are exercised, with fixtures written by Pillow such that
  Pillow's own `ImageOps.exif_transpose` recovers one known upright layout.
* **Two meta-tests** prove the checks can fail: a channel-swapped tensor and a mis-oriented tensor
  are both rejected by the same assertions that guard the real code.
* **Real photo**: per-element comparison against the Python reference, with the mean and max
  element difference reported (mean < 0.05, fewer than 2% of elements above 0.25). The resampling
  difference is now reported as element-wise error rather than hidden behind histograms.

**Two real defects found by this work:**

1. The `image` package's decoders do **not** populate EXIF at all —
   `decodeJpg(...).exif.imageIfd.orientation` is null even for a JPEG carrying the tag — so
   `bakeOrientation` never rotated anything. The app now parses the orientation from the JPEG APP1
   / PNG `eXIf` bytes itself (`lib/services/exif_orientation.dart`).
2. The package's orientation-6 branch rotates the stored pixels the **wrong way** relative to the
   EXIF specification. Pillow was used as the reference implementation and the transform table is
   verified against it for all eight values.

## 2. Gap 2 — evaluation script (closed)

`tools/eval_validation.py`:

* the strict Keras comparison applies to the **FP32 conversion only**; the INT8 difference is
  recorded as the quantisation cost. It no longer aborts a legitimate run (which used to leave the
  previous results file on disk);
* a missing Keras checkpoint is reported as `not-run: …`; it never fabricates a zero vector;
* results carry `run_id`, timestamp, data version, split-protocol and manifest hashes and model
  hashes, so a stale file cannot be mistaken for a fresh run;
* nothing is written unless the checks pass.

## 3. Gap 3 — clone reproducibility (closed, verified)

* `test/fixtures/reference_input.f32` is no longer git-ignored (the preprocessing test reads it).
* Runtime conformance is split into a **required** scope using only committed assets
  (`assets/models/fieldsnap_int8.tflite` + `assets/test/reference_output.json`) and a **research**
  scope that skips with an explicit reason when the uncommitted float model is absent.
* `tools/run_checks.py` reports passed / failed / errors / **skipped** separately.

**Fresh-clone verification** (new directory, `git clone` from GitHub, only `flutter pub get` run):

| Suite | Result |
| --- | --- |
| `flutter analyze` | clean |
| `flutter test --exclude-tags integration` | 41 passed, 0 failed, 0 errors, 0 skipped |
| `flutter test --tags integration` | 6 passed, 0 failed, **1 skipped** (float model is research-only) |
| `flutter test integration_test/on_device_inference_test.dart -d emulator-5554` | 2 passed, 0 failed |

The skip is the float-vs-Keras comparison, which needs `artifacts/fieldsnap_float.tflite`; that is
reported as a skip, never as a pass.

## 4. Controlled data expansion (training set only)

Decision applied: train on ~150 images per class, keep validation and test exactly as they were, do
not change the architecture, unfreeze range, learning rate or epoch budget.

| | v1 (1A) | expanded (v2) |
| --- | --- | --- |
| Training images | 849 | **2,995** |
| Per-class training images | 36–49 | **149–150** |
| Validation / test | 163 / 187 (unchanged) | 163 / 187 (unchanged) |
| New observations | — | 1,073 new observations used |
| Held-out observations respected | — | yes (guard refuses overlap) |

Data integrity work for this step:

* `tools/expand_training_data.py` fetches only NEW observations and never re-randomises the frozen
  protocol (`make_split.py --force` is not used);
* `tools/build_train_manifest.py` re-applies the leakage guard and **drops** any row sharing an
  observation with validation or test, printing each drop. It dropped **3** rows that the fetch-time
  exclusion had missed (house_sparrow, nikau, woolly_nightshade). The cause of that miss is not
  confirmed, which is exactly why the guard is re-applied rather than trusted;
* version record: `data/data_version_2.json`, with manifest hashes for v1 and v2.

**Result — same validation set, same configuration, only the data changed:**

| Metric | small (849) | expanded (2,995) | change |
| --- | --- | --- | --- |
| Validation top-1 | 0.4479 | **0.5031** | **+0.055** |
| Validation top-3 | 0.6748 | **0.7485** | **+0.074** |
| Macro-F1 | 0.4239 | **0.4993** | **+0.075** |

Per-class F1 and the full confusion matrix are in `artifacts/comparison_small.json` and
`artifacts/comparison_expanded.json`. Worst classes by F1 in the expanded run: house_sparrow,
blackbird, pohutukawa, moth_plant, starling. M1's targets (top-1 ≥ 80%, top-3 ≥ 95%,
macro-F1 ≥ 0.80) remain **unmet**; the test split is still sealed.

### FP32 vs INT8 on the expanded model

| Model | Validation top-1 | Validation top-3 | Size |
| --- | --- | --- | --- |
| FP32 `.tflite` | **0.497** | **0.724** | 3.60 MiB |
| INT8 `.tflite` (per-channel weights, float I/O) | **0.307** | **0.613** | 1.17 MiB |

**The INT8 gap is 19 points of top-1**, larger than in the previous round. Per-channel weight
quantisation was made explicit (`int8_per_channel_disabled: false` in the model report) and the
gap persists. The same-model cross-runtime difference is up to ~0.09 absolute probability, and the
INT8 output stays close to uniform (top probability ~0.22 versus ~0.51 for float).

Conclusions drawn, deliberately limited:

* FP32 remains the **correctness and integration baseline**; INT8 is an **experimental variant**
  and is not selected as the deployment model;
* the quantisation cause is **not** diagnosed. Reading the actual operator and quantisation
  parameters, and evaluating FP16 as a cheaper alternative, are the next steps if the size/accuracy
  trade-off is to be pursued;
* this is a design-relevant finding for M2: if the project does not end up adopting INT8, the
  change from the M1 plan must be recorded as a design change with these measurements.

## 5. App features (parallel track) — not started in this checkpoint

The owner asked that camera input, offline learning cards and local history not wait for the model
to hit its targets. **They have not been started yet**: this checkpoint was consumed by the three
gap closures plus the controlled experiment. They remain the next product work, to be connected
through the existing service interfaces, with the UI continuing to state that the model is
experimental. No low-confidence threshold has been "validated on the validation set" and none is
claimed; any UI flow that needs one must use a test double and say so.

## 6. Evidence index

| Item | Path |
| --- | --- |
| Preprocessing conformance | `test/integration/preprocessing_conformance_test.dart`, `lib/services/exif_orientation.dart`, `test/fixtures/exif/orientation_*.png` |
| Runtime conformance (host) | `test/integration/runtime_conformance_test.dart` |
| Runtime conformance (Android, emulator) | `integration_test/on_device_inference_test.dart` |
| Check runner with pass/fail/skip | `tools/run_checks.py` |
| Evaluation with run metadata | `tools/eval_validation.py`, `artifacts/validation_results.json` |
| Expansion + leakage guard | `tools/expand_training_data.py`, `tools/build_train_manifest.py`, `data/data_version_2.json` |
| Controlled comparison | `tools/compare_training_sets.py`, `artifacts/comparison_{small,expanded}.json` |
| Model report | `artifacts/model_report.json` |
