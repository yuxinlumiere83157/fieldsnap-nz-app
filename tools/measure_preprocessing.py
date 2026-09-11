#!/usr/bin/env python3
"""Quantify how much the resize implementation shifts model outputs.

The app resizes with the Dart `image` package (area/average resampling); the Python
reference resizes with `tf.image.resize(antialias=True)`. Both antialias, but the
implementations differ, so the tensor, and therefore the probabilities, differ slightly.
Instead of guessing a tolerance, this script measures the effect on real validation
images and writes `artifacts/preprocessing_report.json`.

It runs in two stages because the Python environments differ on this machine (one has
TensorFlow, the other has Pillow); `--stage pixels` writes the two resized pixel sets and
`--stage compare` runs the model over them. Validation split only; the test split stays
sealed.
"""
from __future__ import annotations

import argparse
import csv
import json
import pathlib

import numpy as np

REPO = pathlib.Path(__file__).resolve().parents[1]
DATA = REPO / "data"
ARTIFACTS = REPO / "artifacts"
TMP = pathlib.Path("/tmp/fieldsnap_preproc")
SIZE = 224
SAMPLE = 40


def sample_rows() -> list[dict]:
    rows = list(csv.DictReader(open(DATA / "manifest_val.csv")))
    step = max(1, len(rows) // SAMPLE)
    return rows[::step][:SAMPLE]


def stage_pixels() -> int:
    """TensorFlow resize + Pillow box resize for each sampled image."""
    import tensorflow as tf
    from PIL import Image

    TMP.mkdir(parents=True, exist_ok=True)
    rows = sample_rows()
    tf_batch, box_batch = [], []
    for row in rows:
        path = str(REPO / row["file_path"])
        raw = tf.io.read_file(path)
        decoded = tf.io.decode_image(raw, channels=3, expand_animations=False)
        tf_resized = tf.image.resize(
            tf.cast(decoded, tf.float32), (SIZE, SIZE), method="bilinear", antialias=True
        ).numpy()
        with Image.open(path) as image:
            rgb = image.convert("RGB")
            # BOX averages the source pixels that fall into each destination pixel:
            # the classic area filter, and the closest match to the Dart `image`
            # package's `Interpolation.average`.
            box_resized = np.asarray(
                rgb.resize((SIZE, SIZE), Image.Resampling.BOX), dtype="float32"
            )
        tf_batch.append(tf_resized)
        box_batch.append(box_resized)
    np.save(TMP / "tf.npy", np.stack(tf_batch))
    np.save(TMP / "box.npy", np.stack(box_batch))
    (TMP / "paths.json").write_text(json.dumps([r["file_path"] for r in rows]))
    print(f"wrote {len(rows)} resized images for both filters to {TMP}")
    return 0


def stage_compare() -> int:
    import tensorflow as tf

    tf_batch = np.load(TMP / "tf.npy") / 127.5 - 1.0
    box_batch = np.load(TMP / "box.npy") / 127.5 - 1.0
    interpreter = tf.lite.Interpreter(model_path=str(ARTIFACTS / "fieldsnap_float.tflite"))
    interpreter.allocate_tensors()
    detail = interpreter.get_input_details()[0]
    output = interpreter.get_output_details()[0]

    def run(tensor: np.ndarray) -> np.ndarray:
        interpreter.set_tensor(detail["index"], tensor[None, ...].astype("float32"))
        interpreter.invoke()
        return interpreter.get_tensor(output["index"])[0]

    differences, top1, top3 = [], 0, 0
    for a_pixels, b_pixels in zip(tf_batch, box_batch):
        a = run(a_pixels)
        b = run(b_pixels)
        differences.append(float(np.abs(a - b).max()))
        order_a, order_b = np.argsort(-a)[:3], np.argsort(-b)[:3]
        top1 += int(order_a[0] == order_b[0])
        top3 += int(set(order_a.tolist()) == set(order_b.tolist()))

    report = {
        "images": len(differences),
        "resize_tf": "tf.image.resize(bilinear, antialias=True)",
        "resize_box": "Pillow BOX (area) filter, standing in for the app's Dart resize",
        "max_probability_difference": round(float(np.max(differences)), 4),
        "mean_probability_difference": round(float(np.mean(differences)), 4),
        "top1_agreement": round(top1 / len(differences), 4),
        "top3_set_agreement": round(top3 / len(differences), 4),
        "note": "validation images only; the app's real resize is checked by "
                "test/integration/tflite_cross_check_test.dart",
    }
    (ARTIFACTS / "preprocessing_report.json").write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stage", choices=["pixels", "compare"], required=True)
    args = parser.parse_args()
    return stage_pixels() if args.stage == "pixels" else stage_compare()


if __name__ == "__main__":
    raise SystemExit(main())
