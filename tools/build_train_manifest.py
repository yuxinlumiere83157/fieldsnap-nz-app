#!/usr/bin/env python3
"""Build versioned training manifests with a hard leakage guard.

Why this exists: the first expansion run produced three extra photos whose observation was
already used by validation or test (the exclusion set did not catch them; the cause is still
unconfirmed — the fetch may have come from a cached API response written before the exclusion
was wired in). Rather than trusting the fetch-time filter, this script re-derives the training
manifest and **drops** any row that shares an observation with validation or test, printing what
it dropped. The validation and test manifests are never rewritten.

Outputs:
  * `data/manifest_train_v1.csv`          — the original 1A training rows
  * `data/manifest_train_expanded_v2.csv` — those plus the clean extra rows
"""
from __future__ import annotations

import csv
import hashlib
import json
import pathlib
import sys

REPO = pathlib.Path(__file__).resolve().parents[1]
DATA = REPO / "data"


def main() -> int:
    split = json.loads((DATA / "split.json").read_text())
    base = list(csv.DictReader(open(DATA / "manifest.csv")))
    extra_path = DATA / "manifest_extra.csv"
    extra = list(csv.DictReader(open(extra_path))) if extra_path.exists() else []

    held_out = {
        r["observation_id"] for r in base if split.get(r["photo_id"]) in ("val", "test")
    }
    base_train = [r for r in base if split.get(r["photo_id"]) == "train"]
    base_train_obs = {r["observation_id"] for r in base_train}
    base_train_photos = {r["photo_id"] for r in base_train}

    clean, dropped = [], []
    seen_photos = set(base_train_photos)
    for row in extra:
        if row["observation_id"] in held_out:
            dropped.append((row, "shares an observation with validation or test"))
            continue
        if row["observation_id"] in base_train_obs:
            # same observation as an existing training row: allowed (no leakage), but flag it
            pass
        if row["photo_id"] in seen_photos:
            dropped.append((row, "duplicate photo id"))
            continue
        seen_photos.add(row["photo_id"])
        clean.append(row)

    print(f"base training rows       : {len(base_train)}")
    print(f"extra rows               : {len(extra)}")
    print(f"extra rows dropped       : {len(dropped)}")
    for row, why in dropped:
        print(f"  - {row['class_slug']:18} photo {row['photo_id']:>11} obs {row['observation_id']:>11}  {why}")

    # Never publish location columns, even if an older local manifest still has them.
    location_columns = {"latitude", "longitude", "place_guess"}
    fields = [f for f in base[0].keys() if f not in location_columns]
    if "split" not in fields:
        fields.append("split")

    def write(path: pathlib.Path, rows: list[dict]) -> str:
        with open(path, "w", newline="") as fh:
            writer = csv.DictWriter(fh, fieldnames=fields, extrasaction="ignore")
            writer.writeheader()
            for row in rows:
                writer.writerow({**row, "split": "train"})
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        print(f"wrote {path.relative_to(REPO)}: {len(rows)} rows, sha256 {digest[:16]}…")
        return digest

    v1_hash = write(DATA / "manifest_train_v1.csv", base_train)
    v2_hash = write(DATA / "manifest_train_expanded_v2.csv", base_train + clean)

    # Guard the guard: no training observation may appear in the held-out sets.
    for name, rows in (("v1", base_train), ("v2", base_train + clean)):
        overlap = {r["observation_id"] for r in rows} & held_out
        if overlap:
            print(f"FATAL: {name} still overlaps held-out observations: {sorted(overlap)[:5]}",
                  file=sys.stderr)
            return 3
    print("leakage guard passed for both versions")

    record = {
        "data_version": 2,
        "created_at": "2026-09-11",
        "purpose": "controlled comparison: training set only; validation and test untouched",
        "base_train_images": len(base_train),
        "added_train_images": len(clean),
        "dropped_extra_images": len(dropped),
        "total_train_images": len(base_train) + len(clean),
        "held_out_observations_respected": len(held_out),
        "train_manifest_v1": {"path": "data/manifest_train_v1.csv", "sha256": v1_hash},
        "train_manifest_v2": {
            "path": "data/manifest_train_expanded_v2.csv", "sha256": v2_hash},
        "val_manifest": "data/manifest_val.csv (unchanged)",
        "test_manifest": "data/manifest_test.csv (unchanged, still sealed)",
        "dropped_detail": [
            {"photo_id": row["photo_id"], "observation_id": row["observation_id"],
             "class_slug": row["class_slug"], "reason": why}
            for row, why in dropped
        ],
        "note": "the fetch-time exclusion did not catch these rows, so the guard is re-applied "
                "here and any drop is printed rather than silently accepted",
    }
    (DATA / "data_version_2.json").write_text(json.dumps(record, indent=2))
    print("wrote data/data_version_2.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
