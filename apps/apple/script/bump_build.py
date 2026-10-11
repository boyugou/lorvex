#!/usr/bin/env python3
"""Bump the build number everywhere it is written, then verify the result.

The build number is a literal in eight files; the marketing version stays put
between TestFlight builds. Every file is edited with one exact replacement that
must match exactly once, and all replacements are computed before any file is
written, so a file that drifted from the expected shape fails loudly and leaves
the tree untouched. `verify_app_metadata.py` runs last and names any file that
still disagrees.

Usage:
    script/bump_build.py          # the current build number plus one
    script/bump_build.py 120      # an explicit number above the current one

Afterward, run the AppMetadata tests and commit, so the uploaded build matches
a commit on main.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

_PLIST_BUILD = r"(<key>CFBundleVersion</key>\s*<string>)\d+(</string>)"

# Path relative to the app root, and a pattern whose group 1 is the text before
# the number and group 2 the text after it. The watch app and the Focus filter
# Info.plists read $(CURRENT_PROJECT_VERSION), so they hold no literal.
TARGETS: list[tuple[str, str]] = [
    ("script/app_metadata.sh", r'(\nBUILD_VERSION=")\d+(")'),
    ("Sources/LorvexCore/Models/ProductMetadata.swift", r'(buildVersion = ")\d+(")'),
    ("Config/XcodeGen/project.yml", r'(CURRENT_PROJECT_VERSION: ")\d+(")'),
    ("Config/LorvexMobileApp-Info.plist", _PLIST_BUILD),
    ("Config/LorvexWatchComplication-Info.plist", _PLIST_BUILD),
    ("Config/LorvexWidgets-Info.plist", _PLIST_BUILD),
    ("Config/LorvexMCPHost-Info.plist", _PLIST_BUILD),
    ("Tests/LorvexAppleTests/AppMetadataTests.swift", r'(AppMetadata\.buildVersion == ")\d+(")'),
]


def current_build(root: Path) -> int:
    text = (root / "script/app_metadata.sh").read_text(encoding="utf-8")
    match = re.search(r'^BUILD_VERSION="(\d+)"$', text, re.MULTILINE)
    if match is None:
        raise SystemExit("bump_build: cannot read BUILD_VERSION from script/app_metadata.sh")
    return int(match.group(1))


def replaced_once(path: Path, pattern: str, number: int, root: Path) -> str:
    text = path.read_text(encoding="utf-8")
    new_text, count = re.subn(pattern, lambda m: f"{m.group(1)}{number}{m.group(2)}", text)
    if count != 1:
        raise SystemExit(
            f"bump_build: {path.relative_to(root)} has {count} matches for its build-number "
            "pattern, expected exactly 1; nothing was changed"
        )
    return new_text


def bump(root: Path, requested: int | None = None) -> int:
    """Write the new build number into every target file and return it."""
    current = current_build(root)
    target = current + 1 if requested is None else requested
    if target <= current:
        raise SystemExit(f"bump_build: {target} is not above the current build number {current}")
    edits = {
        root / relative: replaced_once(root / relative, pattern, target, root)
        for relative, pattern in TARGETS
    }
    for path, text in edits.items():
        path.write_text(text, encoding="utf-8")
    return target


def main(argv: list[str]) -> int:
    if len(argv) > 2 or (len(argv) == 2 and not argv[1].isdigit()):
        print(__doc__, file=sys.stderr)
        return 2
    requested = int(argv[1]) if len(argv) == 2 else None
    previous = current_build(ROOT)
    target = bump(ROOT, requested)
    print(f"bump_build: build number {previous} -> {target} in {len(TARGETS)} files")
    # Run the verifier as a script, not isolated: it imports a sibling module.
    return subprocess.run([sys.executable, str(ROOT / "script/verify_app_metadata.py")]).returncode


if __name__ == "__main__":
    sys.exit(main(sys.argv))
