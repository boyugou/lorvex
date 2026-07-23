#!/usr/bin/env python3
"""Verify the typed MCP registry's bounded source-level invariants.

The Swift `ToolDefinitionRegistry` is the source of truth for listing,
dispatch, idempotency, and fencing. This verifier intentionally does not
reconstruct those derived surfaces. It keeps four cheap checks that remain
useful before compiling the host: expected names, duplicate definitions,
duplicate listing order, and write/idempotency-schema agreement.

The live manifest verifier separately compares the compiled host's schema to
`mcp_tool_manifest.json`, and the stdio smoke exercises real dispatch.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

from expected_mcp_tools import EXPECTED_MCP_TOOLS


ROOT = Path(__file__).resolve().parents[1]
MCP_SOURCE_DIR = ROOT / "Sources" / "LorvexMCPHost"
MANIFEST_PATH = Path(__file__).resolve().parent / "mcp_tool_manifest.json"
DEFINITION_PATTERN = re.compile(
    r"\.(read|write)\(\s*(\d+)\s*,\s*(\w+ToolCatalog)\.(\w+)",
    flags=re.DOTALL,
)


def catalog_declarations(source_dir: Path = MCP_SOURCE_DIR) -> dict[str, str]:
    declarations: dict[str, str] = {}
    for path in source_dir.glob("*ToolCatalog*.swift"):
        source = path.read_text(encoding="utf-8")
        type_match = re.search(r"\b(?:enum|extension)\s+(\w+)", source)
        if type_match is None:
            continue
        catalog = type_match.group(1)
        for match in re.finditer(
            r"static\s+let\s+(\w+)\s*=\s*Tool\s*\(\s*name:\s*\"([^\"]+)\"",
            source,
            flags=re.DOTALL,
        ):
            declarations[f"{catalog}.{match.group(1)}"] = match.group(2)
    return declarations


def definition_entries(source_dir: Path = MCP_SOURCE_DIR) -> list[tuple[str, int, str]]:
    entries: list[tuple[str, int, str]] = []
    for path in sorted(source_dir.glob("*ToolDefinitions.swift")):
        source = path.read_text(encoding="utf-8")
        entries.extend(
            (kind, int(order), f"{catalog}.{property_name}")
            for kind, order, catalog, property_name in DEFINITION_PATTERN.findall(source)
        )
    return entries


def duplicates(values: list[object]) -> list[object]:
    seen: set[object] = set()
    repeated: set[object] = set()
    for value in values:
        if value in seen:
            repeated.add(value)
        seen.add(value)
    return sorted(repeated)


def main() -> int:
    failures: list[str] = []
    declarations = catalog_declarations()
    entries = definition_entries()
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))

    resolved: list[tuple[str, int, str]] = []
    for kind, order, reference in entries:
        name = declarations.get(reference)
        if name is None:
            failures.append(f"definition references unknown catalog tool: {reference}")
            continue
        resolved.append((kind, order, name))

    names = [name for _, _, name in resolved]
    actual = set(names)
    expected = set(EXPECTED_MCP_TOOLS)
    missing = sorted(expected - actual)
    unexpected = sorted(actual - expected)
    duplicate_names = duplicates(names)
    orders = [order for _, order, _ in resolved]
    duplicate_orders = duplicates(orders)

    for kind, _, name in resolved:
        advertises_key = manifest.get(name, {}).get("advertises_idempotency_key") is True
        if kind == "write" and not advertises_key:
            failures.append(f"write definition does not advertise idempotency_key: {name}")
        if kind == "read" and advertises_key:
            failures.append(f"read definition advertises idempotency_key: {name}")

    if missing:
        failures.append(f"expected tools missing from typed registry: {missing}")
    if unexpected:
        failures.append(f"unexpected tools in typed registry: {unexpected}")
    if duplicate_names:
        failures.append(f"duplicate tool definitions: {duplicate_names}")
    if duplicate_orders:
        failures.append(f"duplicate tool listing orders: {duplicate_orders}")
    if sorted(orders) != list(range(len(orders))):
        failures.append("tool listing orders must be contiguous from zero")

    if failures:
        print("MCP typed registry verification failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    print(
        f"MCP typed registry verification passed: {len(names)} unique tools; "
        "write/idempotency metadata agrees"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
