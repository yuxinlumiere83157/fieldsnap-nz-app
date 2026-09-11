#!/usr/bin/env python3
"""Verify the frozen split before any training: no leakage, right licences, test sealed.

Checks performed (all must pass):
  1. every image belongs to exactly one split;
  2. no observation id appears in more than one split (the anti-leakage rule);
  3. no md5 appears twice across the whole data set (de-duplication held);
  4. every licence is in the accepted set;
  5. every image file exists and matches its recorded byte size;
  6. the manifest hash still matches the frozen protocol (so the data did not change
     after the protocol was recorded);
  7. every image file's bytes still hash to the value recorded at download time (a same-size
     edit would otherwise pass unnoticed);
  8. the per-split CSVs are exactly the rows that `split.json` assigns to that split.
"""
from __future__ import annotations

import csv
import hashlib
import json
import pathlib
import sys
from collections import defaultdict

REPO = pathlib.Path(__file__).resolve().parents[1]
DATA = REPO / "data"
ACCEPTED = {"cc0", "cc-by"}


def main() -> int:
    failures: list[str] = []
    assignments = json.loads((DATA / "split.json").read_text())
    protocol = json.loads((DATA / "split_protocol.json").read_text())
    rows: dict[str, dict] = {}
    with open(DATA / "manifest.csv") as fh:
        for row in csv.DictReader(fh):
            rows[row["photo_id"]] = row

    print(f"images={len(rows)} split entries={len(assignments)}")
    if set(rows) != set(assignments):
        failures.append("split.json does not cover exactly the manifest's photo ids")

    observations: dict[str, set[str]] = defaultdict(set)
    md5_owner: dict[str, str] = {}
    split_counts: dict[str, int] = defaultdict(int)
    for photo_id, split in assignments.items():
        row = rows[photo_id]
        split_counts[split] += 1
        observations[row["observation_id"]].add(split)
        md5 = row["md5"]
        if md5 in md5_owner:
            failures.append(f"duplicate bytes: {photo_id} and {md5_owner[md5]}")
        md5_owner[md5] = photo_id
        if row["license_code"] not in ACCEPTED:
            failures.append(f"{photo_id}: licence {row['license_code']} not accepted")
        path = REPO / row["file_path"]
        if not path.exists():
            failures.append(f"{photo_id}: missing file {row['file_path']}")
        elif path.stat().st_size != int(row["bytes"]):
            failures.append(f"{photo_id}: size mismatch on disk")

    leaked = {obs: splits for obs, splits in observations.items() if len(splits) > 1}
    if leaked:
        failures.append(f"{len(leaked)} observations span more than one split")

    # 7. re-hash the bytes on disk and compare with the download-time record
    for photo_id, row in rows.items():
        path = REPO / row["file_path"]
        if not path.exists():
            continue
        actual = hashlib.md5(path.read_bytes()).hexdigest()
        if actual != row["md5"]:
            failures.append(f"{photo_id}: file content hash does not match the manifest")

    # 8. the split CSVs must agree with split.json exactly
    for split in ("train", "val", "test"):
        csv_path = DATA / f"manifest_{split}.csv"
        if not csv_path.exists():
            failures.append(f"{csv_path.name} is missing")
            continue
        with open(csv_path) as fh:
            csv_ids = [r["photo_id"] for r in csv.DictReader(fh)]
        expected_ids = {pid for pid, assigned in assignments.items() if assigned == split}
        if set(csv_ids) != expected_ids or len(csv_ids) != len(expected_ids):
            failures.append(
                f"{csv_path.name} does not match split.json "
                f"({len(csv_ids)} rows vs {len(expected_ids)} assigned)")
        # test observations must never appear in train/val
        if split in ("train", "val"):
            with open(csv_path) as fh:
                for r in csv.DictReader(fh):
                    if assignments.get(r["photo_id"]) == "test":
                        failures.append(f"{csv_path.name} contains a test-assigned photo")
                        break

    current_hash = hashlib.sha256((DATA / "manifest.csv").read_bytes()).hexdigest()
    if current_hash != protocol["manifest_sha256"]:
        failures.append("manifest changed after the protocol was frozen")

    print(f"per-split images: {dict(split_counts)}")
    print(f"observations: {len(observations)} (no observation in two splits: {not leaked})")
    print(f"licences: {sorted({r['license_code'] for r in rows.values()})}")
    print(f"manifest sha256 matches frozen protocol: "
          f"{current_hash == protocol['manifest_sha256']}")
    print(f"test split: {split_counts.get('test', 0)} images, status "
          f"'{protocol['test_split_status']}'")

    if failures:
        print("\nFAILURES:")
        for failure in failures[:20]:
            print(f"  - {failure}")
        return 1
    print("\nall split checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
