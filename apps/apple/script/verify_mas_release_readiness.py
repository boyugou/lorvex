#!/usr/bin/env python3
"""Verify the repository-side Mac App Store release gates.

This verifier covers the parts that can be checked without Apple Developer
portal access. It deliberately keeps CloudKit production schema promotion and
App Store Connect provisioning as explicit pending release gates until a human
has completed those account-side actions.
"""

from __future__ import annotations

import plistlib
import sys
from pathlib import Path

from metadata_env import load_metadata
from release_strategy import CLOUDKIT_PRODUCTION_RELEASE_READINESS


ROOT = Path(__file__).resolve().parents[1]
MAS_ENTITLEMENTS = ROOT / "Config" / "LorvexAppleCloudKitAppStore.entitlements"
BASE_ENTITLEMENTS = ROOT / "Config" / "LorvexApple.entitlements"
HELPER_ENTITLEMENTS = ROOT / "Config" / "LorvexMCPHost.entitlements"
ARCHIVE_SCRIPT = ROOT / "script" / "archive_mas.sh"
ENTITLEMENTS_VERIFIER = ROOT / "script" / "verify_codesign_entitlements.py"
PROVISIONING_VERIFIER = ROOT / "script" / "verify_mas_provisioning.py"
DISTRIBUTION_DOC = ROOT / "docs" / "DISTRIBUTION.md"
PACKAGE_LOCAL_SCRIPT = ROOT / "script" / "package_local.sh"
BUILD_AND_RUN_SCRIPT = ROOT / "script" / "build_and_run.sh"
SIGN_APP_BUNDLE_SCRIPT = ROOT / "script" / "sign_app_bundle.sh"


def load_plist(path: Path) -> dict:
    with path.open("rb") as file:
        return plistlib.load(file)


def mas_entitlements_failures(
    entitlements: dict,
    app_group_id: str,
    cloudkit_container_id: str,
) -> list[str]:
    failures: list[str] = []
    app_groups = entitlements.get("com.apple.security.application-groups", [])
    if app_group_id not in app_groups:
        failures.append(f"MAS entitlements missing app group {app_group_id!r}")
    if entitlements.get("com.apple.security.app-sandbox") is not True:
        failures.append("MAS entitlements must enable app sandbox")
    if entitlements.get("com.apple.security.files.user-selected.read-write") is not True:
        failures.append("MAS entitlements missing user-selected read/write access")
    if entitlements.get("com.apple.security.personal-information.calendars") is not True:
        failures.append("MAS entitlements missing Calendar access")

    containers = entitlements.get("com.apple.developer.icloud-container-identifiers", [])
    if cloudkit_container_id not in containers:
        failures.append(
            f"MAS entitlements missing CloudKit container {cloudkit_container_id!r}"
        )
    services = entitlements.get("com.apple.developer.icloud-services", [])
    if "CloudKit" not in services:
        failures.append("MAS entitlements missing CloudKit iCloud service")
    if entitlements.get("com.apple.developer.icloud-container-environment") != "Production":
        failures.append(
            "MAS entitlements must declare com.apple.developer.icloud-container-environment "
            "= 'Production'"
        )
    if entitlements.get("com.apple.developer.aps-environment") != "production":
        failures.append(
            "MAS entitlements must use com.apple.developer.aps-environment 'production'"
        )
    return failures


def helper_entitlements_failures(entitlements: dict, app_group_id: str) -> list[str]:
    """The MCP helper ships a single entitlements file for both dev and MAS
    packaging (Config/LorvexMCPHost.entitlements): the helper serves the
    Lorvex-managed group-container store only, so it must declare exactly
    app-sandbox + the shared app group and nothing else — no iCloud/aps, and no
    user-selected file access (the app owns export/import Open/Save; the helper
    never touches user-selected files)."""
    failures: list[str] = []
    if entitlements.get("com.apple.security.app-sandbox") is not True:
        failures.append("MCP helper entitlements must enable app sandbox")
    app_groups = entitlements.get("com.apple.security.application-groups", [])
    if app_group_id not in app_groups:
        failures.append(f"MCP helper entitlements missing app group {app_group_id!r}")
    allowed_keys = {
        "com.apple.security.app-sandbox",
        "com.apple.security.application-groups",
    }
    unexpected_keys = sorted(set(entitlements) - allowed_keys)
    if unexpected_keys:
        failures.append(
            f"MCP helper entitlements declare unexpected key(s): {unexpected_keys}"
        )
    return failures


def base_entitlements_failures(entitlements: dict) -> list[str]:
    failures: list[str] = []
    forbidden_keys = [
        "com.apple.developer.icloud-container-identifiers",
        "com.apple.developer.icloud-services",
        "com.apple.developer.icloud-container-environment",
        "com.apple.developer.aps-environment",
        # Native macOS entitlements never use the iOS-style bare key either —
        # forbidding it too catches an accidental copy-paste from an iOS
        # entitlements file.
        "aps-environment",
    ]
    for key in forbidden_keys:
        if key in entitlements:
            failures.append(
                f"base macOS entitlements unexpectedly include production-only key {key!r}"
            )
    return failures


def release_readiness_failures(readiness: dict[str, list[str]]) -> list[str]:
    failures: list[str] = []
    expected_ready = {"mas_cloudkit_entitlement_template", "mas_entitlement_verifier"}
    expected_pending = {
        "cloudkit_production_schema_promotion",
        "app_store_connect_provisioning",
    }
    ready = set(readiness.get("ready", []))
    pending = set(readiness.get("pending", []))
    if ready != expected_ready:
        failures.append(f"MAS production release ready gates mismatch: {sorted(ready)!r}")
    if pending != expected_pending:
        failures.append(f"MAS production release pending gates mismatch: {sorted(pending)!r}")
    return failures


def script_and_doc_failures(distribution_text: str, verifier_text: str) -> list[str]:
    failures: list[str] = []
    if not ARCHIVE_SCRIPT.is_file():
        failures.append(f"MAS archive script missing: {ARCHIVE_SCRIPT}")
    elif not ARCHIVE_SCRIPT.stat().st_mode & 0o111:
        failures.append(f"MAS archive script is not executable: {ARCHIVE_SCRIPT}")

    required_verifier_markers = [
        "--require-cloudkit",
        "--require-production-aps",
    ]
    for marker in required_verifier_markers:
        if marker not in verifier_text:
            failures.append(f"codesign entitlement verifier missing MAS marker {marker!r}")

    required_doc_markers = [
        "## 4. macOS - Mac App Store",
        "./script/archive_mas.sh --preflight",
        "./script/archive_mas.sh --package",
        "CloudKit production schema promotion remains a manual release gate",
    ]
    for marker in required_doc_markers:
        if marker not in distribution_text:
            failures.append(f"DISTRIBUTION.md missing MAS release marker: {marker!r}")
    if "TODO: MAS archive script" in distribution_text:
        failures.append("DISTRIBUTION.md still contains the old MAS archive TODO")
    return failures


def release_build_configuration_failures(
    package_local_text: str, build_and_run_text: str
) -> list[str]:
    """The MAS package must ship a Release/-O build. package_local.sh (the
    packaging entry point archive_mas.sh and archive_local.sh both route
    through) forces LORVEX_BUILD_CONFIGURATION=release before staging; a
    Debug/-Onone binary in the .pkg is an App Store hazard on par with a
    missing entitlement."""
    failures: list[str] = []
    if 'LORVEX_BUILD_CONFIGURATION:-release' not in package_local_text:
        failures.append(
            "package_local.sh does not default LORVEX_BUILD_CONFIGURATION to release"
        )
    required_build_and_run_markers = [
        'BUILD_CONFIGURATION="${LORVEX_BUILD_CONFIGURATION:-debug}"',
        'swift build -c "$BUILD_CONFIGURATION"',
        '--show-bin-path',
    ]
    for marker in required_build_and_run_markers:
        if marker not in build_and_run_text:
            failures.append(f"build_and_run.sh missing release-config marker {marker!r}")
    return failures


def provisioning_profile_wiring_failures(
    archive_script_text: str, sign_app_bundle_text: str
) -> list[str]:
    """Assert the provisioning-profile embedding + cross-check pipeline stays
    wired up: archive_mas.sh must run the sibling profile verifier after
    packaging, and sign_app_bundle.sh must still know how to embed a profile
    at the correct Contents/embedded.provisionprofile location."""
    failures: list[str] = []
    if "verify_mas_provisioning.py" not in archive_script_text:
        failures.append("archive_mas.sh does not run verify_mas_provisioning.py")

    required_sign_markers = [
        "APP_PROVISIONING_PROFILE",
        "HELPER_PROVISIONING_PROFILE",
        "WIDGET_PROVISIONING_PROFILE",
        "embedded.provisionprofile",
    ]
    for marker in required_sign_markers:
        if marker not in sign_app_bundle_text:
            failures.append(f"sign_app_bundle.sh missing provisioning-profile marker {marker!r}")
    return failures


def mas_release_readiness_failures(
    metadata: dict[str, str],
    mas_entitlements: dict,
    base_entitlements: dict,
    helper_entitlements: dict,
    distribution_text: str,
    verifier_text: str,
    package_local_text: str,
    build_and_run_text: str,
    archive_script_text: str,
    sign_app_bundle_text: str,
    release_readiness: dict[str, list[str]] = CLOUDKIT_PRODUCTION_RELEASE_READINESS,
) -> list[str]:
    failures: list[str] = []
    failures.extend(
        mas_entitlements_failures(
            mas_entitlements,
            metadata["APP_GROUP_ID"],
            metadata["CLOUDKIT_CONTAINER_ID"],
        )
    )
    failures.extend(base_entitlements_failures(base_entitlements))
    failures.extend(helper_entitlements_failures(helper_entitlements, metadata["APP_GROUP_ID"]))
    failures.extend(release_readiness_failures(release_readiness))
    failures.extend(script_and_doc_failures(distribution_text, verifier_text))
    failures.extend(
        release_build_configuration_failures(package_local_text, build_and_run_text)
    )
    failures.extend(
        provisioning_profile_wiring_failures(archive_script_text, sign_app_bundle_text)
    )
    return failures


def main() -> int:
    missing = [
        path
        for path in [
            MAS_ENTITLEMENTS,
            BASE_ENTITLEMENTS,
            HELPER_ENTITLEMENTS,
            DISTRIBUTION_DOC,
            ENTITLEMENTS_VERIFIER,
            PROVISIONING_VERIFIER,
            PACKAGE_LOCAL_SCRIPT,
            BUILD_AND_RUN_SCRIPT,
            ARCHIVE_SCRIPT,
            SIGN_APP_BUNDLE_SCRIPT,
        ]
        if not path.is_file()
    ]
    if missing:
        print("MAS release readiness verification failed:", file=sys.stderr)
        for path in missing:
            print(f"- required file missing: {path}", file=sys.stderr)
        return 1

    failures = mas_release_readiness_failures(
        load_metadata(),
        load_plist(MAS_ENTITLEMENTS),
        load_plist(BASE_ENTITLEMENTS),
        load_plist(HELPER_ENTITLEMENTS),
        DISTRIBUTION_DOC.read_text(encoding="utf-8"),
        ENTITLEMENTS_VERIFIER.read_text(encoding="utf-8"),
        PACKAGE_LOCAL_SCRIPT.read_text(encoding="utf-8"),
        BUILD_AND_RUN_SCRIPT.read_text(encoding="utf-8"),
        ARCHIVE_SCRIPT.read_text(encoding="utf-8"),
        SIGN_APP_BUNDLE_SCRIPT.read_text(encoding="utf-8"),
    )
    if failures:
        print("MAS release readiness verification failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    print("MAS release readiness verification passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
