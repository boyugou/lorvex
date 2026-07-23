#!/usr/bin/env python3
"""Drift gate for the bundled third-party ACKNOWLEDGMENTS.md resource.

Regenerates the notices document in memory from the currently-resolved
SwiftPM dependency graph (`Package.resolved` in the outer app and in
`core/`) and fails if it does not byte-for-byte match the checked-in
resource at `Sources/LorvexCore/Resources/ACKNOWLEDGMENTS.md`. This catches
every way the two can drift: a dependency added or removed, a version bump,
a repository URL change, or a hand-edit of the generated file — so a
dependency bump can never silently ship without its required license/NOTICE
text. Run `script/generate_acknowledgments.py` to resolve any failure it
reports.
"""

from __future__ import annotations

import sys
from pathlib import Path

from acknowledgments_data import (
    ACKNOWLEDGMENTS_PATH,
    ResolvedPackage,
    known_identities_missing_metadata,
    load_resolved_packages,
    render_acknowledgments,
    stale_metadata_identities,
)


def acknowledgments_failures(
    resolved: dict[str, ResolvedPackage],
    acknowledgments_path: Path,
) -> list[str]:
    failures: list[str] = []

    missing_metadata = known_identities_missing_metadata(resolved)
    if missing_metadata:
        failures.append(
            "resolved dependency has no license metadata in "
            f"acknowledgments_data.PACKAGE_METADATA (a dependency was added without "
            f"reviewing its license): {missing_metadata}"
        )

    stale = stale_metadata_identities(resolved)
    if stale:
        failures.append(
            "acknowledgments_data.PACKAGE_METADATA describes a package no longer "
            f"resolved by Package.resolved (a removed dependency's entry was not "
            f"cleaned up): {stale}"
        )

    if not acknowledgments_path.is_file():
        failures.append(f"bundled resource missing: {acknowledgments_path}")
        return failures

    if missing_metadata:
        # `render_acknowledgments` would KeyError on a package with no metadata;
        # the failure above already explains what to fix.
        return failures

    expected = render_acknowledgments(resolved)
    actual = acknowledgments_path.read_text(encoding="utf-8")
    if actual != expected:
        failures.append(
            f"{acknowledgments_path} is stale relative to the resolved dependency "
            "graph and/or acknowledgments_data.PACKAGE_METADATA; run "
            "script/generate_acknowledgments.py to regenerate it"
        )

    return failures


def main() -> int:
    try:
        resolved = load_resolved_packages()
    except (FileNotFoundError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    failures = acknowledgments_failures(resolved, ACKNOWLEDGMENTS_PATH)
    if failures:
        for failure in failures:
            print(failure, file=sys.stderr)
        return 1

    print(f"Acknowledgments verification passed: {len(resolved)} resolved dependencies covered")
    return 0


if __name__ == "__main__":
    sys.exit(main())
