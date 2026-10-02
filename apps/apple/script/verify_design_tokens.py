#!/usr/bin/env python3
"""Verify that Apple UI code composes from the design tokens.

The design contract lives in ``docs/design/DESIGN_SYSTEM.md``: color is semantic
(``LorvexDesign.Palette``), spacing and radii come from ``LorvexDesign.Spacing`` /
``Radius``, and type comes from ``LorvexDesign.Typography``. This gate scans the
UI targets and fails when a view

- names a raw system hue in a color position (``Color.orange``, ``tint: .red``,
  ``.foregroundStyle(.green)``, ``.tint(.blue)``, ``.fill(.pink)``, …) or builds
  a color from components (``Color(red:``);
- uses a fixed point size (``.font(.system(size:``) instead of a typography
  token;
- passes a numeric corner radius (``cornerRadius: 12``) instead of a radius
  token;
- names a fixed-direction glyph (``chevron.left``, ``arrow.right.to.line``,
  ``arrow.turn.up.right``, …) instead of its ``forward`` / ``backward`` form,
  which mirrors in a right-to-left layout. Fold chevrons come from
  ``LorvexDisclosureChevron``; glyphs that name both directions
  (``arrow.left.and.right``) are symmetric and pass;
- trims a circle into a progress arc (``.trim(from:``) instead of drawing it
  with ``LorvexProgressArc``, which starts at twelve o'clock and fills with
  the reading direction.

``ALLOWED`` lists whole files that legitimately hold literals: the token
definitions themselves, the hex-color helpers, the user-facing color picker, and
the DEBUG snapshot renderers and debug seeds. A single line may opt out with the
trailing comment ``// lorvex-design-token: allow`` when a glyph scales with its
container or a hue is purely decorative; both lists are the complete inventory
of intentional literals.

Exit status: 0 when every UI file is token-clean, 1 otherwise (each offending
line is printed to stderr).
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]  # apps/apple

SCAN_ROOTS = [
    "Sources/LorvexApple",
    "Sources/LorvexMobile",
    "Sources/LorvexWatch",
    "Sources/LorvexWidgetViews",
    "Sources/LorvexWidgetKitSupport",
    "Sources/LorvexCore/Models",
    "Sources/LorvexCore/Support",
]

# Files that legitimately hold literals. Keep the reason with each entry.
ALLOWED = {
    # The token definitions: this is where the hues are assigned a meaning.
    "Sources/LorvexCore/Support/LorvexDesignSystem.swift",
    "Sources/LorvexCore/Support/LorvexDesign.swift",
    # Hex parsing for user-chosen entity colors and the fixed preset swatches.
    "Sources/LorvexCore/Support/Color+LorvexHex.swift",
    # The user-facing color picker names the system hues it offers.
    "Sources/LorvexMobile/MobileIconColorPicker.swift",
    "Sources/LorvexApple/Views/LorvexColorField.swift",
    # DEBUG-only design renderers and seeds; not shipped UI.
    "Sources/LorvexApple/App/LorvexAppleSnapshotDump.swift",
    "Sources/LorvexApple/App/LorvexMilestoneSnapshotDump.swift",
    "Sources/LorvexMobile/MobileStoreDebugSeed.swift",
    # Icon tiles size their symbol relative to the tile, not to a text style.
    "Sources/LorvexMobile/MobileIconTile.swift",
    "Sources/LorvexApple/Views/LorvexListIconView.swift",
    # The direction-following primitives: the fold chevron draws `chevron.right`
    # and the progress arc trims a circle, and each mirrors itself.
    "Sources/LorvexCore/Support/LorvexLayoutDirection.swift",
}

# A line-level exception for a glyph that scales with its container or for
# purely decorative hues (the Settings traffic-light dots). Every use is a
# documented literal; grep for it to audit the inventory.
ALLOW_MARKER = "lorvex-design-token: allow"

HUES = "red|orange|yellow|green|mint|teal|cyan|blue|indigo|purple|pink|brown|gray"

RULES = [
    (
        "raw system hue",
        re.compile(
            rf"(?:\bColor\.(?:{HUES})\b"
            rf"|(?:tint|color|fill|foreground|background|stroke|iconTint|accent)\s*:\s*\.(?:{HUES})\b"
            rf"|\.(?:tint|foregroundStyle|foregroundColor|fill|background|stroke|strokeBorder|listRowBackground)\(\s*\.(?:{HUES})\b"
            rf"|AnyShapeStyle\(\s*\.(?:{HUES})\b"
            rf"|\?\s*\.(?:{HUES})\b\s*:"
            rf"|:\s*\.(?:{HUES})\s*\)"
            rf"|\bColor\(\s*red:)"
        ),
    ),
    ("fixed point size", re.compile(r"\.font\(\s*\.system\(\s*size\s*:")),
    ("numeric corner radius", re.compile(r"cornerRadius\s*:\s*\d")),
    (
        "fixed-direction glyph",
        re.compile(
            r'"(?![^"]*left[^"]*right)(?![^"]*right[^"]*left)'
            r'(?:chevron|arrow|arrowtriangle|arrowshape)(?:\.[a-z0-9]+)*\.(?:left|right)(?:\.[a-z0-9]+)*"'
        ),
    ),
    ("hand-drawn progress arc", re.compile(r"\.trim\(\s*from\s*:")),
]


def scan_file(path: Path, root: Path = ROOT) -> list[str]:
    failures: list[str] = []
    rel = path.relative_to(root).as_posix()
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        stripped = line.strip()
        if stripped.startswith("//") or stripped.startswith("///"):
            continue
        if ALLOW_MARKER in line:
            continue
        for name, rule in RULES:
            if rule.search(line):
                failures.append(f"{rel}:{number}: {name}: {stripped}")
    return failures


def token_failures(root: Path = ROOT) -> list[str]:
    failures: list[str] = []
    for scan_root in SCAN_ROOTS:
        base = root / scan_root
        if not base.is_dir():
            continue
        for path in sorted(base.rglob("*.swift")):
            if path.relative_to(root).as_posix() in ALLOWED:
                continue
            failures.extend(scan_file(path, root))
    return failures


def main() -> int:
    failures = token_failures()
    if failures:
        print("Design token verification failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1
    print("Design token verification passed: UI targets compose from LorvexDesign tokens")
    return 0


if __name__ == "__main__":
    sys.exit(main())
