#!/usr/bin/env python3
"""Generate the bundled third-party ACKNOWLEDGMENTS.md resource.

Reads the resolved SwiftPM dependency graph from both `Package.resolved`
files (the outer app and the `core/` package) and renders one aggregated
notices document from `acknowledgments_data.PACKAGE_METADATA` plus the
checked-in per-package license/NOTICE texts under `third_party_licenses/`.
Run with `--check` (used by `verify_acknowledgments.py`) to fail without
writing when the checked-in resource has drifted from the resolved graph.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from acknowledgments_data import (
    ACKNOWLEDGMENTS_PATH,
    known_identities_missing_metadata,
    load_resolved_packages,
    render_acknowledgments,
)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify the bundled resource matches the resolved graph without writing",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=ACKNOWLEDGMENTS_PATH,
        help="path to the generated ACKNOWLEDGMENTS.md resource",
    )
    args = parser.parse_args(argv)

    try:
        resolved = load_resolved_packages()
    except (FileNotFoundError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    missing_metadata = known_identities_missing_metadata(resolved)
    if missing_metadata:
        print(
            "error: resolved dependency has no license metadata in "
            f"acknowledgments_data.PACKAGE_METADATA: {missing_metadata}",
            file=sys.stderr,
        )
        return 2

    rendered = render_acknowledgments(resolved)

    if args.check:
        if not args.output.is_file():
            print(f"error: {args.output} does not exist", file=sys.stderr)
            return 1
        current = args.output.read_text(encoding="utf-8")
        if current != rendered:
            print(
                f"error: {args.output} is stale relative to the resolved dependency "
                "graph; run script/generate_acknowledgments.py to regenerate it",
                file=sys.stderr,
            )
            return 1
        print(f"{args.output} is up to date with {len(resolved)} resolved dependencies")
        return 0

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(rendered, encoding="utf-8")
    print(f"wrote {args.output} ({len(resolved)} resolved dependencies)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
