#!/usr/bin/env python3
"""Confidence-threshold calibration for the deployed FP32 model (FR4).

Implements docs/confidence_threshold_calibration_protocol.md on the validation split only.
Reads the per-image scores produced by the calibration harness (artifacts/conf/val_scores.json)
so the model is run through the production preprocessing exactly once per image.

Usage: flutter test test/confidence_calibration_harness_test.dart --dart-define=CONF_CALIBRATE=true
       python3 tools/calibrate_confidence_threshold.py
"""
from __future__ import annotations

import datetime, hashlib, json, pathlib, subprocess, sys

REPO = pathlib.Path(__file__).resolve().parents[1]
ARTIFACTS = REPO / "artifacts"
CONF = ARTIFACTS / "conf"
GRID = [round(0.01 * i, 2) for i in range(100)]
COVERAGE_FLOOR = 0.70


def main() -> int:
    payload = json.loads((CONF / "val_scores.json").read_text())
    rows = payload["rows"]
    n = len(rows)
    sweep = []
    for t in GRID:
        accepted = [r for r in rows if r["top1_score"] >= t]
        if not accepted:
            sweep.append({"threshold": t, "coverage": 0.0, "accepted_accuracy": None,
                          "accepted": 0, "rejected": n})
            continue
        correct = sum(1 for r in accepted if r["correct"])
        sweep.append({
            "threshold": t,
            "coverage": round(len(accepted) / n, 4),
            "accepted_accuracy": round(correct / len(accepted), 4),
            "accepted": len(accepted),
            "rejected": n - len(accepted),
        })

    feasible = [s for s in sweep if s["coverage"] >= COVERAGE_FLOOR
                and s["accepted_accuracy"] is not None]
    if feasible:
        best = max(feasible, key=lambda s: (s["accepted_accuracy"], s["coverage"], -s["threshold"]))
        chosen = best["threshold"]
        calibrated = True
    else:
        chosen, calibrated = 0.45, False
        best = {"accepted_accuracy": None, "coverage": None}

    model = REPO / "assets/models/fieldsnap_float.tflite"
    val_manifest = REPO / "data/manifest_val.csv"
    commit = subprocess.run(["git", "rev-parse", "HEAD"], cwd=REPO,
                            capture_output=True, text=True).stdout.strip()
    protocol = REPO / "docs/confidence_threshold_calibration_protocol.md"

    def sha(path: pathlib.Path) -> str:
        return hashlib.sha256(path.read_bytes()).hexdigest()

    reference = {s["threshold"]: s for s in sweep if s["threshold"] in (0.0, 0.45, chosen)}
    record = {
        "run_id": datetime.datetime.now().strftime("%Y%m%dT%H%M%S") + "-" + sha(model)[:8],
        "created_at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        "commit": commit,
        "protocol_sha256": sha(protocol),
        "model": {"path": str(model.relative_to(REPO)), "sha256": sha(model)},
        "validation_manifest": {"path": str(val_manifest.relative_to(REPO)),
                                "sha256": sha(val_manifest)},
        "validation_images": n,
        "selection_rule": {
            "coverage_floor": COVERAGE_FLOOR,
            "objective": "highest accepted accuracy among thresholds with coverage >= 0.70; ties "
                         "prefer higher coverage, then the lower threshold",
            "grid": "0.01 steps from 0.00 to 0.99",
        },
        "chosen_threshold": chosen,
        "chosen_point": best,
        "m1_target_met": bool(best["accepted_accuracy"] is not None
                              and best["accepted_accuracy"] >= 0.90),
        "reference_points": reference,
        "sweep": sweep,
        "calibrated": calibrated,
        "model_top1_val_accuracy": payload.get("overall_top1"),
    }
    (ARTIFACTS / "confidence_threshold_calibration.json").write_text(json.dumps(record, indent=2))

    print(f"validation images: {n}, model top-1: {payload.get('overall_top1')}")
    print(f"{'threshold':>10}{'coverage':>10}{'accepted acc':>14}{'accepted':>10}")
    for s in sweep:
        if s["threshold"] in (0.0, 0.2, 0.3, 0.4, 0.45, 0.5, 0.6, 0.7, chosen) or s["coverage"] >= 0.70 and s["accepted_accuracy"] and s["accepted_accuracy"] >= 0.85:
            acc = f"{s['accepted_accuracy']:.4f}" if s["accepted_accuracy"] is not None else "  n/a"
            print(f"{s['threshold']:>10.2f}{s['coverage']:>10.3f}{acc:>14}{s['accepted']:>10}")
    print(f"\nchosen threshold: {chosen} (coverage {best['coverage']}, "
          f"accepted accuracy {best['accepted_accuracy']})")
    print(f"M1 accepted-accuracy target (>= 0.90) met: {record['m1_target_met']}")
    print(f"CALIBRATED: {calibrated}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
