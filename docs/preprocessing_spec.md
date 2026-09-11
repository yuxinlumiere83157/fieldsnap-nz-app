# Canonical preprocessing specification (checkpoint 1C)

One spec, implemented three times (training, Python evaluation, Dart app). The point of
writing it down is that the three implementations previously disagreed, and a mismatch here
is invisible: the model still returns confident probabilities.

## The steps, in order

| # | Step | Decision | Why |
| --- | --- | --- | --- |
| 1 | Decode | JPEG/PNG bytes to RGB | App reads whatever the picker returned |
| 2 | Orientation | apply EXIF orientation | A rotated photo is a different tensor; the app's `image` decoder and Python must agree |
| 3 | Colour | convert to RGB, drop alpha | Model input is 3 channels |
| 4 | Resize | **area averaging / box filter** to 224x224 | Downscaling ~2000 px to 224 px must antialias; area averaging is the reference filter |
| 5 | Scale | `(pixel - 127.5) / 127.5` on 0-255 values | Gives `[-1, 1]`, what MobileNetV3 expects with `include_preprocessing=False` |
| 6 | Layout | HWC, row-major, float32, `[1,224,224,3]` | TFLite input contract |

Keras's `mobilenet_v3.preprocess_input` is **not** step 5: in Keras 3 it is a no-op
placeholder, which is how a previous run silently trained on `[0, 255]`.

## Implementations

| Where | Implementation |
| --- | --- |
| `tools/train_and_export.py` | `tf.image.resize(..., method="bilinear", antialias=True)` on decoded pixels, then explicit rescale; augmentation runs **before** the rescale, in `[0, 255]` |
| `tools/eval_validation.py` | `tf.image.resize(..., antialias=True)` + explicit rescale (same call, same order) |
| `tools/export_reference_fixture.py` | the tensor itself is produced by the evaluation code path, so it *is* the reference |
| `lib/services/image_preprocessor.dart` | `image` package `copyResize(interpolation: Interpolation.average)` + explicit rescale |

Note the residual difference: TensorFlow's antialiased bilinear and the Dart package's area
average are different filters that both approximate area resampling. They are not bit-identical,
which is why the tensor comparison in the tests has an explicit, measured tolerance rather than
claiming equality. `tools/preprocessing_conformance.json` holds the measured band, and
`docs/checkpoint_1c_report.md` records how it was obtained.

## Verification split (1C)

| Check | Fixes | Test |
| --- | --- | --- |
| Preprocessing conformance | image -> tensor | `test/integration/preprocessing_conformance_test.dart` compares the Dart tensor against a tensor produced by the Python reference for the same image |
| Runtime conformance | tensor -> output vector | `test/integration/runtime_conformance_test.dart` feeds one fixed tensor to both engines and compares the whole vector; `integration_test/on_device_inference_test.dart` does the same on Android against a recorded reference vector |
| Quantisation impact | FP32 vs INT8 | `tools/eval_validation.py` reports both models on the same validation images |

Keeping these apart matters: a Python/Dart difference on the *same* INT8 model is an execution
difference, and must not be excused as "quantisation loss".
