#!/usr/bin/env python3
"""Regenerates docs/usability/task_images/task2_unsuitable.jpg deterministically.

The unsuitable stimulus must be byte-reproducible so the study is repeatable and so no participant
ever sees a different (or personal) photo. task1_subject.jpg is a real CC-licensed photo and is
recorded in PROVENANCE.md instead of being generated.
"""
from __future__ import annotations

import pathlib

from PIL import Image, ImageDraw, ImageFilter

OUT = pathlib.Path(__file__).resolve().parents[2] / "docs/usability/task_images/task2_unsuitable.jpg"


def main() -> int:
    width, height = 720, 960
    image = Image.new("RGB", (width, height), (74, 78, 82))
    draw = ImageDraw.Draw(image)
    # a faint, meaningless smear: no identifiable subject
    for y in range(0, height, 7):
        shade = 74 + (y * 13) % 22
        draw.line([(0, y), (width, y)], fill=(shade, shade + 2, shade + 4), width=4)
    # glare band across the middle, like a reflection on a screen
    draw.rectangle([0, 380, width, 470], fill=(214, 218, 222))
    # screen pixel grid, so it reads as a photo *of a screen*
    for x in range(0, width, 24):
        draw.line([(x, 0), (x, height)], fill=(64, 66, 70), width=1)
    for y in range(0, height, 24):
        draw.line([(0, y), (width, y)], fill=(64, 66, 70), width=1)
    image = image.filter(ImageFilter.GaussianBlur(radius=6.0))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    image.save(OUT, quality=90)
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
