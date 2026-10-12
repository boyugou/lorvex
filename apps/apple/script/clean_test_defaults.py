#!/usr/bin/env python3
"""Delete the preference files the app's tests leave behind.

A test that makes its own `UserDefaults(suiteName: "<Prefix>.\\(UUID().uuidString)")`
cannot erase the suite's file when it ends: `removePersistentDomain` empties the
domain but leaves its plist in `~/Library/Preferences`, and a store that writes
into the suite refills it. Every full run adds hundreds of these files.

This script finds the prefixes the tests use (the literal text before
`\\(UUID().uuidString)` in a suite name under `Tests/`) and deletes only the
files named `<prefix>.<uuid>.plist` or `<prefix>-<uuid>.plist` for those prefixes,
so another project's preference files are never touched.

Usage: script/clean_test_defaults.py [--dry-run]
"""

from __future__ import annotations

import argparse
import glob
import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SUITE_NAME = re.compile(r'"([A-Za-z0-9_.-]+?)[.-]\\\(UUID\(\)\.uuidString\)"')
UUID_GLOB = "[.-]????????-????-????-????-????????????.plist"


def test_suite_prefixes(tests_dir: Path) -> set[str]:
    """The literal prefixes of every UUID-suffixed suite name in the tests."""
    prefixes: set[str] = set()
    for path in tests_dir.rglob("*.swift"):
        prefixes.update(SUITE_NAME.findall(path.read_text(encoding="utf-8", errors="replace")))
    return prefixes


def leftover_files(prefixes: set[str], preferences_dir: Path) -> list[Path]:
    found: list[Path] = []
    for prefix in sorted(prefixes):
        found.extend(Path(p) for p in glob.glob(str(preferences_dir / (glob.escape(prefix) + UUID_GLOB))))
    return found


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--dry-run", action="store_true", help="count the files without deleting them")
    arguments = parser.parse_args()
    preferences = Path(os.path.expanduser("~/Library/Preferences"))
    files = leftover_files(test_suite_prefixes(ROOT / "Tests"), preferences)
    if not arguments.dry_run:
        for path in files:
            path.unlink(missing_ok=True)
    verb = "would delete" if arguments.dry_run else "deleted"
    print(f"{verb} {len(files)} leftover test preference files in {preferences}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
