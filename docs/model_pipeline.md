# Model pipeline (checkpoint 1B)

Purpose of this checkpoint: prove that a **real** model can be trained, quantised, exported
and executed inside the Flutter app, with the label order and tensor contract verified. It is
**not** a claim that Milestone 1's accuracy targets are met — see the measured numbers below.

## Result summary

| Item | Value |
| --- | --- |
| Architecture | MobileNetV3-Small, ImageNet weights, `include_top=False` |
| Classes | 20 (10 birds, 10 plants — the candidate list in `docs/species_candidates.md`) |
| Training data | 849 train / 163 validation / 187 sealed test images, 614 observations total |
| Epochs run | 14 head-only + **3 fine-tuning** epochs (see docs/checkpoint_1c_report.md: the fine-tune phase did not run before 1C) |
| Training accuracy (last epoch) | 0.5842 |
| Best validation top-1 (training curve) | 0.411 |
| Exported float model, validation top-1 / top-3 | **0.2454 / 0.5276** |
| Exported INT8 model, validation top-1 / top-3 | **0.1534 / 0.4479** |
| Float model size | 3.60 MiB |
| INT8 model size | **1.17 MiB** (NFR4 target ≤ 15 MB) |
| Input contract | float32 RGB `[1,224,224,3]`, values in `[-1, 1]` |
| Output contract | float32 `[1,20]` probabilities, order = `data/class_indices.json` |

**Correction (checkpoint 1C).** Earlier revisions of this document reported a fine-tuning phase
that never ran, and an unexplained gap between the training curve and the exported model. Both are
fixed: see `docs/checkpoint_1c_report.md`. The current numbers above are from the corrected run.

These are validation numbers on a deliberately small, equal-per-class sample. M1's targets
(top-1 ≥ 80%, top-3 ≥ 95%, macro-F1 ≥ 0.80) are **not** claimed and cannot be claimed from a
frozen-ImageNet-base run of this size. The test split has not been read.

## How to reproduce

```sh
python3 tools/fetch_dataset.py --per-class 60     # CC0/CC BY only, ~1 req/s to the API
python3 tools/make_split.py                       # freezes data/split_protocol.json
python3 tools/verify_split.py                     # leakage/licence/integrity gate
python3 tools/train_and_export.py --epochs 15 --fine-tune-epochs 3
python3 tools/eval_validation.py                  # validation only, never the test split
python3 tools/export_reference_fixture.py         # cross-language fixtures
python3 tools/measure_preprocessing.py --stage pixels   # needs Pillow + TensorFlow
python3 tools/measure_preprocessing.py --stage compare
flutter test                                      # 43 deterministic tests
flutter test --tags integration                   # real model, cross-language check
```

## Three real bugs this pipeline caught

These are worth keeping in the record because each one produced **plausible-looking output**
rather than an obvious crash.

1. **The fine-tune phase was silently skipped** because Keras `epochs` is an absolute end epoch,
not an increment, and the recorded `final_val_accuracy` duplicated the training accuracy. Fixed
with explicit epoch arithmetic plus mandatory evidence (optimizer steps and a post-unfreeze weight
delta). Details and before/after numbers: `docs/checkpoint_1c_report.md`.

2. **`mobilenet_v3.preprocess_input` is a no-op in Keras 3.** The function is documented in
   the source as "a placeholder method for backward compatibility … does nothing". Calling it
   left the tensors in `[0, 255]` while the base model had `include_preprocessing=False`, so
   training diverged (loss ≈ 2800, accuracy stuck near chance). Fixed with an explicit
   `(x - 127.5) / 127.5` plus a runtime `assert` on the batch range, because a scale error is
   invisible until the loss explodes.

3. **The Dart preprocessor initially skipped the rescaling.** `tflite_flutter` happily ran the
   model on `[0, 255]` input and returned confident predictions. The cross-language test
   (`test/integration/tflite_cross_check_test.dart`) caught it by comparing against the Python
   reference. This is exactly why that test exists: a wrong tensor scale does not raise, it
   lies.

4. **TFLite conversion crashed on the in-graph `Normalization` layer.** Converting the Keras
   model that had `include_preprocessing=True` aborted MLIR lowering with
   `ReadVariableOp … missing attribute 'value'`. Converting through a SavedModel export
   (which constant-folds the frozen weights) works, and moving the preprocessing out of the
   graph keeps it stable; the report records which converter path produced each asset.

## Known limitations (measured, not assumed)

- **Resize implementation differs between Python and Dart.** The app resizes with the Dart
  `image` package (area averaging), the reference resizes with `tf.image.resize`
  (`antialias=True`). `tools/measure_preprocessing.py` measures the effect on 40 validation
  images: maximum probability difference **0.1332**, mean
  **0.0508**, top-1 agreement **0.95**, top-3
  set agreement **0.75**. A trained model should not care this much, which is itself
  evidence that this small model is under-trained; the mitigation is for training, evaluation
  and the app to share one resize implementation.
- **INT8 costs about 11 points of validation top-1** (0.282 → 0.172) and flips the argmax on
  the reference image. The cross-language test therefore asserts exact agreement for the float
  model and only a bounded probability difference for the int8 model.
- **Overfitting is visible**: training accuracy 0.642 against validation 0.282 with only ~45
  images per class. More data per class (the fetch target is configurable) and unfreezing more
  of the base are the obvious next levers.
- **The INT8 model is not full-integer**: input and output stay float32
  (`quantization_scale = 0.0`, `zero_point = 0`) so the app can feed ordinary floats. Weights
  are quantised, which is where the size reduction comes from.
- The model binaries are **not committed** (`assets/models/*.tflite` is git-ignored); the
  committed `class_indices.json` is the auditable artefact, and the report records sizes and
  tensor shapes.

## On-device verification (emulator)

`integration_test/on_device_inference_test.dart` runs the real Android TFLite runtime through
the FFI binding and passed on the Android 16 emulator:

```sh
flutter test integration_test/on_device_inference_test.dart -d emulator-5554
# 00:06 +1: All tests passed!
```

It asserts the model loads on device, that the loaded tensor contract is
`[1,224,224,3]` in / `[1,20]` out with 20 labels, and that inference produces a normalised
distribution whose top class is not a chance-level guess. That is the part host tests cannot
cover: the native library really does load and run on Android.

The debug APK built for that run is 196 MB, of which the bundled model assets are
**1.17 MiB for the INT8 model** plus the 0.6 MiB reference photo used only by this test.
M1's release-package ≤ 80 MB target refers to a **release** build with the app's own assets,
which has not been built or measured yet; a debug APK is not that metric.

## Where the pieces live

| Path | Role |
| --- | --- |
| `lib/services/image_preprocessor.dart` | pixels → model tensor, `[-1, 1]`, area resize |
| `lib/services/tflite_inference_engine.dart` | the only file importing `tflite_flutter`; validates the tensor contract at load |
| `lib/services/tflite_species_classifier.dart` | engine → top-3 `ClassificationResult`, typed failures |
| `lib/services/model_labels.dart` | label order + display names |
| `tools/train_and_export.py` | training, float + INT8 export, `artifacts/model_report.json` |
| `tools/eval_validation.py` | validation-set evaluation of both `.tflite` files |
| `test/integration/tflite_cross_check_test.dart` | Python/Dart agreement on tensor and prediction |

The bundled asset is the INT8 model (1.20 MiB). The float model is kept in `artifacts/` for
comparison and for the cross-language test.

### Running the integration check on this machine

`tflite_flutter` resolves its macOS library relative to the `flutter_tester` binary as
`<engine dir>/resources/libtensorflowlite_c-mac.dylib`. The pub package ships that dylib, so
for host-side testing it was copied to

```sh
cp ~/.pub-cache/hosted/pub.dev/tflite_flutter-0.12.1/macos/libtensorflowlite_c-mac.dylib \
   "$HOME/development/flutter/bin/cache/artifacts/engine/resources/"
```

The test skips itself (rather than failing) when the library is absent, so a fresh clone is not
broken by this machine-specific step. On Android the library comes from the plugin, so no such
step is needed for the app itself.
