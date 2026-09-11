#!/usr/bin/env python3
"""1B step 1 — small transfer-learning run and TFLite export (float + INT8).

Baseline: MobileNetV3-Small with ImageNet weights (M1's chosen architecture). The
Keras application's built-in preprocessing layer is kept ENABLED, which is the trap
flagged in review: with `include_preprocessing=True` the model expects float input in
[0, 255] and does its own rescaling to [-1, 1]. The exported tensor contract is printed
and saved so the Flutter side can assert the same thing instead of guessing.

Discipline:
  * reads only manifest_train.csv / manifest_val.csv — the test split stays sealed;
  * the split protocol (seed, ratios, manifest hash) is read from data/split_protocol.json
    and copied into the run report, so results can be tied to a frozen protocol;
  * no QAT, no GPU delegate, no purchased compute;
  * this proves the pipeline only. It is NOT evidence that M1's accuracy targets are met.
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import pathlib
import sys

import numpy as np

REPO = pathlib.Path(__file__).resolve().parents[1]
DATA = REPO / "data"
ARTIFACTS = REPO / "artifacts"
IMG_SIZE = 224
BATCH = 16


def class_names() -> list[str]:
    """Deterministic label order shared by training, export, Python checks and Flutter."""
    path = DATA / "class_indices.json"
    if path.exists():
        return json.loads(path.read_text())["classes"]
    protocol = json.loads((DATA / "split_protocol.json").read_text())
    return sorted(protocol["per_class"].keys())


def load_split(split: str, names: list[str], manifest: pathlib.Path | None = None
               ) -> tuple[list[str], np.ndarray]:
    import csv

    index = {name: i for i, name in enumerate(names)}
    paths: list[str] = []
    labels: list[int] = []
    source = manifest if manifest is not None else DATA / f"manifest_{split}.csv"
    with open(source) as fh:
        for row in csv.DictReader(fh):
            paths.append(str(REPO / row["file_path"]))
            labels.append(index[row["class_slug"]])
    return paths, np.array(labels, dtype="int32")


def make_dataset(paths, labels, names, training: bool):
    import tensorflow as tf

    ds = tf.data.Dataset.from_tensor_slices((paths, labels))
    if training:
        ds = ds.shuffle(len(paths), seed=20260911, reshuffle_each_iteration=True)

    def _load(path, label):
        raw = tf.io.read_file(path)
        # See tools/compare_training_sets.py: a few "photos" are PNG and one is an animated GIF.
        image = tf.io.decode_image(raw, channels=3, expand_animations=False)
        # Area averaging (antialiased), matching the app's preprocessor closely. Plain
        # bilinear downscaling from ~2000 px to 224 px changes the model's answer on some
        # classes; tools/measure_preprocessing.py quantifies the residual difference
        # between the Python and Dart resamplers.
        image = tf.image.resize(image, (IMG_SIZE, IMG_SIZE), method="bilinear",
                                antialias=True)
        # Deliberately still in [0, 255] here: augmentation layers such as
        # RandomContrast default to `value_range=(0, 255)`, so normalising first would
        # make the augmentation a no-op or a distorting one. See docs/preprocessing_spec.md.
        return tf.cast(image, tf.float32), label

    ds = ds.map(_load, num_parallel_calls=tf.data.AUTOTUNE)

    def _rescale(image, label):
        # Single, explicit rescaling point for the whole pipeline (spec step 5).
        return (image - 127.5) / 127.5, label

    if training:
        augmentation = tf.keras.Sequential([
            tf.keras.layers.RandomFlip("horizontal"),
            tf.keras.layers.RandomRotation(0.05),
            # Explicit value_range: the layer default is (0, 255), and this pipeline now
            # feeds it 0-255 pixels on purpose rather than relying on that default.
            tf.keras.layers.RandomContrast(0.1, value_range=(0.0, 255.0)),
        ])
        ds = ds.map(lambda x, y: (augmentation(x, training=True), y),
                    num_parallel_calls=tf.data.AUTOTUNE)

    # Guard the input contract at runtime, in the only position where it means anything:
    # after augmentation and after rescaling, i.e. on exactly what the model receives. A
    # wrong scale here is invisible until the loss explodes (it cost one training run).
    def _check(image, label):
        tf.debugging.assert_greater_equal(tf.reduce_min(image), -1.05,
                                          message="training input below [-1, 1]")
        tf.debugging.assert_less_equal(tf.reduce_max(image), 1.05,
                                       message="training input above [-1, 1]")
        return image, label

    ds = ds.map(_rescale, num_parallel_calls=tf.data.AUTOTUNE)
    ds = ds.map(_check, num_parallel_calls=tf.data.AUTOTUNE)
    return ds.batch(BATCH).prefetch(tf.data.AUTOTUNE)


def build_model(num_classes: int) -> "object":
    import tensorflow as tf
    from tensorflow.keras import layers

    base = tf.keras.applications.MobileNetV3Small(
        input_shape=(IMG_SIZE, IMG_SIZE, 3),
        include_top=False,
        weights="imagenet",
        include_preprocessing=False,  # preprocessing happens in the input pipeline
    )
    base.trainable = False
    inputs = tf.keras.Input(shape=(IMG_SIZE, IMG_SIZE, 3), name="image")
    x = base(inputs, training=False)
    x = layers.GlobalAveragePooling2D()(x)
    x = layers.Dropout(0.2)(x)
    x = layers.Dense(num_classes, activation="softmax", name="predictions")(x)
    model = tf.keras.Model(inputs, x)
    model.compile(
        optimizer=tf.keras.optimizers.Adam(1e-3),
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"],
    )
    return model



def converter_for(model):
    """Build a TFLite converter.

    `from_keras_model` aborted in MLIR lowering for this frozen MobileNetV3 graph
    ("ReadVariableOp ... missing attribute 'value'"). Exporting to SavedModel first
    (which constant-folds the frozen weights) gives the converter a different, working
    path, so that is preferred; the Keras path is kept as a fallback and the one that
    succeeded is recorded in the report.
    """
    import tempfile

    import tensorflow as tf

    try:
        saved_dir = pathlib.Path(tempfile.mkdtemp(prefix="fieldsnap_saved_")) / "model"
        model.export(saved_dir)
        return tf.lite.TFLiteConverter.from_saved_model(str(saved_dir)), "saved_model"
    except Exception as error:  # pragma: no cover - depends on the local toolchain
        print(f"saved_model export failed ({error}); falling back to from_keras_model")
        return tf.lite.TFLiteConverter.from_keras_model(model), "keras_model"


def describe(path: pathlib.Path) -> dict:
    import tensorflow as tf

    interpreter = tf.lite.Interpreter(model_path=str(path))
    interpreter.allocate_tensors()
    info: dict[str, object] = {"file": path.name, "bytes": int(path.stat().st_size)}
    for tag, details in (("input", interpreter.get_input_details()),
                         ("output", interpreter.get_output_details())):
        entry = details[0]
        scale, zero = entry["quantization"]
        info[tag] = {
            "name": str(entry["name"]), "shape": [int(v) for v in entry["shape"]],
            "dtype": np.dtype(entry["dtype"]).name,
            "quantization_scale": float(scale), "quantization_zero_point": int(zero),
        }
    return info


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--epochs", type=int, default=15)
    parser.add_argument("--fine-tune-epochs", type=int, default=5,
                        help="extra epochs with the top block unfrozen (0 disables)")
    parser.add_argument("--representative-per-class", type=int, default=10,
                        help="INT8 calibration images per class (10 x 20 classes = 200)")
    parser.add_argument("--train-manifest", default=None,
                        help="versioned training manifest; defaults to data/manifest_train.csv")
    parser.add_argument("--data-version", type=int, default=1)
    args = parser.parse_args()

    import tensorflow as tf
    tf.random.set_seed(20260911)

    names = class_names()
    (DATA / "class_indices.json").write_text(json.dumps(
        {"classes": names, "index": {n: i for i, n in enumerate(names)},
         "note": "order is the model's output order; the app must use exactly this list"},
        indent=2, sort_keys=True))

    train_manifest = pathlib.Path(args.train_manifest) if args.train_manifest else None
    train_paths, train_labels = load_split("train", names, train_manifest)
    val_paths, val_labels = load_split("val", names)
    print(f"classes={len(names)} train={len(train_paths)} val={len(val_paths)} "
          f"(test split deliberately not loaded)")

    train_ds = make_dataset(train_paths, train_labels, names, training=True)
    val_ds = make_dataset(val_paths, val_labels, names, training=False)

    model = build_model(len(names))
    model.summary()

    callbacks = [
        tf.keras.callbacks.EarlyStopping(monitor="val_accuracy", patience=5,
                                         restore_best_weights=True),
    ]
    head = model.fit(train_ds, validation_data=val_ds, epochs=args.epochs,
                     callbacks=callbacks, verbose=2)
    head_epochs = len(head.history["loss"])
    history: dict[str, list[float]] = {k: list(v) for k, v in head.history.items()}

    # Keras treats `epochs` as an absolute end epoch and `initial_epoch` as the starting
    # index, so the fine-tune call must pass `head_epochs + n`, not `n`. Passing `n` made
    # the whole phase a silent no-op in an earlier revision (it ended before it started).
    fine_epochs_run = 0
    weights_before: list[np.ndarray] = []
    if args.fine_tune_epochs > 0:
        base = model.layers[1]
        base.trainable = True
        for layer in base.layers[:-20]:
            layer.trainable = False
        model.compile(
            optimizer=tf.keras.optimizers.Adam(1e-5),
            loss="sparse_categorical_crossentropy",
            metrics=["accuracy"],
        )
        # Snapshot AFTER unfreezing: the earlier revision snapshotted before it, so the list
        # held only the head's weights and the comparison was meaningless either way.
        weights_before = [w.numpy().copy() for w in model.trainable_weights]
        steps_before = int(model.optimizer.iterations.numpy())
        fine = model.fit(train_ds, validation_data=val_ds,
                         initial_epoch=head_epochs,
                         epochs=head_epochs + args.fine_tune_epochs,
                         callbacks=callbacks, verbose=2)
        fine_epochs_run = len(fine.history["loss"])
        for key, values in fine.history.items():
            history.setdefault(key, []).extend(values)
        steps_after = int(model.optimizer.iterations.numpy())
        fine_tune_steps = steps_after - steps_before
        if fine_epochs_run == 0 or fine_tune_steps == 0:
            raise RuntimeError(
                "fine-tuning requested but no epoch/step ran; check the "
                "epochs/initial_epoch pair")
        weights_after = [w.numpy() for w in model.trainable_weights]
        moved = [
            float(np.abs(a - b).max())
            for a, b in zip(weights_before, weights_after)
            if a.shape == b.shape
        ]
        if not moved or max(moved) == 0.0:
            raise RuntimeError("fine-tuning ran but changed no trainable weight")
        fine_tune_weight_delta = max(moved)
    else:
        fine_tune_weight_delta = None

    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    keras_path = ARTIFACTS / "fieldsnap_mobilenetv3s.keras"
    model.save(keras_path)

    # ---- TFLite float ----
    converter, source = converter_for(model)
    float_model = converter.convert()
    float_path = ARTIFACTS / "fieldsnap_float.tflite"
    float_path.write_bytes(float_model)

    # ---- TFLite INT8 (full integer) ----
    # Representative samples for INT8 range estimation. Google's guidance is a few hundred
    # samples; the previous revision used at most 16, drawn from the augmented training
    # pipeline, which did not even cover all 20 classes. This version takes the first N
    # training images in class order (deterministic, augmentation OFF, same preprocessing as
    # deployment) and records exactly which photo ids were used.
    import csv as _csv

    representative_rows: list[dict] = []
    with open(train_manifest if train_manifest else DATA / "manifest_train.csv") as fh:
        by_class: dict[str, list[dict]] = {}
        for row in _csv.DictReader(fh):
            by_class.setdefault(row["class_slug"], []).append(row)
    per_class = max(1, args.representative_per_class)
    for slug in names:
        representative_rows.extend(by_class.get(slug, [])[:per_class])

    def representative():
        interpreter_ds = make_dataset(
            [str(REPO / r["file_path"]) for r in representative_rows],
            np.array([names.index(r["class_slug"]) for r in representative_rows], dtype="int32"),
            names,
            training=False,
        )
        for images, _ in interpreter_ds:
            for image in images:
                yield [tf.expand_dims(image, 0)]

    int8_converter, int8_source = converter_for(model)
    int8_converter.optimizations = [tf.lite.Optimize.DEFAULT]
    # Per-channel weight quantisation: without it a whole conv kernel shares one scale, which
    # is a known cause of large INT8 accuracy loss on small models. `_experimental_disable_
    # per_channel` is False by default in recent converters, but it is set explicitly here so
    # the intent is recorded rather than assumed.
    int8_converter._experimental_disable_per_channel = False
    int8_converter.representative_dataset = representative
    int8_converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
    # input/output stay float so the app can feed ordinary float preprocessing
    int8_model = int8_converter.convert()
    int8_path = ARTIFACTS / "fieldsnap_int8.tflite"
    int8_path.write_bytes(int8_model)

    specs = [describe(float_path), describe(int8_path)]
    report = {
        "created_at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        "tensorflow": tf.__version__,
        "architecture": "MobileNetV3Small (imagenet, include_preprocessing=False)",
        "input_contract": "float32 RGB in [-1, 1]; apply (x - 127.5) / 127.5 to [0, 255] "
                          "pixels exactly once. The model does NOT rescale internally.",
        "preprocessing_reference": "(pixel - 127.5) / 127.5 applied once, in the app",
        "converter_source": {"float": source, "int8": int8_source},
        "int8_per_channel_disabled": bool(int8_converter._experimental_disable_per_channel),
        "image_size": IMG_SIZE,
        "classes": names,
        "epochs_run": len(history["loss"]),
        "head_epochs_run": head_epochs,
        "fine_tune_epochs_run": fine_epochs_run,
        "fine_tune_optimizer_steps": fine_tune_steps if args.fine_tune_epochs > 0 else 0,
        "fine_tune_weight_delta": fine_tune_weight_delta,
        "history": {k: [round(float(v), 4) for v in vals]
                    for k, vals in history.items()},
        "final_train_accuracy": round(float(history["accuracy"][-1]), 4),
        "final_val_accuracy": round(float(history["val_accuracy"][-1]), 4)
        if "val_accuracy" in history else None,
        "best_val_accuracy": round(float(max(history.get("val_accuracy", [0]))), 4),
        "model_assets": specs,
        "int8_representative_images": len(representative_rows),
        "int8_representative_photo_ids": [r["photo_id"] for r in representative_rows],
        "split_protocol": json.loads((DATA / "split_protocol.json").read_text()),
        "data_version": args.data_version,
        "train_manifest": str(train_manifest or (DATA / "manifest_train.csv")),
        "train_manifest_sha256": hashlib.sha256(
            (train_manifest or (DATA / "manifest_train.csv")).read_bytes()).hexdigest()[:16],
        "claim_boundary": "pipeline proof only; M1 accuracy targets are NOT claimed",
    }
    (ARTIFACTS / "model_report.json").write_text(json.dumps(report, indent=2))

    print("\n=== model assets ===")
    for spec in specs:
        print(f"{spec['file']}: {spec['bytes'] / 1024:.1f} KiB")
        print(f"  input : {spec['input']}")
        print(f"  output: {spec['output']}")
    print(f"\nreport: {ARTIFACTS / 'model_report.json'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
