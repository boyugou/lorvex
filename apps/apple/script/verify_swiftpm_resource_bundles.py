#!/usr/bin/env python3
"""Verify SwiftPM resource bundles are staged in a valid macOS app layout."""

from __future__ import annotations

import re
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
PAYLOAD_CONTRACT_AUTHORITY_DIR = REPO_ROOT / "schema" / "sync_payload"
PAYLOAD_CONTRACT_EMBEDDED_DIR = (
    REPO_ROOT
    / "apps"
    / "apple"
    / "core"
    / "Sources"
    / "LorvexSync"
    / "Resources"
    / "SyncPayloadContracts"
)
SCHEMA_AUTHORITY_PATH = REPO_ROOT / "schema" / "schema.sql"
CHECKSUMS_AUTHORITY_PATH = REPO_ROOT / "schema" / "migrations" / "checksums.lock"
PAYLOAD_MANIFEST_NAME = re.compile(r"^\d{3,}\.json$")
CORE_RESOURCE_BUNDLE = "LorvexApple_LorvexCore.bundle"
SYNC_RESOURCE_BUNDLE = "LorvexAppleCore_LorvexSync.bundle"
WIDGET_APPEX_NAME = "LorvexFocusWidget.appex"
REQUIRED_CORE_BUNDLES = (
    CORE_RESOURCE_BUNDLE,
    SYNC_RESOURCE_BUNDLE,
)


def _numbered_manifests(directory: Path) -> dict[str, Path]:
    return {
        path.name: path
        for path in directory.glob("*.json")
        if PAYLOAD_MANIFEST_NAME.fullmatch(path.name)
    }


def _shipped_resource_roots(app_bundle: Path) -> dict[str, Path]:
    return {
        "app": app_bundle / "Contents" / "Resources",
        "MCP helper": (
            app_bundle
            / "Contents"
            / "Helpers"
            / "LorvexMCPHost.app"
            / "Contents"
            / "Resources"
        ),
        "widget extension": (
            app_bundle
            / "Contents"
            / "PlugIns"
            / WIDGET_APPEX_NAME
            / "Contents"
            / "Resources"
        ),
    }


def _payload_manifest_failures(
    app_bundle: Path,
    *,
    authority_dir: Path,
    embedded_dir: Path,
) -> list[str]:
    """Verify every database-writing process carries the exact source contracts."""
    if not authority_dir.is_dir():
        return [f"payload contract authority directory not found: {authority_dir}"]
    if not embedded_dir.is_dir():
        return [f"embedded payload contract directory not found: {embedded_dir}"]

    authority = _numbered_manifests(authority_dir)
    embedded = _numbered_manifests(embedded_dir)
    if not authority:
        return [f"no numbered payload contract manifests found in {authority_dir}"]

    failures: list[str] = []
    for name in sorted(authority.keys() - embedded.keys()):
        failures.append(f"embedded payload contract is missing authority manifest: {name}")
    for name in sorted(embedded.keys() - authority.keys()):
        failures.append(f"embedded payload contract has no authority manifest: {name}")
    for name in sorted(authority.keys() & embedded.keys()):
        if authority[name].read_bytes() != embedded[name].read_bytes():
            failures.append(
                f"embedded payload contract differs from authority: {name}"
            )

    for surface, resources in _shipped_resource_roots(app_bundle).items():
        shipped_bundle = resources / SYNC_RESOURCE_BUNDLE
        if not shipped_bundle.is_dir():
            continue
        shipped_dir = resources / SYNC_RESOURCE_BUNDLE / "SyncPayloadContracts"
        shipped = _numbered_manifests(shipped_dir)
        for name in sorted(shipped.keys() - authority.keys()):
            failures.append(
                f"payload contract manifest in {surface} has no authority manifest: {name}"
            )
        for name, authority_path in sorted(authority.items()):
            shipped_path = shipped.get(name)
            if shipped_path is None:
                failures.append(
                    f"payload contract manifest missing from {surface}: {name}"
                )
            elif shipped_path.read_bytes() != authority_path.read_bytes():
                failures.append(
                    f"payload contract manifest in {surface} differs from authority: {name}"
                )
    return failures


def _core_resource_failures(
    app_bundle: Path,
    *,
    schema_authority_path: Path,
    checksums_authority_path: Path,
) -> list[str]:
    authority_files = {
        "schema.sql": schema_authority_path,
        "checksums.lock": checksums_authority_path,
    }
    failures = [
        f"LorvexCore resource authority file not found: {path}"
        for path in authority_files.values()
        if not path.is_file()
    ]
    for surface, resources in _shipped_resource_roots(app_bundle).items():
        shipped_bundle = resources / CORE_RESOURCE_BUNDLE
        if not shipped_bundle.is_dir():
            continue
        for name, authority_path in authority_files.items():
            shipped_path = shipped_bundle / name
            if not shipped_path.is_file():
                failures.append(f"LorvexCore resource missing from {surface}: {name}")
            elif (
                authority_path.is_file()
                and shipped_path.read_bytes() != authority_path.read_bytes()
            ):
                failures.append(
                    f"LorvexCore resource in {surface} differs from authority: {name}"
                )
    return failures


def resource_bundle_failures(
    app_bundle: Path,
    *,
    authority_dir: Path = PAYLOAD_CONTRACT_AUTHORITY_DIR,
    embedded_dir: Path = PAYLOAD_CONTRACT_EMBEDDED_DIR,
    schema_authority_path: Path = SCHEMA_AUTHORITY_PATH,
    checksums_authority_path: Path = CHECKSUMS_AUTHORITY_PATH,
) -> list[str]:
    resources = app_bundle / "Contents" / "Resources"
    if not app_bundle.is_dir():
        return [f"app bundle not found: {app_bundle}"]
    if not resources.is_dir():
        return [f"app resources directory not found: {resources}"]

    failures: list[str] = []
    bundles = sorted(path for path in resources.glob("*.bundle") if path.is_dir())
    if not bundles:
        failures.append(f"no SwiftPM resource bundles found in {resources}")
        return failures
    for name in REQUIRED_CORE_BUNDLES:
        if not (resources / name).is_dir():
            failures.append(f"required SwiftPM resource bundle missing from app: {name}")

    shipped_roots = _shipped_resource_roots(app_bundle)
    helper_resources = shipped_roots["MCP helper"]
    for name in REQUIRED_CORE_BUNDLES:
        if not (helper_resources / name).is_dir():
            failures.append(f"required SwiftPM resource bundle missing from MCP helper: {name}")

    widget_resources = shipped_roots["widget extension"]
    for name in REQUIRED_CORE_BUNDLES:
        if not (widget_resources / name).is_dir():
            failures.append(
                f"required SwiftPM resource bundle missing from widget extension: {name}"
            )

    failures.extend(
        _payload_manifest_failures(
            app_bundle,
            authority_dir=authority_dir,
            embedded_dir=embedded_dir,
        )
    )
    failures.extend(
        _core_resource_failures(
            app_bundle,
            schema_authority_path=schema_authority_path,
            checksums_authority_path=checksums_authority_path,
        )
    )

    root_bundles = sorted(path for path in app_bundle.glob("*.bundle"))
    if root_bundles:
        failures.append(
            "SwiftPM resource bundles must live in Contents/Resources, not the .app root: "
            f"{[path.name for path in root_bundles]!r}"
        )

    return failures


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} /path/to/Lorvex.app", file=sys.stderr)
        return 2

    failures = resource_bundle_failures(Path(sys.argv[1]))
    if failures:
        for failure in failures:
            print(failure, file=sys.stderr)
        return 1

    print(f"SwiftPM resource bundle verification passed: {sys.argv[1]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
