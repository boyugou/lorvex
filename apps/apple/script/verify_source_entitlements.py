#!/usr/bin/env python3
"""Reject over-broad capabilities in the repo's source ``.entitlements`` plists.

``verify_codesign_entitlements.py`` inspects what a built, signed bundle actually
carries. This gate guards the SOURCE entitlement plists checked into the repo, so
an over-broad grant is caught at review time — before it can ever be signed into a
build. Lorvex is a local-first task manager (managed storage + CloudKit sync); it
needs none of the following, so any of them appearing in a source file is treated
as a mistake:

  * ``com.apple.security.app-sandbox`` set to ``false`` — disables the App
    Sandbox entirely.
  * ``com.apple.security.network.client`` / ``com.apple.security.network.server``
    — outbound / inbound network access.
  * ``com.apple.security.files.all`` — unrestricted filesystem access.
  * any ``com.apple.security.temporary-exception.*`` key — sandbox escape
    hatches (absolute-path file access, mach-lookup, etc.).

The check passes on every entitlement file Lorvex ships today; its job is to keep
a future edit from quietly adding one of these.
"""

from __future__ import annotations

import plistlib
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

SANDBOX_KEY = "com.apple.security.app-sandbox"
TEMPORARY_EXCEPTION_PREFIX = "com.apple.security.temporary-exception."

# Keys that must never be granted (truthy) in a source entitlements file.
DENIED_TRUTHY_KEYS = (
    "com.apple.security.network.client",
    "com.apple.security.network.server",
    "com.apple.security.files.all",
)

# Directory names that hold build artifacts / generated copies, not source.
_SKIP_DIR_PARTS = {".build", "dist", "DerivedData", ".git"}


def overbroad_entitlement_failures(label: str, entitlements: dict) -> list[str]:
    """Pure decision core: the over-broad grants present in one entitlements dict.

    ``label`` names the file for the failure message. Returns one message per
    over-broad grant found; an empty list means the file is clean."""
    failures: list[str] = []

    if entitlements.get(SANDBOX_KEY) is False:
        failures.append(f"{label} disables the App Sandbox ({SANDBOX_KEY} = false)")

    for key in DENIED_TRUTHY_KEYS:
        if entitlements.get(key):
            failures.append(f"{label} grants over-broad entitlement {key}")

    for key in sorted(entitlements):
        if key.startswith(TEMPORARY_EXCEPTION_PREFIX):
            failures.append(f"{label} grants sandbox temporary-exception entitlement {key}")

    return failures


def source_entitlement_files(root: Path) -> list[Path]:
    """Every source ``.entitlements`` file under ``root``, excluding build
    artifacts and generated copies."""
    files: list[Path] = []
    for path in sorted(root.rglob("*.entitlements")):
        if any(part in _SKIP_DIR_PARTS or part.endswith(".xcodeproj") for part in path.parts):
            continue
        files.append(path)
    return files


def main() -> int:
    files = source_entitlement_files(ROOT)
    if not files:
        print(
            "verify_source_entitlements: no .entitlements files found under "
            f"{ROOT} (expected the Config/ plists)",
            file=sys.stderr,
        )
        return 1

    failures: list[str] = []
    for path in files:
        try:
            with path.open("rb") as file:
                entitlements = plistlib.load(file)
        except (OSError, plistlib.InvalidFileException) as error:
            failures.append(f"{path.relative_to(ROOT)} could not be parsed: {error}")
            continue
        failures.extend(
            overbroad_entitlement_failures(str(path.relative_to(ROOT)), entitlements)
        )

    if failures:
        for message in failures:
            print(message, file=sys.stderr)
        return 1

    print(f"Source entitlements verification passed: {len(files)} files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
