#!/usr/bin/env python3
"""Verify SwiftPM resource bundles are staged in a valid macOS app layout.

macOS bundles are wrapped: `Contents/Info.plist` beside `Contents/Resources/`.
`swift build` emits the flat iOS shape instead, with the Info.plist and payload
at the bundle root, so the macOS staging rewraps every bundle it copies. This
verifier requires the wrapped result — a flat bundle in the macOS payload is a
regression, not an accepted alternative.
"""

from __future__ import annotations

import plistlib
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
WIDGET_APPEX_NAME = "LorvexWidgets.appex"
REQUIRED_CORE_BUNDLES = (
    CORE_RESOURCE_BUNDLE,
    SYNC_RESOURCE_BUNDLE,
)
# The identity and platform keys Xcode stamps into a macOS resource bundle's
# Info.plist. A SwiftPM package that omits `defaultLocalization` emits no
# Info.plist for its resource bundles at all, leaving a `.bundle` directory that
# is not a valid bundle; App Store Connect rejects the payload for the missing
# CFBundleIdentifier (error 90276). Fixed values are asserted exactly; the rest
# only have to be present and non-empty, since they are derived per bundle. The
# DT* toolchain provenance the staging also stamps is deliberately not asserted:
# its values depend on the build host's Xcode.
REQUIRED_BUNDLE_PLIST_KEYS = (
    "CFBundleIdentifier",
    "CFBundleName",
    "CFBundleDevelopmentRegion",
    "LSMinimumSystemVersion",
)
EXPECTED_BUNDLE_PLIST_VALUES = {
    "CFBundlePackageType": "BNDL",
    "CFBundleInfoDictionaryVersion": "6.0",
    "CFBundleSupportedPlatforms": ["MacOSX"],
}


def _bundle_payload_root(bundle: Path) -> Path:
    """Where a wrapped macOS bundle keeps the files SwiftPM put at its root."""
    return bundle / "Contents" / "Resources"


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
        shipped_dir = _bundle_payload_root(shipped_bundle) / "SyncPayloadContracts"
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
            shipped_path = _bundle_payload_root(shipped_bundle) / name
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


def _bundle_identity_failures(app_bundle: Path) -> list[str]:
    """Assert every staged `*.bundle`, at any depth, is a valid macOS bundle.

    Walks the whole app payload — including the bundles duplicated into the
    widget `.appex` and the MCP helper `.app` — because a resource bundle
    reaches those directories by a copy the app-level staging never re-inspects.
    Requires the wrapped macOS layout: `Contents/Info.plist` beside
    `Contents/Resources/`, with nothing left at the bundle root.
    """
    failures: list[str] = []
    for bundle in sorted(app_bundle.rglob("*.bundle")):
        if not bundle.is_dir():
            continue
        relative = bundle.relative_to(app_bundle)
        if not (bundle / "Contents").is_dir():
            failures.append(
                "staged bundle uses the flat iOS layout, expected a wrapped "
                f"Contents/ directory: {relative}"
            )
            continue
        if not _bundle_payload_root(bundle).is_dir():
            failures.append(
                f"staged bundle has no Contents/Resources directory: {relative}"
            )
        stray = sorted(
            path.name for path in bundle.iterdir() if path.name != "Contents"
        )
        if stray:
            failures.append(
                "staged bundle keeps payload outside Contents/, so it was "
                f"wrapped incompletely: {relative}: {stray!r}"
            )
        plist_path = bundle / "Contents" / "Info.plist"
        if not plist_path.is_file():
            failures.append(f"staged bundle has no Info.plist: {relative}")
            continue
        try:
            info = plistlib.loads(plist_path.read_bytes())
        except Exception as error:
            # Broad on purpose: plistlib surfaces malformed XML, an unsupported
            # binary header, and an unreadable file as unrelated exception
            # types, and every one of them means the same thing here.
            failures.append(
                f"staged bundle Info.plist is unreadable: {relative}: {error}"
            )
            continue
        if not isinstance(info, dict):
            failures.append(f"staged bundle Info.plist is not a dictionary: {relative}")
            continue
        for key in REQUIRED_BUNDLE_PLIST_KEYS:
            value = info.get(key)
            if not isinstance(value, str) or not value:
                failures.append(
                    f"staged bundle Info.plist is missing {key}: {relative}"
                )
        for key, expected in EXPECTED_BUNDLE_PLIST_VALUES.items():
            value = info.get(key)
            if value != expected:
                failures.append(
                    f"staged bundle Info.plist {key} is {value!r}, expected "
                    f"{expected!r}: {relative}"
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
    failures.extend(_bundle_identity_failures(app_bundle))

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
