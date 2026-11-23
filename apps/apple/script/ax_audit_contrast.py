#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow"]
# ///
"""Measures the contrast of the accessibility audit's contrast findings.

    uv run script/ax_audit_contrast.py <findings file> <screenshot directory>

`script/ios_sim_accessibility_audit.sh` writes both. The audit says only
"failed" or "nearly passed"; this reads each finding's frame on the screenshot
of its screen and prints the WCAG contrast ratio of the text against its
background, lowest first, so a finding can be judged by a number.

The background is the frame's most common color and the text is the most
common color among the pixels farthest from it in luminance. Thin strokes are
blended with the background by antialiasing, so a ratio for small text reads a
little low; a frame that holds several colors (a glyph beside a word, a
gradient) reads unreliably and deserves a look at the screenshot.
"""

from __future__ import annotations

import sys
from collections import Counter
from pathlib import Path

from PIL import Image


def linear(channel: int) -> float:
    value = channel / 255
    return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4


def luminance(pixel: tuple[int, int, int]) -> float:
    return 0.2126 * linear(pixel[0]) + 0.7152 * linear(pixel[1]) + 0.0722 * linear(pixel[2])


def contrast(first: tuple[int, int, int], second: tuple[int, int, int]) -> float:
    high, low = sorted((luminance(first), luminance(second)), reverse=True)
    return (high + 0.05) / (low + 0.05)


def measure(image: Image.Image, frame: tuple[int, int, int, int], scale: float):
    x, y, width, height = frame
    box = tuple(round(value * scale) for value in (x, y, x + width, y + height))
    pixels = list(image.crop(box).get_flattened_data())
    if not pixels:
        return None
    background = Counter(pixels).most_common(1)[0][0]
    base = luminance(background)
    farthest = sorted(pixels, key=lambda pixel: -abs(luminance(pixel) - base))
    text = Counter(farthest[: max(20, len(pixels) // 100)]).most_common(1)[0][0]
    return contrast(text, background), text, background


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__.strip().splitlines()[2].strip(), file=sys.stderr)
        return 2
    findings, screenshots = Path(sys.argv[1]), Path(sys.argv[2])
    images: dict[str, Image.Image | None] = {}
    lines = [line.split("|") for line in findings.read_text().splitlines()]
    # The app window's width in points, which turns a frame into pixels.
    window_width = {
        parts[1]: int(parts[3].split("x")[0])
        for parts in lines
        if len(parts) == 4 and parts[2] == "window"
    }
    rows = []
    for parts in lines:
        if len(parts) < 8 or parts[2] != "contrast" or parts[6] == "-":
            continue
        screen, label, identifier, frame_text = parts[1], parts[4], parts[5], parts[6]
        if screen not in images:
            path = screenshots / f"{screen}.png"
            images[screen] = Image.open(path).convert("RGB") if path.exists() else None
        image = images[screen]
        if image is None:
            continue
        origin, size = frame_text.split(" ")
        x, y = (int(value) for value in origin.split(","))
        width, height = (int(value) for value in size.split("x"))
        # A capture is the screen in pixels and a frame is in points. A
        # findings file without the window's width is taken to be an iPhone's.
        scale = image.width / window_width[screen] if screen in window_width else 3
        measured = measure(image, (x, y, width, height), scale)
        if measured is None:
            continue
        ratio, text, background = measured
        verdict = "failed" if "Contrast failed" in parts[7] else "nearly"
        rows.append((ratio, screen, verdict, label or identifier, frame_text, text, background))
    for ratio, screen, verdict, label, frame_text, text, background in sorted(rows):
        print(
            f"{ratio:5.2f}  {screen:15s} {verdict:7s} "
            f"#{text[0]:02x}{text[1]:02x}{text[2]:02x} on "
            f"#{background[0]:02x}{background[1]:02x}{background[2]:02x}  "
            f"{frame_text:18s} {label[:60]}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
