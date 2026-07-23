#!/usr/bin/env python3
"""Lock the MCP tool *input-schema* surface against drift.

`verify_mcp_tool_catalog.py` guards the typed registry's tool names, uniqueness,
listing order, and write/idempotency classification. It does not look at full
argument shapes, so renaming/removing/retyping a tool's input field can slip
through. This verifier closes that gap: it drives the real `LorvexMCPHost` over stdio
(`initialize` → `tools/list`), reduces every tool to a typed signature
(its input-schema property names→type tokens, the `required` set, and whether it
advertises `idempotency_key`), and diffs that against the committed
`mcp_tool_manifest.json`.

The type token folds in every client-observable constraint the manifest locks,
so a change to any of them fails the diff:

- enum value sets, sorted into the token (`enum[completion,schedule]`), so an
  enum-value rename ("open"→"todo") or a new allowed value is caught;
- array item shapes (`array<enum[MO,TU,...]>`);
- nested object `properties` and their `required` set, recursively — a renamed
  field inside `recurrence`, `attendees[]`, or a batch item object is caught.

Descriptions and prose are intentionally excluded — they churn and are not a
client contract; the property/type/enum/required/idempotency shape is.

Usage:
  verify_mcp_tool_manifest.py            verify the live host matches the lock
  verify_mcp_tool_manifest.py --write    regenerate the lock after an intended
                                         tool-schema change, then review the diff
"""

from __future__ import annotations

import json
import os
import select
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any

from metadata_env import load_metadata


ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = ROOT.parents[1]
SCHEMA_PATH = REPO_ROOT / "schema" / "schema.sql"
MANIFEST_PATH = Path(__file__).resolve().parent / "mcp_tool_manifest.json"
PROTOCOL_VERSION = "2025-11-25"


class ManifestFailure(RuntimeError):
    pass


def _run(command: list[str]) -> str:
    result = subprocess.run(
        command, cwd=ROOT, check=True, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    return result.stdout.strip()


def _send(process: subprocess.Popen[str], message: dict[str, Any]) -> None:
    assert process.stdin is not None
    process.stdin.write(json.dumps(message, separators=(",", ":")) + "\n")
    process.stdin.flush()


def _read(process: subprocess.Popen[str], request_id: int, timeout: float = 15.0) -> dict[str, Any]:
    assert process.stdout is not None
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        ready, _, _ = select.select([process.stdout], [], [], 0.1)
        if not ready:
            continue
        line = process.stdout.readline()
        if not line:
            break
        payload = json.loads(line)
        if payload.get("id") == request_id:
            if "error" in payload:
                raise ManifestFailure(f"request {request_id} errored: {payload['error']}")
            return payload
    raise ManifestFailure(f"timed out waiting for response id {request_id}")


def _enum_token(value: Any) -> str:
    """Render one enum member for the sorted enum token (bare string / JSON scalar)."""
    return value if isinstance(value, str) else json.dumps(value, sort_keys=True)


def _object_token(schema: dict[str, Any]) -> str:
    """Type token for an object fragment: its sorted property shapes + required set."""
    properties = schema.get("properties") or {}
    required = schema.get("required") or []
    prop_tokens = ",".join(
        f"{name}:{_property_type(properties[name])}" for name in sorted(properties)
    )
    required_token = ",".join(sorted(str(name) for name in required))
    return f"object{{{prop_tokens}}}required[{required_token}]"


def _property_type(schema: Any) -> str:
    """Reduce one property's JSON-schema fragment to a stable type token.

    `enum` is tested before `type` so an enum-constrained field records its
    sorted value set (`enum[DAILY,MONTHLY,...]`) rather than the bare base type
    it also declares; arrays fold in their item shape and objects recurse into
    their nested `properties` + `required`.
    """
    if not isinstance(schema, dict):
        return "unknown"
    if "enum" in schema and isinstance(schema["enum"], list):
        return "enum[" + ",".join(sorted(_enum_token(v) for v in schema["enum"])) + "]"
    type_value = schema.get("type")
    if isinstance(type_value, str):
        if type_value == "array":
            items = schema.get("items")
            return f"array<{_property_type(items)}>" if items is not None else "array"
        if type_value == "object":
            return _object_token(schema)
        return type_value
    if isinstance(type_value, list):
        return "|".join(str(t) for t in sorted(type_value))
    return _object_token(schema) if "properties" in schema else "unknown"


def _tool_signature(tool: dict[str, Any]) -> dict[str, Any]:
    schema = tool.get("inputSchema") or {}
    properties = schema.get("properties") or {}
    required = schema.get("required") or []
    return {
        "properties": {name: _property_type(properties[name]) for name in sorted(properties)},
        "required": sorted(required),
        "advertises_idempotency_key": "idempotency_key" in properties,
    }


def live_manifest() -> dict[str, Any]:
    metadata = load_metadata()
    product = metadata.get("MCP_HOST_PRODUCT", "LorvexMCPHost")
    marketing_version = metadata.get("MARKETING_VERSION", "1.0.0")
    if not SCHEMA_PATH.exists():
        raise ManifestFailure(f"missing schema at {SCHEMA_PATH}")

    binary = os.environ.get("MCP_HOST_BINARY")
    if binary:
        bin_path = Path(binary)
    else:
        _run(["swift", "build", "--product", product])
        bin_path = Path(_run(["swift", "build", "--show-bin-path"])) / product
    if not bin_path.exists():
        raise ManifestFailure(f"missing MCP host binary at {bin_path}")

    db_tempdir = tempfile.TemporaryDirectory(prefix="lorvex-mcp-manifest-")
    db_path = Path(db_tempdir.name) / "lorvex.db"
    process = subprocess.Popen(
        [str(bin_path)], cwd=ROOT,
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        env={
            **os.environ,
            "NSUnbufferedIO": "YES",
            "LORVEX_APPLE_DB_PATH": str(db_path),
            "LORVEX_APPLE_SCHEMA_PATH": str(SCHEMA_PATH),
        },
    )
    try:
        _send(process, {
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": {
                "protocolVersion": PROTOCOL_VERSION, "capabilities": {},
                "clientInfo": {"name": "lorvex-manifest", "version": marketing_version},
            },
        })
        _read(process, 1)
        _send(process, {"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})
        _send(process, {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
        tools = _read(process, 2)["result"]["tools"]
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
        db_tempdir.cleanup()

    if not tools:
        raise ManifestFailure("tools/list returned no tools")
    return {tool["name"]: _tool_signature(tool) for tool in tools}


def _serialize(manifest: dict[str, Any]) -> str:
    return json.dumps(manifest, indent=2, sort_keys=True) + "\n"


def main() -> int:
    write = "--write" in sys.argv[1:]
    try:
        manifest = live_manifest()
    except ManifestFailure as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1

    if write:
        MANIFEST_PATH.write_text(_serialize(manifest), encoding="utf-8")
        print(f"PASS: wrote {MANIFEST_PATH.name} with {len(manifest)} tools.")
        return 0

    if not MANIFEST_PATH.exists():
        print(
            f"FAIL: missing {MANIFEST_PATH.name}. Regenerate with "
            "`python3 script/verify_mcp_tool_manifest.py --write`.",
            file=sys.stderr,
        )
        return 1

    committed = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    if committed == manifest:
        print(f"PASS: MCP tool manifest matches ({len(manifest)} tools).")
        return 0

    drift: list[str] = []
    for name in sorted(set(committed) | set(manifest)):
        if name not in manifest:
            drift.append(f"  - tool removed: {name}")
        elif name not in committed:
            drift.append(f"  - tool added: {name}")
        elif committed[name] != manifest[name]:
            drift.append(f"  - input-schema changed: {name}")
            drift.append(f"      locked: {json.dumps(committed[name], sort_keys=True)}")
            drift.append(f"      actual: {json.dumps(manifest[name], sort_keys=True)}")
    print(
        "FAIL: MCP tool input-schema drift vs script/mcp_tool_manifest.json.\n"
        + "\n".join(drift)
        + "\nIf intended, regenerate with "
        "`python3 script/verify_mcp_tool_manifest.py --write` and review the diff.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
