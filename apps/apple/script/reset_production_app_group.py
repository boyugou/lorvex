#!/usr/bin/env python3
"""Irreversibly clear Lorvex production local state before final-app launch."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from datetime import UTC, datetime
from pathlib import Path

from mcp_stdio_smoke import (
    DESTRUCTIVE_RESET_ENV,
    McpSmokeFailure,
    require_quiescent_app_group,
    reset_real_app_group_state,
    signed_entitlements,
    stop_lorvex_processes,
    verify_sandboxed_release_binary,
)
from metadata_env import load_metadata


DEFAULTS = Path("/usr/bin/defaults")


def defaults_domain_is_absent(output: str) -> bool:
    lowered = output.lower()
    return "does not exist" in lowered or "not found" in lowered


def validate_app_group_identifier(identifier: str) -> None:
    if (
        not identifier.startswith("group.")
        or "/" in identifier
        or "\\" in identifier
        or identifier in ("group.", ".", "..")
    ):
        raise ValueError(f"invalid App Group identifier: {identifier!r}")


def atomic_json(path: Path, payload: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", dir=path.parent
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            json.dump(payload, stream, indent=2, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def clear_defaults_domain(domain: str) -> None:
    """Delete one preferences domain from every known sandbox container."""
    deleted = subprocess.run(
        [str(DEFAULTS), "delete-all", domain],
        capture_output=True,
        text=True,
        check=False,
    )
    deleted_output = f"{deleted.stdout}\n{deleted.stderr}"
    if deleted.returncode != 0 and not defaults_domain_is_absent(deleted_output):
        raise McpSmokeFailure(
            f"cannot clear defaults domain {domain!r}: "
            f"{deleted.stderr.strip() or deleted.returncode}"
        )
    checked = subprocess.run(
        [str(DEFAULTS), "read", domain],
        capture_output=True,
        text=True,
        check=False,
    )
    checked_output = f"{checked.stdout}\n{checked.stderr}"
    if checked.returncode == 0 or not defaults_domain_is_absent(checked_output):
        raise McpSmokeFailure(
            f"defaults domain {domain!r} still exists or cannot be verified absent"
        )


def remove_private_state(path: Path) -> None:
    if path.is_symlink() or path.is_file():
        path.unlink(missing_ok=True)
    elif path.is_dir():
        shutil.rmtree(path)


def reset_installed_app_group(
    helper_binary: Path,
    app_group_id: str,
    app_bundle_id: str,
    application_support_name: str,
    process_names: tuple[str, ...],
    *,
    home: Path | None = None,
    evidence_path: Path | None = None,
) -> int:
    """Clear shared data, defaults, and private sync state without restoration."""
    validate_app_group_identifier(app_group_id)
    if not helper_binary.is_file():
        raise FileNotFoundError(f"installed MCP helper is missing: {helper_binary}")
    if not process_names:
        raise ValueError("at least one Lorvex process name is required")

    entitlements = signed_entitlements(helper_binary)
    verify_sandboxed_release_binary(helper_binary, app_group_id, entitlements)

    stop_lorvex_processes(process_names)
    base_home = home if home is not None else Path.home()
    group_container = (
        base_home
        / "Library"
        / "Group Containers"
        / app_group_id
    )
    require_quiescent_app_group(group_container)
    private_container = base_home / "Library" / "Containers" / app_bundle_id
    if private_container.exists():
        require_quiescent_app_group(private_container)

    clear_defaults_domain(app_bundle_id)
    clear_defaults_domain(app_group_id)
    private_state = (
        private_container
        / "Data"
        / "Library"
        / "Application Support"
        / application_support_name
    )
    remove_private_state(private_state)

    container = group_container / "Lorvex"
    database = container / "db.sqlite"
    generation = reset_real_app_group_state(database)
    if database.exists():
        raise McpSmokeFailure(
            f"production database still exists after destructive reset: {database}"
        )

    if evidence_path is not None:
        atomic_json(
            evidence_path,
            {
                "appGroupIdentifier": app_group_id,
                "backupCreated": False,
                "databaseAbsentAfterReset": True,
                "databasePath": str(database),
                "defaultsDomainsCleared": [app_bundle_id, app_group_id],
                "destructive": True,
                "generation": generation,
                "helperBinary": str(helper_binary.resolve(strict=True)),
                "priorDataRestored": False,
                "privateStatePathCleared": str(private_state),
                "resetAt": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
            },
        )
    return generation


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--helper-binary", required=True, type=Path)
    parser.add_argument("--evidence", required=True, type=Path)
    parser.add_argument("--process-name", action="append", default=[])
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    if os.environ.get(DESTRUCTIVE_RESET_ENV) != "1":
        print(
            "production App Group reset requires explicit destructive "
            f"acknowledgement: {DESTRUCTIVE_RESET_ENV}=1",
            file=sys.stderr,
        )
        return 2

    metadata = load_metadata()
    process_names = tuple(args.process_name) or (
        metadata.get("APP_NAME", "Lorvex"),
        metadata.get("MCP_HOST_PRODUCT", "LorvexMCPHost"),
        metadata.get("WIDGET_EXECUTABLE", "LorvexFocusWidget"),
    )
    try:
        generation = reset_installed_app_group(
            args.helper_binary,
            metadata.get("APP_GROUP_ID", "group.com.lorvex.apple"),
            metadata.get("BUNDLE_ID", "com.lorvex.apple"),
            metadata.get("APP_PRODUCT_NAME", "LorvexApple"),
            process_names,
            evidence_path=args.evidence,
        )
    except (McpSmokeFailure, OSError, RuntimeError, ValueError) as error:
        print(f"production App Group reset failed: {error}", file=sys.stderr)
        return 1

    print(
        "Production App Group permanently cleared before cold launch "
        f"(generation {generation}); no backup or restoration was performed"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
