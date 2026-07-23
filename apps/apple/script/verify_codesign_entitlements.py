#!/usr/bin/env python3
"""Verify signed app entitlements used by Apple platform integrations.

Checks the top-level app bundle for required entitlements (app group,
user-selected file read/write) and, when present,
extends the same checks to the MCP helper and embedded widget extension. When a code-
signing identity is configured (via the ``CODE_SIGN_IDENTITY`` environment
variable), the signing authority is asserted to be non-ad-hoc: the hardened
runtime flag must be set and a ``TeamIdentifier`` other than ``not set``
must be present.

The CloudKit container entitlement is asserted against
``CLOUDKIT_CONTAINER_ID`` from ``app_metadata.sh`` whenever the entitlement
is present on the bundle. MAS/live-sync callers can require the CloudKit
service, matching container, and production APS entitlement explicitly.

The MCP helper must ship as a bundle (``Contents/Helpers/<product>.app``)
with its own ``CFBundleIdentifier``, not a bare Mach-O — a bare executable
has no Info.plist, so the sandbox cannot initialize a container for it. Its
entitlements must include ``com.apple.security.app-sandbox`` and the shared
app group. For identity-signed bundles this verifier also walks every
Mach-O *executable* (not shared libraries) under the bundle and asserts none
of them lack the sandbox entitlement — the Mac App Store requires every
executable in the bundle to be sandboxed.
"""

from __future__ import annotations

import argparse
import os
import plistlib
import re
import subprocess
import sys
from pathlib import Path

from metadata_env import load_metadata


ROOT = Path(__file__).resolve().parents[1]


def signed_entitlements(bundle: Path) -> dict:
    output = subprocess.check_output(
        ["codesign", "-d", "--entitlements", ":-", str(bundle)],
        stderr=subprocess.DEVNULL,
    )
    if not output.strip():
        return {}
    return plistlib.loads(output)


def codesign_details(bundle: Path) -> str:
    result = subprocess.run(
        ["codesign", "-dvvv", str(bundle)],
        capture_output=True,
        text=True,
    )
    # codesign writes details to stderr.
    return (result.stdout or "") + (result.stderr or "")


def check_core_entitlements(label: str, entitlements: dict, app_group_id: str) -> list[str]:
    failures: list[str] = []
    app_groups = entitlements.get("com.apple.security.application-groups", [])
    if app_group_id not in app_groups:
        failures.append(
            f"{label} is missing app group {app_group_id!r}: {app_groups!r}"
        )
    return failures


def check_sandbox_entitlement(label: str, entitlements: dict) -> list[str]:
    if entitlements.get("com.apple.security.app-sandbox") is not True:
        return [f"{label} is missing the app-sandbox entitlement"]
    return []


def helper_bundle_identifier_failures(plist: dict, expected_bundle_id: str) -> list[str]:
    actual = plist.get("CFBundleIdentifier")
    if actual != expected_bundle_id:
        return [
            f"MCP helper Info.plist CFBundleIdentifier mismatch: "
            f"expected {expected_bundle_id!r}, got {actual!r}"
        ]
    return []


def non_sandboxed_executable_failures(
    executables: list[Path],
    entitlements_by_path: dict[Path, dict],
) -> list[str]:
    """Pure decision core for the "zero non-sandboxed executables" MAS gate.

    ``executables`` is every Mach-O *executable* (not a dylib/shared library —
    those run inside their host process's sandbox and carry no entitlements of
    their own) found under the signed bundle. ``entitlements_by_path`` is each
    executable's own signed entitlements dict (empty if unreadable)."""
    failures: list[str] = []
    for path in executables:
        entitlements = entitlements_by_path.get(path, {})
        if entitlements.get("com.apple.security.app-sandbox") is not True:
            failures.append(f"non-sandboxed executable in signed bundle: {path}")
    return failures


def macho_executable_files(app_bundle: Path) -> list[Path]:
    executables: list[Path] = []
    for path in sorted(app_bundle.rglob("*")):
        if not path.is_file() or not os.access(path, os.X_OK):
            continue
        try:
            output = subprocess.check_output(
                ["file", "-b", str(path)], stderr=subprocess.DEVNULL, text=True
            )
        except subprocess.CalledProcessError:
            continue
        if "Mach-O" in output and "executable" in output:
            executables.append(path)
    return executables


def zero_non_sandboxed_executables_failures(app_bundle: Path) -> list[str]:
    executables = macho_executable_files(app_bundle)
    entitlements_by_path: dict[Path, dict] = {}
    for executable in executables:
        try:
            entitlements_by_path[executable] = signed_entitlements(executable)
        except subprocess.CalledProcessError:
            entitlements_by_path[executable] = {}
    return non_sandboxed_executable_failures(executables, entitlements_by_path)


def check_cloudkit_entitlements(
    label: str,
    entitlements: dict,
    cloudkit_container_id: str,
    require_cloudkit: bool,
    require_production_aps: bool,
) -> list[str]:
    failures: list[str] = []
    cloudkit_ids = entitlements.get("com.apple.developer.icloud-container-identifiers")
    cloudkit_services = entitlements.get("com.apple.developer.icloud-services")

    if require_cloudkit and not cloudkit_ids:
        failures.append(f"{label} is missing CloudKit container entitlement")
    if cloudkit_ids is not None:
        if not cloudkit_container_id:
            failures.append(
                "CLOUDKIT_CONTAINER_ID is empty in app_metadata.sh but entitlement is present"
            )
        elif cloudkit_container_id not in cloudkit_ids:
            failures.append(
                f"{label} CloudKit container entitlement {cloudkit_ids!r} does not include "
                f"{cloudkit_container_id!r}"
            )

    if require_cloudkit and not cloudkit_services:
        failures.append(f"{label} is missing iCloud services entitlement")
    if cloudkit_services is not None and "CloudKit" not in cloudkit_services:
        failures.append(
            f"{label} iCloud services entitlement {cloudkit_services!r} does not include "
            "'CloudKit'"
        )

    aps_environment = entitlements.get("com.apple.developer.aps-environment")
    if require_production_aps and aps_environment != "production":
        failures.append(
            f"{label} must use com.apple.developer.aps-environment 'production' for "
            f"MAS live sync, got {aps_environment!r}"
        )

    return failures


def is_local_signature(details: str) -> bool:
    """True for ad-hoc or local-identity signatures (no team identifier) —
    the signer deliberately omits entitlement files for these, so entitlement
    assertions only apply to real-identity bundles."""
    return bool(
        re.search(r"^Signature=adhoc$", details, flags=re.MULTILINE)
        or re.search(r"^TeamIdentifier=not set$", details, flags=re.MULTILINE)
    )


def check_developer_id_signature_details(details: str) -> list[str]:
    failures: list[str] = []
    flags_match = re.search(r"(?:^|\s)flags=([^\s]+)", details, flags=re.MULTILINE)
    flags_value = flags_match.group(1) if flags_match else ""
    if "runtime" not in flags_value:
        failures.append(
            f"signed app is not hardened (flags={flags_value!r}); CODE_SIGN_IDENTITY is set"
        )
    team_match = re.search(r"^TeamIdentifier=(.*)$", details, flags=re.MULTILINE)
    team_value = team_match.group(1).strip() if team_match else ""
    if not team_value or team_value.lower() == "not set":
        failures.append(
            "signed app has no TeamIdentifier (ad-hoc signature) but CODE_SIGN_IDENTITY is set"
        )
    return failures


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Verify signed app entitlements used by Apple platform integrations."
    )
    parser.add_argument("app_bundle", type=Path)
    parser.add_argument(
        "--require-cloudkit",
        action="store_true",
        help="require CloudKit service and container entitlements on the app bundle",
    )
    parser.add_argument(
        "--require-production-aps",
        action="store_true",
        help="require com.apple.developer.aps-environment=production on the app bundle",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    app_bundle = args.app_bundle
    metadata = load_metadata()
    app_group_id = metadata["APP_GROUP_ID"]
    cloudkit_container_id = metadata.get("CLOUDKIT_CONTAINER_ID", "")
    widget_appex_name = metadata.get("WIDGET_APPEX_NAME", "")
    mcp_host_product = metadata.get("MCP_HOST_PRODUCT", "")
    code_sign_identity = os.environ.get("CODE_SIGN_IDENTITY", "").strip()

    # Ad-hoc / local-identity signatures cannot carry a stable App Group:
    # sign_app_bundle.sh deliberately omits the entitlement files for them.
    # Asserting entitlements would fail every local development gate for a
    # condition the signer itself documents as expected, so the check applies
    # only when a real signing identity is in play (CODE_SIGN_IDENTITY set,
    # or the bundle carries a team identifier).
    details = codesign_details(app_bundle)
    if is_local_signature(details) and not code_sign_identity:
        print(
            "Skipping entitlement verification for ad-hoc/local-identity package "
            "(no stable App Group without a real signing identity)"
        )
        return 0

    entitlements = signed_entitlements(app_bundle)
    failures: list[str] = []
    failures.extend(check_core_entitlements("signed app", entitlements, app_group_id))

    if not entitlements.get("com.apple.security.files.user-selected.read-write"):
        failures.append("signed app is missing user-selected read/write file entitlement")
    if not entitlements.get("com.apple.security.personal-information.calendars"):
        failures.append("signed app is missing Calendar personal-information entitlement")

    failures.extend(
        check_cloudkit_entitlements(
            "signed app",
            entitlements,
            cloudkit_container_id,
            require_cloudkit=args.require_cloudkit,
            require_production_aps=args.require_production_aps,
        )
    )

    widget_path: Path | None = None
    if widget_appex_name:
        candidate = app_bundle / "Contents" / "PlugIns" / widget_appex_name
        if candidate.is_dir():
            widget_path = candidate

    if widget_path is not None:
        try:
            widget_entitlements = signed_entitlements(widget_path)
        except subprocess.CalledProcessError:
            widget_entitlements = None
        if widget_entitlements is None:
            failures.append(f"could not read entitlements for embedded widget {widget_path}")
        else:
            widget_groups = widget_entitlements.get(
                "com.apple.security.application-groups", []
            )
            if app_group_id not in widget_groups:
                failures.append(
                    f"embedded widget is missing app group {app_group_id!r}: "
                    f"{widget_groups!r}"
                )

    mcp_host_bundle_id = metadata.get("MCP_HOST_BUNDLE_ID", "")
    helper_bundle: Path | None = None
    if mcp_host_product:
        candidate = app_bundle / "Contents" / "Helpers" / f"{mcp_host_product}.app"
        if candidate.is_dir():
            helper_bundle = candidate
        else:
            failures.append(f"MCP helper bundle is missing from signed app bundle: {candidate}")

    if helper_bundle is not None:
        helper_info_plist = helper_bundle / "Contents" / "Info.plist"
        if not helper_info_plist.is_file():
            failures.append(f"MCP helper bundle is missing Info.plist: {helper_info_plist}")
        else:
            with helper_info_plist.open("rb") as file:
                helper_plist = plistlib.load(file)
            failures.extend(helper_bundle_identifier_failures(helper_plist, mcp_host_bundle_id))

        try:
            helper_entitlements = signed_entitlements(helper_bundle)
        except subprocess.CalledProcessError:
            helper_entitlements = None
        if helper_entitlements is None:
            failures.append(f"could not read entitlements for MCP helper {helper_bundle}")
        else:
            failures.extend(
                check_core_entitlements("MCP helper", helper_entitlements, app_group_id)
            )
            failures.extend(check_sandbox_entitlement("MCP helper", helper_entitlements))
        if code_sign_identity:
            failures.extend(check_developer_id_signature_details(codesign_details(helper_bundle)))

    if code_sign_identity:
        failures.extend(check_developer_id_signature_details(details))
        # The Mac App Store requires every executable in the bundle to be
        # sandboxed. This only applies to identity-signed bundles: ad-hoc
        # signatures already returned early above with no entitlements at all.
        failures.extend(zero_non_sandboxed_executables_failures(app_bundle))

    if failures:
        for message in failures:
            print(message, file=sys.stderr)
        return 1

    print(f"Signed app entitlements verification passed: {app_bundle}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
