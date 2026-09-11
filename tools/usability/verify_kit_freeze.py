#!/usr/bin/env python3
"""Verifies that the usability kit still matches the v1.1 freeze record.

Reads the hash table from docs/usability/FREEZE_v1.1.md and recomputes every hash. Exits non-zero if
any frozen file changed, appeared or disappeared. Editing an instrument mid-study is exactly the kind
of thing that should fail loudly.
"""
from __future__ import annotations

import hashlib
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]
RECORD = REPO / "docs/usability/FREEZE_v1.1.md"
ROW = re.compile(r"^\|\s*`([^`]+)`\s*\|\s*(\d+)\s*\|\s*`([0-9a-f]{64})`\s*\|", re.MULTILINE)


def main() -> int:
    if not RECORD.exists():
        print(f"freeze record not found: {RECORD}")
        return 1
    expected = {path: (int(size), digest) for path, size, digest in ROW.findall(RECORD.read_text())}
    if not expected:
        print("no hashes parsed from the freeze record")
        return 1

    problems: list[str] = []
    for path, (size, digest) in sorted(expected.items()):
        target = REPO / path
        if not target.exists():
            problems.append(f"MISSING  {path}")
            continue
        data = target.read_bytes()
        actual = hashlib.sha256(data).hexdigest()
        if actual != digest:
            problems.append(f"CHANGED  {path} (sha256 {actual[:16]}… != frozen {digest[:16]}…)")
        elif len(data) != size:
            problems.append(f"CHANGED  {path} (size {len(data)} != frozen {size})")
        else:
            print(f"ok       {path}")

    print()
    if problems:
        print(f"FREEZE VIOLATIONS ({len(problems)}):")
        for problem in problems:
            print("  " + problem)
        return 1
    print(f"freeze intact: {len(expected)} files match docs/usability/FREEZE_v1.1.md")
    return 0


if __name__ == "__main__":
    sys.exit(main())
