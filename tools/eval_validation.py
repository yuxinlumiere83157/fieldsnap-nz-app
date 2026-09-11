#!/usr/bin/env python3
"""1B step 2 — check both exported TFLite models on the validation split only.

This runs the same Keras preprocessing the app will have to reproduce, so it also
acts as the reference for the Flutter side. It writes `artifacts/reference_io.json`
with one input tensor and both models' outputs for that tensor; tools/reference_io.py
turns that into files the Dart test can replay.

The test split is never opened here.
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import pathlib
import sys

import numpy as np

REPO = pathlib.Path(__file__).resolve().parents[1]
DATA = REPO / "data"
ARTIFACTS = REPO / "artifacts"
IMG_SIZE = 224


def load_val() -> tuple[list[str], np.ndarray, list[str]]:
    import csv

    names = json.loads((DATA / "class_indices.json").read_text())["classes"]
    index = {n: i for i, n in enumerate(names)}
    paths, labels = [], []
    with open(DATA / "manifest_val.csv") as fh:
        for row in csv.DictReader(fh):
            paths.append(str(REPO / row["file_path"]))
            labels.append(index[row["class_slug"]])
    return paths, np.array(labels), names


def preprocess(path: str, size: int) -> np.ndarray:
    """Training-time pipeline: decode -> tf.image.resize(bilinear) -> (x-127.5)/127.5.

    The Flutter preprocessor uses the `image` package's resize, which is a different
    resampling implementation; `test/integration/tflite_cross_check_test.dart` quantifies
    how far apart the two are on a single reference image rather than assuming they agree.
    """
    import tensorflow as tf

    raw = tf.io.read_file(path)
    image = tf.io.decode_image(raw, channels=3, expand_animations=False)
    # antialias=True matches the training pipeline and the spec (docs/preprocessing_spec.md);
    # without it Python evaluation used a different filter from training, which added an
    # unexplained gap between the training curve and the exported-model numbers.
    image = tf.image.resize(image, (size, size), method="bilinear", antialias=True)
    image = tf.cast(image, tf.float32)
    return ((image - 127.5) / 127.5).numpy()


def run_model(path: pathlib.Path, inputs: np.ndarray) -> np.ndarray:
    """Run one image at a time through a TFLite model.

    `np.ascontiguousarray` matters: the earlier revision passed a slice view
    (`raw[i:i+1]`) straight to `set_tensor`, and that produced a *wrong* reference vector
    (it disagreed with both the Keras model and the Dart runtime by 0.237 on the reference
    image). Every input is now materialised as a contiguous array before inference.
    """
    import tensorflow as tf

    interpreter = tf.lite.Interpreter(model_path=str(path))
    interpreter.allocate_tensors()
    input_detail = interpreter.get_input_details()[0]
    output_detail = interpreter.get_output_details()[0]
    outputs = []
    for image in inputs:
        tensor = np.ascontiguousarray(image[None, ...]).astype(input_detail["dtype"])
        interpreter.set_tensor(input_detail["index"], tensor)
        interpreter.invoke()
        outputs.append(interpreter.get_tensor(output_detail["index"])[0])
    return np.stack(outputs)


def _keras_predictions(artifacts: pathlib.Path, inputs: np.ndarray):
    """Keras as the third opinion, or an explicit "not available".

    Returns (predictions, status). It never fabricates a reference: an earlier revision
    returned a zero array when the checkpoint was missing, which made the comparison
    meaningless instead of reporting that it could not run.
    """
    import tensorflow as tf

    keras_path = artifacts / "fieldsnap_mobilenetv3s.keras"
    if not keras_path.exists():
        return None, "not-run: no Keras checkpoint at artifacts/fieldsnap_mobilenetv3s.keras"
    model = tf.keras.models.load_model(keras_path)
    return model.predict(np.ascontiguousarray(inputs), verbose=0), "run"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sample", type=int, default=0,
                        help="index in the validation split used for the reference I/O")
    args = parser.parse_args()

    run_id = f"{datetime.datetime.now().strftime('%Y%m%dT%H%M%S')}-{os.getpid()}"
    data_version = None
    protocol_path = DATA / "split_protocol.json"
    if protocol_path.exists():
        data_version = json.loads(protocol_path.read_text()).get("data_version")

    def model_hash(path: pathlib.Path) -> str:
        return hashlib.sha256(path.read_bytes()).hexdigest()[:16] if path.exists() else "missing"

    paths, labels, names = load_val()
    print(f"run {run_id}: validation images {len(paths)} across {len(names)} classes "
          f"(test split not opened)")

    raw = np.stack([preprocess(p, IMG_SIZE) for p in paths])
    results: dict[str, dict] = {}
    for name in ("fieldsnap_float.tflite", "fieldsnap_int8.tflite"):
        path = ARTIFACTS / name
        if not path.exists():
            print(f"missing {path}")
            return 2
        probabilities = run_model(path, raw)
        top1 = probabilities.argmax(axis=1)
        accuracy = float((top1 == labels).mean())
        top3 = np.argsort(-probabilities, axis=1)[:, :3]
        top3_accuracy = float(np.mean([labels[i] in top3[i] for i in range(len(labels))]))
        per_class = {}
        for index, cls in enumerate(names):
            mask = labels == index
            if mask.sum():
                per_class[cls] = {
                    "n": int(mask.sum()),
                    "top1": round(float((top1[mask] == labels[mask]).mean()), 4),
                }
        results[name] = {
            "top1_val_accuracy": round(accuracy, 4),
            "top3_val_accuracy": round(top3_accuracy, 4),
            "per_class_top1": per_class,
        }
        print(f"{name}: top1={accuracy:.3f} top3={top3_accuracy:.3f}")

    reference = {
        "run_id": run_id,
        "model_sha256_prefix": {
            name: model_hash(ARTIFACTS / name)
            for name in ("fieldsnap_float.tflite", "fieldsnap_int8.tflite")},
        "note": "input tensor is float32 RGB in [-1,1]; (x-127.5)/127.5 applied once",
        "image_path": paths[args.sample],
        "class_slug": names[labels[args.sample]],
        "class_index": int(labels[args.sample]),
        "input_shape": list(raw[args.sample].shape),
        "input_tensor": raw[args.sample].tolist(),
        "outputs": {},
    }
    # A strict Keras cross-check applies to the FP32 conversion only. The INT8 model is
    # *expected* to differ from Keras: that difference is the quantisation cost, and treating
    # it as an error would abort a legitimate run (and leave the previous results on disk).
    records: dict[str, dict] = {}
    for name in ("fieldsnap_float.tflite", "fieldsnap_int8.tflite"):
        probabilities = run_model(ARTIFACTS / name, raw[args.sample:args.sample + 1])[0]
        keras_probabilities, keras_status = _keras_predictions(
            ARTIFACTS, raw[args.sample:args.sample + 1])
        record = {"keras_cross_check": keras_status}
        if keras_probabilities is not None:
            delta = float(np.abs(probabilities - keras_probabilities[0]).max())
            record["keras_max_delta"] = round(delta, 6)
            record["keras_delta_kind"] = "quantisation cost" if "int8" in name else "conversion fidelity"
            if name.endswith("float.tflite") and delta > 5e-3:
                # Anything written now would be untrustworthy, so write nothing.
                print(f"REFUSING to write results: the float conversion disagrees with Keras "
                      f"by {delta:.4f}", file=sys.stderr)
                return 3
        public = {k: v for k, v in record.items() if k != "keras_cross_check"}
        results[name].update(public)
        top = int(probabilities.argmax())
        reference["outputs"][name] = {
            "argmax_index": top,
            "argmax_class": names[top],
            "probabilities": [round(float(value), 6) for value in probabilities],
            "top_probability": float(probabilities.max()),
            "keras_cross_check": keras_status,
            "keras_max_delta": record.get("keras_max_delta"),
        }
        results[name]["keras_cross_check"] = keras_status
        print(f"  {name}: keras cross-check {keras_status}"
              + (f", max delta {record['keras_max_delta']:.2e} "
                 f"({record['keras_delta_kind']})" if keras_probabilities is not None else ""))

    (ARTIFACTS / "reference_io.json").write_text(json.dumps(reference))
    summary = {
        "run_id": run_id,
        "finished_at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        "data_version": data_version,
        "split_protocol_sha256": (
            hashlib.sha256(protocol_path.read_bytes()).hexdigest()[:16]
            if protocol_path.exists() else None),
        "manifest_sha256": (
            hashlib.sha256((DATA / "manifest.csv").read_bytes()).hexdigest()[:16]
            if (DATA / "manifest.csv").exists() else None),
        "model_sha256_prefix": {
            name: model_hash(ARTIFACTS / name)
            for name in ("fieldsnap_float.tflite", "fieldsnap_int8.tflite")},
        "classes": names,
        "validation_images": len(paths),
        "test_split_read": False,
        "models": results,
    }
    (ARTIFACTS / "validation_results.json").write_text(json.dumps(summary, indent=2, sort_keys=True))
    print(f"\nwrote {ARTIFACTS / 'validation_results.json'} and {ARTIFACTS / 'reference_io.json'}")
    print("Reminder: these are validation numbers from a small sample, not M1's "
          "held-out test-set targets.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
