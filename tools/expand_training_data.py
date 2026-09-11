#!/usr/bin/env python3
"""1D step 1 — enlarge the TRAINING split only, as a new data version.

Rules (from the project owner's decision, 2026-09-11):
  * validation and test keep their existing observations and assignments;
  * new images must come from observations not already used anywhere, so nothing can leak
    between splits;
  * new images must not duplicate existing bytes (md5) or existing photo ids;
  * the existing frozen protocol is never re-randomised (`make_split.py --force` is not used).

The script appends to `data/manifest_extra.csv` and leaves `manifest.csv`, `split.json` and
`split_protocol.json` untouched. `tools/apply_expansion.py` then builds the versioned
training manifest for the comparison experiment.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import fetch_dataset as fd  # noqa: E402  (reuse the fetch/parse/download helpers)

REPO = fd.REPO
DATA = fd.DATA
EXTRA = DATA / "manifest_extra.csv"


def load_manifest(path: pathlib.Path) -> list[dict]:
    if not path.exists():
        return []
    with open(path) as fh:
        return list(csv.DictReader(fh))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target-per-class", type=int, default=150,
                        help="desired TOTAL training images per class")
    parser.add_argument("--per-page", type=int, default=30)
    parser.add_argument("--download-workers", type=int, default=4)
    args = parser.parse_args()

    existing = load_manifest(DATA / "manifest.csv") + load_manifest(EXTRA)
    used_photos = {r["photo_id"] for r in existing}
    used_observations = {r["observation_id"] for r in existing}
    # every observation that is currently in validation or test must stay out of training
    split = json.loads((DATA / "split.json").read_text())
    held_out = {
        r["observation_id"] for r in existing if split.get(r["photo_id"]) in ("val", "test")
    }
    existing_train: dict[str, int] = {}
    for r in existing:
        if split.get(r["photo_id"]) == "train" or r.get("split") == "train":
            existing_train[r["class_slug"]] = existing_train.get(r["class_slug"], 0) + 1
    extra_train: dict[str, int] = {}
    for r in load_manifest(EXTRA):
        extra_train[r["class_slug"]] = extra_train.get(r["class_slug"], 0) + 1

    print(f"held-out observations that must not be reused: {len(held_out)}")
    print(f"{'class':20} {'train now':>9} {'target':>7} {'to fetch':>9}")

    fd.CACHE.mkdir(parents=True, exist_ok=True)
    fd.RAW.mkdir(parents=True, exist_ok=True)

    new_rows: list[dict] = []
    for slug, (group, display, names) in fd.CLASSES.items():
        have = existing_train.get(slug, 0) + extra_train.get(slug, 0)
        need = max(0, args.target_per_class - have)
        print(f"{slug:20} {have:>9} {args.target_per_class:>7} {need:>9}")
        if need == 0:
            continue
        # ask for more than needed: some candidates will be filtered out as duplicates
        candidates = fd.fetch_class(
            slug, need * 2, args.per_page, offline=False,
            exclude_photo_ids=used_photos,
            exclude_observation_ids=used_observations | held_out,
        )
        fresh = [
            row for row in candidates
            if row["photo_id"] not in used_photos
            and row["observation_id"] not in used_observations
            and row["observation_id"] not in held_out
        ]
        print(f"  candidates={len(candidates)} usable={len(fresh)}")
        kept = fd.download_rows(fresh[:need], offline=False, workers=args.download_workers)
        for row in kept:
            row["split"] = "train"
            used_photos.add(row["photo_id"])
            used_observations.add(row["observation_id"])
        new_rows.extend(kept)

    fields = list(fd.MANIFEST_FIELDS) + ["split"]
    with open(EXTRA, "w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(new_rows)

    per_class: dict[str, int] = {}
    per_class_obs: dict[str, set[str]] = {}
    for row in new_rows:
        per_class[row["class_slug"]] = per_class.get(row["class_slug"], 0) + 1
        per_class_obs.setdefault(row["class_slug"], set()).add(row["observation_id"])
    print("")
    print(f"new training images: {len(new_rows)}")
    print(f"appended to {EXTRA.relative_to(REPO)}")
    print(f"new observations used: {len({r['observation_id'] for r in new_rows})}")
    print("per-class new images / new observations:")
    for slug in fd.CLASSES:
        print(f"  {slug:20} {per_class.get(slug, 0):>3} / {len(per_class_obs.get(slug, set())):>3}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
