#!/usr/bin/env python3
"""Controlled comparison: small training set vs expanded training set.

Same architecture, same preprocessing spec, same validation split, same seed and the same
epoch budget. Only the training data changes, so a difference in results is attributable to the
data rather than to a simultaneous change of model or schedule.

Reads `data/manifest_train.csv` (or a versioned variant passed with --train-manifest) and
`data/manifest_val.csv`; the test split is never opened. Writes
`artifacts/comparison_<version>.json` plus a markdown summary.
"""
from __future__ import annotations

import argparse
import csv
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


def load_split(manifest: pathlib.Path, names: list[str]) -> tuple[list[str], np.ndarray]:
    paths, labels = [], []
    with open(manifest) as fh:
        for row in csv.DictReader(fh):
            paths.append(str(REPO / row["file_path"]))
            labels.append(names.index(row["class_slug"]))
    return paths, np.array(labels, dtype="int32")


def preprocess(path: str) -> np.ndarray:
    import tensorflow as tf

    raw = tf.io.read_file(path)
    image = tf.io.decode_image(raw, channels=3, expand_animations=False)
    image = tf.image.resize(image, (IMG_SIZE, IMG_SIZE), method="bilinear", antialias=True)
    image = tf.cast(image, tf.float32)
    return ((image - 127.5) / 127.5).numpy()


def dataset(paths, labels, training: bool):
    import tensorflow as tf

    ds = tf.data.Dataset.from_tensor_slices((paths, labels))
    if training:
        ds = ds.shuffle(len(paths), seed=20260911, reshuffle_each_iteration=True)

    def load(p, y):
        raw = tf.io.read_file(p)
        # decode_jpeg would fail on the handful of PNG/GIF files that iNaturalist serves for a
        # "photo" (and animated GIFs cannot be decoded at all). One animated GIF in the data set
        # is therefore skipped with a printed warning instead of aborting the run.
        try:
            image = tf.io.decode_image(raw, channels=3, expand_animations=False)
        except tf.errors.InvalidArgumentError as error:
            tf.print("skipping undecodable/animaged file:", p, error.message[:80])
            image = tf.zeros((IMG_SIZE, IMG_SIZE, 3), dtype=tf.uint8)
        image = tf.image.resize(image, (IMG_SIZE, IMG_SIZE), method="bilinear", antialias=True)
        return tf.cast(image, tf.float32), y

    def rescale(image, y):
        return (image - 127.5) / 127.5, y

    ds = ds.map(load, num_parallel_calls=tf.data.AUTOTUNE)
    if training:
        aug = tf.keras.Sequential([
            tf.keras.layers.RandomFlip("horizontal"),
            tf.keras.layers.RandomRotation(0.05),
            tf.keras.layers.RandomContrast(0.1, value_range=(0.0, 255.0)),
        ])
        ds = ds.map(lambda x, y: (aug(x, training=True), y),
                    num_parallel_calls=tf.data.AUTOTUNE)
    return ds.map(rescale, num_parallel_calls=tf.data.AUTOTUNE).batch(16).prefetch(
        tf.data.AUTOTUNE)


def build(num_classes: int):
    import tensorflow as tf
    from tensorflow.keras import layers

    tf.random.set_seed(20260911)
    base = tf.keras.applications.MobileNetV3Small(
        input_shape=(IMG_SIZE, IMG_SIZE, 3), include_top=False, weights="imagenet",
        include_preprocessing=False)
    base.trainable = False
    inputs = tf.keras.Input(shape=(IMG_SIZE, IMG_SIZE, 3))
    x = layers.GlobalAveragePooling2D()(base(inputs, training=False))
    x = layers.Dropout(0.2)(x)
    outputs = layers.Dense(num_classes, activation="softmax")(x)
    model = tf.keras.Model(inputs, outputs)
    model.compile(optimizer=tf.keras.optimizers.Adam(1e-3),
                  loss="sparse_categorical_crossentropy", metrics=["accuracy"])
    return model


def evaluate(model, paths, labels, names) -> dict:
    ds = dataset(paths, labels, training=False)
    probabilities = model.predict(ds, verbose=0)
    top1 = probabilities.argmax(axis=1)
    top3 = np.argsort(-probabilities, axis=1)[:, :3]
    confusion = np.zeros((len(names), len(names)), dtype=int)
    for truth, predicted in zip(labels, top1):
        confusion[truth, predicted] += 1
    per_class = {}
    for index, cls in enumerate(names):
        mask = labels == index
        if not mask.sum():
            continue
        tp = int(((top1 == index) & mask).sum())
        fp = int(((top1 == index) & ~mask).sum())
        fn = int(((top1 != index) & mask).sum())
        precision = tp / (tp + fp) if tp + fp else 0.0
        recall = tp / (tp + fn) if tp + fn else 0.0
        f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
        per_class[cls] = {"n": int(mask.sum()), "top1": round(recall, 4),
                          "precision": round(precision, 4), "f1": round(f1, 4)}
    return {
        "top1": round(float((top1 == labels).mean()), 4),
        "top3": round(float(np.mean([labels[i] in top3[i] for i in range(len(labels))])), 4),
        "macro_f1": round(float(np.mean([v["f1"] for v in per_class.values()])), 4),
        "per_class": per_class,
        "confusion": confusion.tolist(),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", default="expanded")
    parser.add_argument("--train-manifest", default="data/manifest_train.csv")
    parser.add_argument("--head-epochs", type=int, default=15)
    parser.add_argument("--fine-tune-epochs", type=int, default=3)
    parser.add_argument("--baseline", default=None,
                        help="path to a previous comparison json for the small-set results")
    args = parser.parse_args()

    train_manifest = REPO / args.train_manifest
    names = json.loads((DATA / "class_indices.json").read_text())["classes"]
    train_paths, train_labels = load_split(train_manifest, names)
    val_paths, val_labels = load_split(DATA / "manifest_val.csv", names)
    counts = {cls: int((train_labels == i).sum()) for i, cls in enumerate(names)}
    print(f"train={len(train_paths)} val={len(val_paths)} classes={len(names)} "
          f"(test split not opened)")
    print("train per class:", counts)

    import tensorflow as tf
    train_ds = dataset(train_paths, train_labels, training=True)
    val_ds = dataset(val_paths, val_labels, training=False)

    model = build(len(names))
    callbacks = [tf.keras.callbacks.EarlyStopping(monitor="val_accuracy", patience=5,
                                                 restore_best_weights=True)]
    head = model.fit(train_ds, validation_data=val_ds, epochs=args.head_epochs,
                     callbacks=callbacks, verbose=2)
    head_epochs = len(head.history["loss"])
    history = {k: [round(float(v), 4) for v in vals] for k, vals in head.history.items()}

    if args.fine_tune_epochs > 0:
        base = model.layers[1]
        base.trainable = True
        for layer in base.layers[:-20]:
            layer.trainable = False
        model.compile(optimizer=tf.keras.optimizers.Adam(1e-5),
                      loss="sparse_categorical_crossentropy", metrics=["accuracy"])
        before = [w.numpy().copy() for w in model.trainable_weights]
        steps_before = int(model.optimizer.iterations.numpy())
        fine = model.fit(train_ds, validation_data=val_ds, initial_epoch=head_epochs,
                         epochs=head_epochs + args.fine_tune_epochs,
                         callbacks=callbacks, verbose=2)
        for key, vals in fine.history.items():
            history.setdefault(key, []).extend([round(float(v), 4) for v in vals])
        steps_after = int(model.optimizer.iterations.numpy())
        delta = max(float(np.abs(a - b).max()) for a, b in
                    zip(before, [w.numpy() for w in model.trainable_weights]))
        print(f"fine-tune epochs={len(fine.history['loss'])} steps={steps_after - steps_before} "
              f"weight delta={delta:.2e}")
        if not fine.history["loss"] or steps_after == steps_before:
            raise RuntimeError("fine-tuning did not run")

    metrics = evaluate(model, val_paths, val_labels, names)
    model_path = ARTIFACTS / f"comparison_{args.version}.keras"
    model.save(model_path)
    payload = {
        "version": args.version,
        "created_at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        "train_manifest": str(train_manifest.relative_to(REPO)),
        "train_manifest_sha256": hashlib.sha256(train_manifest.read_bytes()).hexdigest()[:16],
        "val_manifest_sha256": hashlib.sha256(
            (DATA / "manifest_val.csv").read_bytes()).hexdigest()[:16],
        "train_images": len(train_paths),
        "val_images": len(val_paths),
        "train_per_class": counts,
        "head_epochs": head_epochs,
        "fine_tune_epochs": args.fine_tune_epochs,
        "history": history,
        "validation": metrics,
        "test_split_read": False,
    }
    (ARTIFACTS / f"comparison_{args.version}.json").write_text(
        json.dumps(payload, indent=2, sort_keys=True))

    print(f"\n=== {args.version}: validation top1={metrics['top1']} top3={metrics['top3']} "
          f"macro-F1={metrics['macro_f1']}")
    worst = sorted(metrics["per_class"].items(), key=lambda kv: kv[1]["f1"])[:5]
    print("worst classes by F1:", ", ".join(f"{k}={v['f1']}" for k, v in worst))
    print(f"wrote artifacts/comparison_{args.version}.json")

    if args.baseline:
        base_payload = json.loads((REPO / args.baseline).read_text())
        print(f"\n=== comparison vs {args.baseline}")
        for key in ("top1", "top3", "macro_f1"):
            before = base_payload["validation"][key]
            after = metrics[key]
            print(f"  {key:9} {before} -> {after}  ({after - before:+.3f})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
