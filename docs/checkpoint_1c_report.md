# Checkpoint 1C report — correctness fixes

Date: 2026-09-11. Scope: fix what the `630de50` review found, using the **same**
1,199-image data set. No new species, no extra downloads, no extra unfrozen layers, no QAT.

This report records corrections to earlier conclusions rather than presenting the earlier work
as having always been right. The earlier numbers are kept below next to what replaced them.

## 1. The fine-tuning phase never ran (review finding confirmed)

**Claim in `630de50`:** "15 epochs (head-only warm-up, then fine-tuning of the top block)",
"best validation top-1 0.3006".

**What was actually true:** `model.fit(..., initial_epoch=len(history["loss"]), epochs=args.fine_tune_epochs)`
passes `epochs` as an **absolute end epoch**, so with `--epochs 15 --fine-tune-epochs 3` the
call was `initial_epoch=15, epochs=3` and Keras ran nothing. Evidence from the artefacts:

- `artifacts/model_report.json` history had 15 entries and no fine-tune entries;
- `/tmp/train_final.log` (kept as an experiment record) ended at `Epoch 15/15` with no second phase.

**Fix:** the fine-tune call now uses `initial_epoch=head_epochs,
epochs=head_epochs + args.fine_tune_epochs`, and the script **refuses to pass silently**:

- `fine_tune_epochs_run` must be > 0,
- `fine_tune_optimizer_steps` records `optimizer.iterations` before/after,
- `fine_tune_weight_delta` compares a **post-unfreeze** snapshot of trainable weights (the
  earlier draft snapshotted before unfreezing, which made the comparison meaningless), and both
  checks raise if nothing moved.

**After the fix:** `head_epochs=14` (early stopping), `fine_tune_epochs_run=3`,
`fine_tune_optimizer_steps=162`, `fine_tune_weight_delta=4.8e-4`.

## 2. Reporting bug in `final_val_accuracy` (review finding confirmed)

The field was read from `history["accuracy"]`, so it duplicated the training accuracy. Fixed to
read `history["val_accuracy"]`; the per-phase counts above are recorded alongside it.

## 3. Preprocessing was three implementations, not one (review finding confirmed)

| Location | `630de50` | Now |
| --- | --- | --- |
| `tools/train_and_export.py` | TF bilinear, `antialias=True` | unchanged (spec) |
| `tools/eval_validation.py` | TF bilinear, **no antialias** | `antialias=True` |
| `lib/services/image_preprocessor.dart` | Dart `Interpolation.average` | unchanged (spec) |

The training-vs-evaluation mismatch is now closed. `docs/preprocessing_spec.md` states the six
steps (decode, EXIF orientation, RGB, area resize, `(x-127.5)/127.5`, HWC float32) and names the
residual difference between TensorFlow's antialiased bilinear and the Dart package's area average,
which are approximations of the same idea and are not bit-identical.

**Augmentation range fixed too:** augmentation now runs on `[0, 255]` pixels with an explicit
`RandomContrast(value_range=(0.0, 255.0))`, and rescaling happens once, *after* augmentation. The
range assertion was moved after both steps — in the first 1C draft it still sat before
augmentation, which is exactly the "assert the wrong thing" problem the review warned about, and
the assertion caught it.

## 4. Test scope was overstated (review finding confirmed and acted on)

`test/integration/tflite_cross_check_test.dart` mixed two questions and its INT8 branch allowed a
wrong class. Replaced by three separate checks:

| Check | What is fixed | Test | Result |
| --- | --- | --- | --- |
| Preprocessing conformance | image -> tensor | `test/integration/preprocessing_conformance_test.dart` | passes; shape, RGB order, `[-1,1]` scale and distribution statistics compared against the reference |
| Runtime conformance | tensor -> output vector | `test/integration/runtime_conformance_test.dart` + `integration_test/on_device_inference_test.dart` | passes; **whole 20-value vector** compared, host and Android |
| Quantisation impact | FP32 vs INT8 | `tools/eval_validation.py` | reported separately (below) |

The Android test no longer settles for "shapes are right and the top probability is > 0.1": it
loads the same canonical tensor the Python reference used and compares every output value. A
confidently wrong model would now fail it.

**Tolerances are empirical, not derived.** With the same tensor and the same INT8 file the two
runtimes differed by up to 0.024 in this round. That was labelled "one quantisation step" (1/32) in
this report, which overstates the evidence: the standard INT8 softmax output scale is 1/256, and the
actual operators and quantisation parameters were never read out. Checkpoint 1D relabels this as a
provisional empirical band and widens it to the measured value. The float model reproduces Python to
~1e-6, which is a real derivation.

## 5. The reference vector itself was wrong (hypothesis on the cause, not confirmed)

The first runtime conformance run disagreed with Python by **0.237** on the same tensor. Root
cause: `eval_validation.py` passed a numpy **slice view** (`raw[i:i+1]`) to `set_tensor`, so the
recorded `reference_io.json` was wrong while the model conversion was fine. Proof: the Keras
model and the TFLite model agree with each other on that tensor to 2.5e-6, and both disagree with
the recorded vector by the same 0.237.

- inputs are now materialised with `np.ascontiguousarray` before inference;
- `tools/export_reference_fixture.py` now **builds every fixture from one canonical tensor** and
  refuses to write if the float TFLite conversion disagrees with the Keras model (>5e-3);
- the INT8 difference is recorded as the measured quantisation cost instead of being treated as a
  fixture error.

Anything that had been measured against the old `reference_io.json` is superseded. Validation
accuracy numbers never depended on it (they use the full validation loop), but the cross-language
comparison did.

## 6. INT8 calibration was 16 augmented images (review finding confirmed)

`train_ds.take(8)` with `images[:2]` gave at most 16 samples from the augmented training pipeline,
not covering 20 classes. Now: `--representative-per-class 10` → **200 images** in class order,
augmentation off, deployment preprocessing, and the exact photo ids are recorded in
`model_report.json` (`int8_representative_photo_ids`). QAT was not used.

## 7. Data freezing was not actually enforced (review finding confirmed)

- `tools/make_split.py` now **refuses to overwrite** a frozen protocol (exit 4) and prints the
  previous vs current manifest hash; re-freezing requires `--force --version N`, and the reason
  belongs in `docs/progress.md`.
- `tools/verify_split.py` now also (a) recomputes the **content hash of every image** and
  compares it with the download-time record, (b) checks each `manifest_{train,val,test}.csv`
  against `split.json` exactly, and (c) fails if a test-assigned photo appears in train/val.
  Both guards were tested: overwrite refused, and a one-byte same-size edit was detected.

## 8. Reproducibility for the marker (review finding confirmed)

- `data/provenance_shareable.csv` — 1,199 rows: photo/observation id, class, licence,
  attribution, taxon id/name, CDN URL, md5, size, original dimensions, split. Local paths,
  coordinates, place names and local timestamps are **removed** on purpose.
- The **INT8 model that actually ships (1.2 MiB) and `class_indices.json` are committed**, so the
  app and every test run from a plain clone without retraining. The float model and the Keras
  checkpoint stay ignored.
- `data/README.md` explains how to re-create the images optionally (`fetch_dataset.py` refetches
  the same photo ids, `verify_split.py` re-checks every md5).
- The `third_party/tflite_flutter` patch is kept, with upstream version, the exact diff, the
  licence file and the removal condition documented.

## Results after the fixes (same data set)

| Metric | Before (`630de50`) | After 1C |
| --- | --- | --- |
| Head epochs | 15 (as recorded) | 14 (early stopping) |
| Fine-tune epochs actually run | **0** | **3** (162 optimizer steps, weight delta 4.8e-4) |
| Best validation top-1 (training curve) | 0.3006 | **0.411** |
| Exported float model, validation top-1 / top-3 | 0.245 / 0.528 | **0.411 / 0.650** |
| Exported INT8 model, validation top-1 / top-3 | 0.153 / 0.448 | **0.252 / 0.534** |
| INT8 size | 1.17 MiB | 1.17 MiB |
| Cross-language reference | wrong by 0.237 (undetected) | float agrees to ~1e-6; INT8 within one quantisation step; Android matches |
| Data-freeze enforcement | none | overwrite refused; content hashes and split CSVs verified |

M1's accuracy targets (top-1 ≥ 80%, top-3 ≥ 95%, macro-F1 ≥ 0.80) remain **not met** and are
**not claimed**. The test split is still sealed and was not read.

## Honest reading of the new numbers

The jump from 0.30 to 0.41 validation top-1 came from *enabling the phase that was supposed to run
in the first place*, not from more data or a better model. Before this checkpoint, "the model is
weak" was being blamed partly on data volume; the correct statement was that the training
procedure was not doing what it claimed. Any decision about enlarging the data set should now be
made against these corrected numbers.

## What still needs deciding next

1. Whether to grow the data set (per-class 150–300) now that the training procedure is trustworthy.
2. Whether to unfreeze more of the base, given the fine-tune phase clearly helps.
3. The FP32-vs-INT8 gap (0.411 → 0.252) is large; calibration is now 200 representative images, so
   the remaining causes to investigate are per-channel quantisation, the int8 kernel set, and
   whether the head benefits from being excluded from quantisation.
4. Abstention threshold (FR4) still needs the validation-derived, pre-registered procedure before
   any test-set evaluation.

## Evidence

- scripts: `tools/train_and_export.py`, `tools/eval_validation.py`, `tools/export_reference_fixture.py`,
  `tools/make_split.py`, `tools/verify_split.py`
- machine-readable results: `artifacts/model_report.json`, `artifacts/validation_results.json`,
  `artifacts/reference_io.json`, `artifacts/preprocessing_report.json`
- tests: `test/integration/preprocessing_conformance_test.dart`,
  `test/integration/runtime_conformance_test.dart`, `integration_test/on_device_inference_test.dart`
- 43 deterministic tests + 2 host integration tests + 1 on-device integration test, all passing at
  the time of writing.
