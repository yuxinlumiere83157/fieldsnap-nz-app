#!/usr/bin/env python3
"""1A step 2 — freeze an observation-grouped train/validation/test split.

Why group by observation: iNaturalist observations often carry several near-identical
frames of the same individual. Splitting per photo would put near-duplicates on both
sides of the train/test boundary and inflate measured accuracy. Every image from one
observation therefore lands in exactly one split.

The test split is written once and then treated as sealed: it must not be read during
training, threshold selection or debugging. The protocol (sizes, ratios, seed, policy
and the hash of the manifest it was derived from) is written to
`data/split_protocol.json` *before* any model code runs, so the evaluation protocol
cannot be adjusted after seeing results.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import pathlib
import random
import sys
from collections import defaultdict

REPO = pathlib.Path(__file__).resolve().parents[1]  # tools/ -> repository root
DATA = REPO / "data"
MANIFEST = DATA / "manifest.csv"
LICENCES = ("cc0", "cc-by")


def sha256_file(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=int, default=20260911)
    parser.add_argument("--train", type=float, default=0.70)
    parser.add_argument("--val", type=float, default=0.15)
    parser.add_argument("--test", type=float, default=0.15)
    parser.add_argument("--dry-run", action="store_true",
                        help="report the split without writing the protocol file")
    parser.add_argument("--force", action="store_true",
                        help="overwrite an existing frozen protocol (creates a new version "
                             "record and is never implicit)")
    parser.add_argument("--version", type=int, default=1,
                        help="data version label for an explicitly re-frozen split")
    args = parser.parse_args()

    if abs((args.train + args.val + args.test) - 1.0) > 1e-9:
        print("ratios must sum to 1.0", file=sys.stderr)
        return 2
    if not MANIFEST.exists():
        print(f"missing {MANIFEST}; run tools/fetch_dataset.py first", file=sys.stderr)
        return 2

    protocol_path = DATA / "split_protocol.json"
    rows = list(csv.DictReader(open(MANIFEST)))
    for row in rows:
        row["observation_id"] = row["observation_id"].strip()

    # policy guard: refuse to split anything that is not under the accepted licences
    bad = sorted({r["license_code"] for r in rows if r["license_code"] not in LICENCES})
    if bad:
        print(f"refusing to split: unexpected licences present: {bad}", file=sys.stderr)
        return 3

    by_class: dict[str, dict[str, list[dict]]] = defaultdict(lambda: defaultdict(list))
    for row in rows:
        by_class[row["class_slug"]][row["observation_id"]].append(row)

    rng = random.Random(args.seed)
    assignment: dict[str, str] = {}          # photo_id -> split
    class_counts: dict[str, dict[str, int]] = {}

    for slug in sorted(by_class):
        observations = sorted(by_class[slug])
        rng.shuffle(observations)
        n_obs = len(observations)
        n_val = max(1, round(n_obs * args.val))
        n_test = max(1, round(n_obs * args.test))
        if n_val + n_test >= n_obs:
            n_val = max(1, n_obs // 4)
            n_test = max(1, n_obs // 4)
        val = observations[:n_val]
        test = observations[n_val:n_val + n_test]
        train = observations[n_val + n_test:]
        counts = {"train": 0, "val": 0, "test": 0, "observations": n_obs}
        for split, obs_ids in (("train", train), ("val", val), ("test", test)):
            for obs_id in obs_ids:
                for row in by_class[slug][obs_id]:
                    assignment[row["photo_id"]] = split
                    counts[split] += 1
        class_counts[slug] = counts

    protocol = {
        "frozen_at": None,  # filled after writing, see below
        "seed": args.seed,
        "ratios": {"train": args.train, "val": args.val, "test": args.test},
        "grouping": "observation",
        "licence_policy": list(LICENCES),
        "manifest_sha256": sha256_file(MANIFEST),
        "images": len(rows),
        "observations": len({r["observation_id"] for r in rows}),
        "classes": len(by_class),
        "per_class": class_counts,
        "test_split_status": "sealed - not to be read until the final evaluation",
        "data_version": args.version,
        "supersedes": (
            json.loads(protocol_path.read_text()).get("frozen_at")
            if protocol_path.exists() else None
        ),
    }

    print(f"images={len(rows)} observations={protocol['observations']} classes={len(by_class)}")
    print(f"{'class':20} {'train':>6} {'val':>5} {'test':>5} {'obs':>5}")
    for slug in sorted(class_counts):
        c = class_counts[slug]
        print(f"{slug:20} {c['train']:>6} {c['val']:>5} {c['test']:>5} {c['observations']:>5}")

    if args.dry_run:
        print("\ndry run: nothing written")
        return 0

    # A frozen protocol must not be silently replaced: re-running the fetch after adding
    # data would otherwise reshuffle the existing validation/test observations and quietly
    # invalidate earlier results. Re-freezing is allowed, but only explicitly.
    if protocol_path.exists() and not args.force:
        previous = json.loads(protocol_path.read_text())
        print("\nREFUSING TO OVERWRITE the frozen split protocol at "
              f"{protocol_path.relative_to(REPO)}")
        print(f"  frozen_at      : {previous.get('frozen_at')}")
        print(f"  images         : {previous.get('images')}")
        print(f"  manifest hash  : {str(previous.get('manifest_sha256'))[:16]}…")
        print(f"  current hash   : {protocol['manifest_sha256'][:16]}…")
        print("  If the data set really changed and you intend a new data version, re-run with")
        print("  --force --version N and record the reason in docs/progress.md. Existing test")
        print("  observations must never move into train or validation.")
        return 4

    import datetime
    protocol["frozen_at"] = datetime.datetime.now().astimezone().isoformat(timespec="seconds")

    (DATA / "split.json").write_text(json.dumps(assignment, indent=1, sort_keys=True))
    protocol_path.write_text(json.dumps(protocol, indent=2, sort_keys=True))
    for split in ("train", "val", "test"):
        with open(DATA / f"manifest_{split}.csv", "w", newline="") as fh:
            writer = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
            writer.writeheader()
            for row in rows:
                if assignment.get(row["photo_id"]) == split:
                    writer.writerow(row)
    print(f"\nwrote split.json, split_protocol.json, manifest_{{train,val,test}}.csv")
    print(f"manifest_sha256={protocol['manifest_sha256'][:16]}… seed={args.seed}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
