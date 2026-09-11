#!/usr/bin/env python3
"""Quality-gate calibration and one-shot verification (FR2).

Implements the pre-registered protocol in docs/quality_gate_calibration_protocol.md exactly: the
validation split is divided by observation id into a calibration subset and a verification subset,
deterministic conditions are generated from the accepted images, the thresholds are chosen by the
pre-registered rule, and the chosen values are applied **once** to the verification subset.

The sealed classifier test split is not touched, and the classifier is not involved.

Usage:
  python3 tools/calibrate_quality_gate.py            # stage 1: prepare images -> artifacts/qg/
  python3 tools/calibrate_quality_gate.py --finalise # stage 2: run in the Dart harness, then this
                                                     # script reads its output and freezes values
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import pathlib
import random
import sys

REPO = pathlib.Path(__file__).resolve().parents[1]
DATA = REPO / "data"
ARTIFACTS = REPO / "artifacts"
STAGE = ARTIFACTS / "qg"

SEED = 20260911
BLUR_SIGMA = 6.0
DARK_SCALE = 0.10
BRIGHT_SCALE = 2.5  # amendment 1: 1.6 never reached the ceiling


def split_by_observation() -> tuple[list[dict], list[dict]]:
    """50/50 by observation id, deterministic."""
    rows = list(csv.DictReader(open(DATA / "manifest_val.csv")))
    by_obs: dict[str, list[dict]] = {}
    for row in rows:
        by_obs.setdefault(row["observation_id"], []).append(row)
    observations = sorted(by_obs)
    rng = random.Random(SEED)
    rng.shuffle(observations)
    half = len(observations) // 2
    calib_obs, verify_obs = set(observations[:half]), set(observations[half:])
    calib = [r for o in calib_obs for r in by_obs[o]]
    verify = [r for o in verify_obs for r in by_obs[o]]
    return calib, verify


def box_blur(image, sigma: float):
    """Separable box blur, repeated three times: a standard Gaussian approximation."""
    from PIL import Image, ImageFilter

    radius = max(1, int(round(sigma)))
    out = image
    for _ in range(3):
        out = out.filter(ImageFilter.BoxBlur(radius))
    return out


def scale_luma(image, factor: float):
    """Multiply luma, clipping: a deterministic brightness change."""
    from PIL import Image

    if image.mode != "RGB":
        image = image.convert("RGB")
    channels = image.split()
    out = [ch.point(lambda v, f=factor: min(255, int(v * f))) for ch in channels]
    return Image.merge("RGB", out)


def stage_prepare() -> int:
    from PIL import Image

    calib, verify = split_by_observation()
    STAGE.mkdir(parents=True, exist_ok=True)
    conditions = {"bright": None, "dark": DARK_SCALE, "overexposed": BRIGHT_SCALE, "blurred": "blur"}
    manifest = {"calibration": [], "verification": []}

    for subset_name, rows in (("calibration", calib), ("verification", verify)):
        for condition, transform in conditions.items():
            directory = STAGE / subset_name / condition
            directory.mkdir(parents=True, exist_ok=True)
            for row in rows:
                source = REPO / row["file_path"]
                with Image.open(source) as image:
                    rgb = image.convert("RGB")
                    if transform == "blur":
                        small = box_blur(rgb, BLUR_SIGMA)
                        small = small.resize(
                            (max(1, rgb.width // 4), max(1, rgb.height // 4)),
                            Image.Resampling.BILINEAR,
                        )
                        result = small
                    elif transform is None:
                        result = rgb
                    else:
                        result = scale_luma(rgb, float(transform))
                    target = directory / f"{row['photo_id']}.jpg"
                    result.save(target, quality=92)
                manifest[subset_name].append({
                    "photo_id": row["photo_id"],
                    "observation_id": row["observation_id"],
                    "class_slug": row["class_slug"],
                    "condition": condition,
                    "expected": "acceptable" if condition == "bright" else "reject",
                    "path": str(target.relative_to(REPO)),
                })

    (STAGE / "manifest.json").write_text(json.dumps(manifest, indent=2))
    print(f"calibration subset: {len(calib)} images x 4 conditions = {len(manifest['calibration'])}")
    print(f"verification subset: {len(verify)} images x 4 conditions = {len(manifest['verification'])}")
    digest = hashlib.sha256((STAGE / "manifest.json").read_bytes()).hexdigest()
    print(f"stage manifest sha256: {digest[:16]}…")
    print(f"images written under {STAGE.relative_to(REPO)}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stage", choices=["prepare"], default="prepare")
    args = parser.parse_args()
    if args.stage == "prepare":
        return stage_prepare()
    return 1


if __name__ == "__main__":
    sys.exit(main())
