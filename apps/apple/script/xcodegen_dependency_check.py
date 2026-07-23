#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def target_block(source: str, target: str) -> list[str]:
    lines = source.splitlines()
    start: int | None = None
    header = f"  {target}:"
    for index, line in enumerate(lines):
        if line == header:
            start = index + 1
            break
    if start is None:
        return []

    block: list[str] = []
    for line in lines[start:]:
        if line.startswith("  ") and not line.startswith("    ") and line.strip().endswith(":"):
            break
        block.append(line)
    return block


def dependency_entries(block: list[str]) -> list[dict[str, object]]:
    entries: list[dict[str, object]] = []
    in_dependencies = False
    current: dict[str, object] | None = None

    for line in block:
        stripped = line.strip()
        if line.startswith("    ") and not line.startswith("      ") and stripped == "dependencies:":
            in_dependencies = True
            current = None
            continue
        if in_dependencies and line.startswith("    ") and not line.startswith("      ") and stripped.endswith(":"):
            break
        if not in_dependencies:
            continue
        if not stripped or stripped.startswith("#"):
            continue

        if line.startswith("      - "):
            if current is not None:
                entries.append(current)
            current = {}
            payload = stripped[2:].strip()
            if ":" in payload:
                key, value = payload.split(":", 1)
                current[key.strip()] = parse_scalar(value.strip())
            continue

        if current is not None and line.startswith("        ") and ":" in stripped:
            key, value = stripped.split(":", 1)
            current[key.strip()] = parse_scalar(value.strip())

    if current is not None:
        entries.append(current)
    return entries


def parse_scalar(value: str) -> object:
    value = value.split(" #", 1)[0].strip()
    if value == "true":
        return True
    if value == "false":
        return False
    return value.strip("\"'")


def dependency_entry(source: str, owner: str, dependency: str) -> dict[str, object] | None:
    block = target_block(source, owner)
    for entry in dependency_entries(block):
        if entry.get("target") == dependency:
            return entry
    return None


def dependency_failures(
    source: str,
    owner: str,
    dependency: str,
    *,
    require_embed: bool,
) -> list[str]:
    entry = dependency_entry(source, owner, dependency)
    if entry is None:
        return [f"{owner} is missing dependency target {dependency}"]
    if require_embed and entry.get("embed") is not True:
        return [f"{owner} dependency {dependency} must set embed: true"]
    return []


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Verify XcodeGen target dependency wiring.")
    parser.add_argument("--project", type=Path, default=ROOT / "Config" / "XcodeGen" / "project.yml")
    parser.add_argument("--owner", required=True)
    parser.add_argument("--dependency", required=True)
    parser.add_argument("--require-embed", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    failures = dependency_failures(
        args.project.read_text(encoding="utf-8"),
        args.owner,
        args.dependency,
        require_embed=args.require_embed,
    )
    if failures:
        for failure in failures:
            print(failure, file=sys.stderr)
        return 1
    print(f"{args.owner} dependency {args.dependency} verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
