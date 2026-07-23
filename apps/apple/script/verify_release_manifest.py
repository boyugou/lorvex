#!/usr/bin/env python3
"""Verify the Lorvex Apple release manifest matches local artifacts."""

from __future__ import annotations

import hashlib
import json
import os
import plistlib
import sys
import zipfile
from pathlib import Path

from expected_mcp_tools import EXPECTED_MCP_TOOLS
from metadata_env import load_metadata
from quality_gates import quality_gate_failures
from release_strategy import (
    APPLE_RELEASE_STRATEGY,
    CLOUDKIT_PRODUCTION_RELEASE_READINESS,
    CLOUDKIT_SYNC_READINESS,
    SYSTEM_INTENTS_ACTIONS,
    SYSTEM_INTENTS_CAPABILITIES,
    SYSTEM_INTENTS_PRODUCT,
)
from verify_mcp_client_config import mcp_client_config_failures


ROOT = Path(__file__).resolve().parents[1]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def client_config_test_glob_failures(
    root: Path,
    glob_value: object,
    expected: str = "script/test_*.py",
) -> list[str]:
    if glob_value != expected:
        return [f"MCP client config test glob mismatch: {glob_value!r}"]

    test_paths = sorted(root.glob(expected))
    failures: list[str] = []
    if not test_paths:
        failures.append("MCP client config test glob does not match any files")
    for path in test_paths:
        if not path.is_file():
            failures.append(f"MCP client config test glob matched non-file path: {path}")
    return failures


def mcp_client_config_contract_failures(
    config_path: Path,
    app_bundle: Path,
    metadata: dict[str, str],
) -> list[str]:
    if not config_path.is_file():
        return ["MCP client config missing"]
    try:
        config = json.loads(config_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        return [f"MCP client config is not valid JSON: {error}"]
    return [
        f"MCP client config {failure}"
        for failure in mcp_client_config_failures(
            config=config,
            app_bundle=app_bundle,
            metadata=metadata,
        )
    ]


def archive_layout_failures(
    archive_path: Path,
    app_name: str,
    metadata: dict[str, str] | None = None,
) -> list[str]:
    try:
        with zipfile.ZipFile(archive_path) as archive:
            names = archive.namelist()
            infos = archive.infolist()
    except zipfile.BadZipFile as error:
        return [f"archive is not a valid zip file: {error}"]

    failures: list[str] = []
    root_entry = f"{app_name}.app/"
    outside_app_entries = sorted(
        name for name in names
        if name != root_entry and not name.startswith(root_entry)
    )
    if outside_app_entries:
        failures.append(f"archive contains entries outside app bundle: {outside_app_entries}")

    symlink_entries = sorted(
        info.filename
        for info in infos
        if ((info.external_attr >> 16) & 0o170000) == 0o120000
    )
    if symlink_entries:
        failures.append(f"archive contains symlink entry(s): {symlink_entries}")

    apple_double = sorted(name for name in names if Path(name).name.startswith("._"))
    if apple_double:
        failures.append(f"archive contains AppleDouble sidecar file(s): {apple_double}")

    macosx_metadata = sorted(
        name for name in names
        if "__MACOSX" in Path(name).parts
    )
    if macosx_metadata:
        failures.append(f"archive contains __MACOSX metadata entry(s): {macosx_metadata}")

    has_app_root = any(name == root_entry or name.startswith(root_entry) for name in names)
    if not has_app_root:
        failures.append(f"archive does not keep parent app bundle: {root_entry}")

    required_entries = [
        f"{app_name}.app/Contents/MacOS/{app_name}",
        f"{app_name}.app/Contents/Info.plist",
        f"{app_name}.app/Contents/Resources/PrivacyInfo.xcprivacy",
    ]
    executable_entries = [f"{app_name}.app/Contents/MacOS/{app_name}"]
    if metadata is not None:
        widget_appex_name = metadata["WIDGET_APPEX_NAME"]
        widget_executable = metadata["WIDGET_EXECUTABLE"]
        mcp_host_product = metadata["MCP_HOST_PRODUCT"]
        helper_bundle_entry = f"{app_name}.app/Contents/Helpers/{mcp_host_product}.app"
        helper_entry = f"{helper_bundle_entry}/Contents/MacOS/{mcp_host_product}"
        widget_executable_entry = (
            f"{app_name}.app/Contents/PlugIns/{widget_appex_name}/Contents/MacOS/"
            f"{widget_executable}"
        )
        required_entries.extend(
            [
                helper_entry,
                f"{helper_bundle_entry}/Contents/Info.plist",
                widget_executable_entry,
                f"{app_name}.app/Contents/PlugIns/{widget_appex_name}/Contents/Info.plist",
                f"{app_name}.app/Contents/PlugIns/{widget_appex_name}/Contents/Resources/PrivacyInfo.xcprivacy",
            ]
        )
        executable_entries.extend([helper_entry, widget_executable_entry])
    for entry in required_entries:
        if entry not in names:
            failures.append(f"archive missing required entry: {entry}")
    info_by_name = {info.filename: info for info in infos}
    for entry in executable_entries:
        info = info_by_name.get(entry)
        if info is None:
            continue
        mode = (info.external_attr >> 16) & 0o777
        if mode and not mode & 0o111:
            failures.append(f"archive required executable entry is not executable: {entry}")

    return failures


def executable_file_failures(path: Path, label: str) -> list[str]:
    if not path.exists():
        return [f"{label} missing: {path}"]
    if not path.is_file():
        return [f"{label} is not a file: {path}"]
    if not os.access(path, os.X_OK):
        return [f"{label} is not executable: {path}"]
    return []


def regular_file_failures(path: Path, label: str) -> list[str]:
    if not path.exists():
        return [f"{label} missing: {path}"]
    if not path.is_file():
        return [f"{label} is not a file: {path}"]
    return []


def privacy_manifest_failures(path: Path) -> list[str]:
    failures = regular_file_failures(path, "privacy manifest")
    if failures:
        return failures

    with path.open("rb") as file:
        plist = plistlib.load(file)

    if plist.get("NSPrivacyTracking") is not False:
        failures.append("privacy manifest must declare NSPrivacyTracking=false")
    if plist.get("NSPrivacyTrackingDomains") != []:
        failures.append("privacy manifest must declare no tracking domains")
    if plist.get("NSPrivacyCollectedDataTypes") != []:
        failures.append("privacy manifest must declare no collected data types")

    accessed = plist.get("NSPrivacyAccessedAPITypes")
    if not isinstance(accessed, list):
        failures.append("privacy manifest missing NSPrivacyAccessedAPITypes array")
        return failures

    user_defaults = [
        entry for entry in accessed
        if isinstance(entry, dict)
        and entry.get("NSPrivacyAccessedAPIType")
        == "NSPrivacyAccessedAPICategoryUserDefaults"
    ]
    if not user_defaults:
        failures.append("privacy manifest missing UserDefaults required-reason API declaration")
    elif user_defaults[0].get("NSPrivacyAccessedAPITypeReasons") != ["CA92.1"]:
        failures.append(
            "privacy manifest UserDefaults reasons mismatch: "
            f"{user_defaults[0].get('NSPrivacyAccessedAPITypeReasons')!r}"
        )
    return failures


def directory_failures(path: Path, label: str) -> list[str]:
    if not path.exists():
        return [f"{label} missing: {path}"]
    if not path.is_dir():
        return [f"{label} is not a directory: {path}"]
    return []


def symlink_failures(paths: dict[str, Path]) -> list[str]:
    failures: list[str] = []
    for label, path in paths.items():
        if path.is_symlink():
            failures.append(f"{label} must not be a symlink: {path}")
    return failures


def path_containment_failures(parent: Path, children: dict[str, Path]) -> list[str]:
    failures: list[str] = []
    try:
        parent_resolved = parent.resolve(strict=True)
    except FileNotFoundError:
        return []

    for label, child in children.items():
        try:
            child_resolved = child.resolve(strict=True)
        except FileNotFoundError:
            continue
        if child_resolved != parent_resolved and parent_resolved not in child_resolved.parents:
            failures.append(f"{label} must be inside app bundle: {child}")
    return failures


def bundle_layout_failures(expected: dict[str, tuple[Path, Path]]) -> list[str]:
    failures: list[str] = []
    for label, (actual, expected_path) in expected.items():
        if not actual.exists() or not expected_path.exists():
            continue
        try:
            actual_resolved = actual.resolve(strict=True)
            expected_resolved = expected_path.resolve(strict=True)
        except FileNotFoundError:
            continue
        if actual_resolved != expected_resolved:
            failures.append(f"{label} must be packaged at {expected_path}: {actual}")
    return failures


def apple_platform_manifest_failures(section: object) -> list[str]:
    if not isinstance(section, dict):
        return [f"apple_platforms metadata mismatch: {section!r}"]

    failures: list[str] = []
    manifest_path = Path(str(section.get("manifest", "")))
    failures.extend(executable_file_failures(Path(str(section.get("manifest_verifier", ""))), "Apple platform manifest verifier"))
    failures.extend(executable_file_failures(Path(str(section.get("xcodegen_project_verifier", ""))), "XcodeGen project verifier"))

    if not manifest_path.is_file():
        failures.append(f"Apple platform manifest missing: {manifest_path}")
        return failures

    platform_manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    targets = platform_manifest.get("targets", {})
    if not isinstance(targets, dict):
        failures.append(f"Apple platform manifest targets mismatch: {targets!r}")
    else:
        expected_targets = {
            "ios",
            "visionos",
            "watchos",
            "watch_complication",
            "widget",
            "focus_filter",
        }
        missing_targets = sorted(expected_targets - set(targets))
        if missing_targets:
            failures.append(f"Apple platform manifest missing target(s): {missing_targets}")
        ios_target = targets.get("ios")
        if not isinstance(ios_target, dict):
            failures.append(f"Apple platform manifest ios target metadata mismatch: {ios_target!r}")
        elif not isinstance(ios_target.get("live_activities_supported"), bool):
            # Whether the feature is actually enabled (true) or not yet
            # implemented (false) is validated against the iOS Info.plist by
            # verify_apple_platform_manifest.py's plist-consistency check;
            # this only guards that the release manifest carries the field.
            failures.append("Apple platform manifest ios.live_activities_supported must be a boolean")

    shared_targets = platform_manifest.get("shared_targets", {})
    system_intents = shared_targets.get("system_intents") if isinstance(shared_targets, dict) else None
    if not isinstance(system_intents, dict):
        failures.append(f"Apple platform manifest missing system intents metadata: {system_intents!r}")
    elif system_intents.get("swiftpm_product") != SYSTEM_INTENTS_PRODUCT:
        failures.append(
            "Apple platform manifest system intents product mismatch: "
            f"{system_intents.get('swiftpm_product')!r}"
        )
    elif system_intents.get("actions") != SYSTEM_INTENTS_ACTIONS:
        failures.append(
            "Apple platform manifest system intents actions mismatch: "
            f"{system_intents.get('actions')!r}"
        )
    elif system_intents.get("capabilities") != SYSTEM_INTENTS_CAPABILITIES:
        failures.append(
            "Apple platform manifest system intents capabilities mismatch: "
            f"{system_intents.get('capabilities')!r}"
        )

    xcodegen = platform_manifest.get("xcodegen", {})
    if not isinstance(xcodegen, dict) or xcodegen.get("verified_by") != section.get("xcodegen_project_verifier"):
        failures.append("Apple platform manifest XcodeGen verifier does not match release manifest")

    simulators = platform_manifest.get("simulators", {})
    if not isinstance(simulators, dict):
        failures.append(f"Apple platform manifest simulators metadata mismatch: {simulators!r}")
    else:
        failures.extend(
            executable_file_failures(
                Path(str(simulators.get("all_platforms_verifier", ""))),
                "Apple simulator aggregate verifier",
            )
        )

    for failure in quality_gate_failures(ROOT, platform_manifest.get("quality_gates")):
        failures.append(f"Apple platform manifest {failure}")

    return failures


def bundle_artifact_failures(bundle: dict[str, object], metadata: dict[str, str]) -> list[str]:
    failures: list[str] = []
    app_bundle = Path(str(bundle.get("path", "")))
    helper = Path(str(bundle.get("helper", "")))
    widget_extension = Path(str(bundle.get("widget_extension", "")))
    privacy_manifest = Path(str(bundle.get("privacy_manifest", "")))
    widget_privacy_manifest = Path(str(bundle.get("widget_privacy_manifest", "")))
    app_executable = app_bundle / "Contents" / "MacOS" / metadata["APP_NAME"]
    widget_executable = (
        widget_extension / "Contents" / "MacOS" / metadata["WIDGET_EXECUTABLE"]
    )

    failures.extend(directory_failures(app_bundle, "app bundle"))
    failures.extend(executable_file_failures(app_executable, "app executable"))
    failures.extend(executable_file_failures(helper, "MCP helper"))
    failures.extend(directory_failures(widget_extension, "widget extension"))
    failures.extend(executable_file_failures(widget_executable, "widget executable"))
    failures.extend(privacy_manifest_failures(privacy_manifest))
    failures.extend(privacy_manifest_failures(widget_privacy_manifest))
    failures.extend(
        symlink_failures(
            {
                "MCP helper": helper,
                "app executable": app_executable,
                "widget extension": widget_extension,
                "widget executable": widget_executable,
                "privacy manifest": privacy_manifest,
                "widget privacy manifest": widget_privacy_manifest,
            }
        )
    )
    failures.extend(
        path_containment_failures(
            app_bundle,
            {
                "MCP helper": helper,
                "widget extension": widget_extension,
                "widget executable": widget_executable,
                "privacy manifest": privacy_manifest,
                "widget privacy manifest": widget_privacy_manifest,
            },
        )
    )
    failures.extend(
        bundle_layout_failures(
            {
                "MCP helper": (
                    helper,
                    app_bundle
                    / "Contents"
                    / "Helpers"
                    / f"{metadata['MCP_HOST_PRODUCT']}.app"
                    / "Contents"
                    / "MacOS"
                    / metadata["MCP_HOST_PRODUCT"],
                ),
                "app executable": (
                    app_executable,
                    app_bundle / "Contents" / "MacOS" / metadata["APP_NAME"],
                ),
                "privacy manifest": (
                    privacy_manifest,
                    app_bundle / "Contents" / "Resources" / "PrivacyInfo.xcprivacy",
                ),
                "widget extension": (
                    widget_extension,
                    app_bundle / "Contents" / "PlugIns" / metadata["WIDGET_APPEX_NAME"],
                ),
                "widget executable": (
                    widget_executable,
                    app_bundle
                    / "Contents"
                    / "PlugIns"
                    / metadata["WIDGET_APPEX_NAME"]
                    / "Contents"
                    / "MacOS"
                    / metadata["WIDGET_EXECUTABLE"],
                ),
                "widget privacy manifest": (
                    widget_privacy_manifest,
                    app_bundle
                    / "Contents"
                    / "PlugIns"
                    / metadata["WIDGET_APPEX_NAME"]
                    / "Contents"
                    / "Resources"
                    / "PrivacyInfo.xcprivacy",
                ),
            },
        )
    )
    return failures


def bundle_info_plist_failures(bundle_path: Path, metadata: dict[str, str]) -> list[str]:
    info_plist = bundle_path / "Contents" / "Info.plist"
    if not info_plist.is_file():
        return [f"app Info.plist missing: {info_plist}"]

    with info_plist.open("rb") as file:
        plist = plistlib.load(file)

    expected_values = {
        "CFBundleName": metadata["APP_DISPLAY_NAME"],
        "CFBundleDisplayName": metadata["APP_DISPLAY_NAME"],
        "CFBundleIdentifier": metadata["BUNDLE_ID"],
        "CFBundleExecutable": metadata["APP_NAME"],
        "CFBundleShortVersionString": metadata["MARKETING_VERSION"],
        "CFBundleVersion": metadata["BUILD_VERSION"],
        "LSMinimumSystemVersion": metadata["MIN_SYSTEM_VERSION"],
        "CFBundlePackageType": "APPL",
        "LSApplicationCategoryType": metadata["APP_CATEGORY"],
        "NSCalendarsWriteOnlyAccessUsageDescription": metadata[
            "CALENDAR_WRITE_USAGE_DESCRIPTION"
        ],
        "NSCalendarsFullAccessUsageDescription": metadata[
            "CALENDAR_FULL_ACCESS_USAGE_DESCRIPTION"
        ],
    }
    failures: list[str] = []
    for key, expected in expected_values.items():
        actual = plist.get(key)
        if actual != expected:
            failures.append(f"Info.plist {key} mismatch: expected {expected!r}, got {actual!r}")

    url_types = plist.get("CFBundleURLTypes", [])
    schemes = {
        scheme
        for url_type in url_types
        if isinstance(url_type, dict)
        for scheme in url_type.get("CFBundleURLSchemes", [])
    }
    if metadata["URL_SCHEME"] not in schemes:
        failures.append(f"Info.plist does not register URL scheme {metadata['URL_SCHEME']!r}")

    expected_activities = [
        "com.lorvex.apple.openTask",
        "com.lorvex.apple.openDestination",
        "com.lorvex.apple.openList",
    ]
    if plist.get("NSUserActivityTypes") != expected_activities:
        failures.append(
            "Info.plist NSUserActivityTypes mismatch: "
            f"expected {expected_activities!r}, got {plist.get('NSUserActivityTypes')!r}"
        )

    return failures


def widget_info_plist_failures(widget_extension_path: Path, metadata: dict[str, str]) -> list[str]:
    info_plist = widget_extension_path / "Contents" / "Info.plist"
    if not info_plist.is_file():
        return [f"widget Info.plist missing: {info_plist}"]

    with info_plist.open("rb") as file:
        plist = plistlib.load(file)

    expected_values = {
        "CFBundleName": metadata["WIDGET_EXECUTABLE"],
        "CFBundleDisplayName": metadata["WIDGET_DISPLAY_NAME"],
        "CFBundleIdentifier": metadata["WIDGET_BUNDLE_ID"],
        "CFBundleExecutable": metadata["WIDGET_EXECUTABLE"],
        "CFBundleShortVersionString": metadata["MARKETING_VERSION"],
        "CFBundleVersion": metadata["BUILD_VERSION"],
        "CFBundlePackageType": "XPC!",
    }
    failures: list[str] = []
    for key, expected in expected_values.items():
        actual = plist.get(key)
        if actual != expected:
            failures.append(f"widget Info.plist {key} mismatch: expected {expected!r}, got {actual!r}")

    extension = plist.get("NSExtension")
    extension_point = extension.get("NSExtensionPointIdentifier") if isinstance(extension, dict) else None
    expected_extension_point = metadata["WIDGET_EXTENSION_POINT_IDENTIFIER"]
    if extension_point != expected_extension_point:
        failures.append(
            "widget Info.plist NSExtensionPointIdentifier mismatch: "
            f"expected {expected_extension_point!r}, got {extension_point!r}"
        )

    return failures


def integration_metadata_failures(integrations: object, metadata: dict[str, str]) -> list[str]:
    expected_integrations = {
        "app_group": metadata["APP_GROUP_ID"],
        "cloudkit_container": metadata["CLOUDKIT_CONTAINER_ID"],
        "cloudkit_sync_readiness": CLOUDKIT_SYNC_READINESS,
        "cloudkit_production_release_readiness": CLOUDKIT_PRODUCTION_RELEASE_READINESS,
        "system_intents_product": SYSTEM_INTENTS_PRODUCT,
        "system_intents_actions": SYSTEM_INTENTS_ACTIONS,
        "system_intents_capabilities": SYSTEM_INTENTS_CAPABILITIES,
        "widget_bundle_id": metadata["WIDGET_BUNDLE_ID"],
        "widget_kind": metadata["WIDGET_KIND"],
        "control_widget_kind": metadata["CONTROL_WIDGET_KIND"],
        "control_widget_display_name": metadata["CONTROL_WIDGET_DISPLAY_NAME"],
        "control_widget_description": metadata["CONTROL_WIDGET_DESCRIPTION"],
    }
    if integrations != expected_integrations:
        return [f"integration metadata mismatch: {integrations!r}"]
    return []


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} manifest.json", file=sys.stderr)
        return 2

    manifest_path = Path(sys.argv[1])
    manifest = json.loads(manifest_path.read_text())
    metadata = load_metadata()
    failures: list[str] = []

    expected_app = {
        "name": metadata["APP_NAME"],
        "display_name": metadata["APP_DISPLAY_NAME"],
        "bundle_id": metadata["BUNDLE_ID"],
        "version": metadata["MARKETING_VERSION"],
        "build": metadata["BUILD_VERSION"],
        "minimum_macos": metadata["MIN_SYSTEM_VERSION"],
        "url_scheme": metadata["URL_SCHEME"],
    }
    if manifest.get("app") != expected_app:
        failures.append(f"app metadata mismatch: {manifest.get('app')!r}")

    archive = Path(manifest.get("archive", {}).get("path", ""))
    if not archive.is_file():
        failures.append(f"archive missing: {archive}")
    else:
        if manifest["archive"].get("size_bytes") != archive.stat().st_size:
            failures.append("archive size does not match manifest")
        if manifest["archive"].get("sha256") != sha256(archive):
            failures.append("archive sha256 does not match manifest")
        failures.extend(archive_layout_failures(archive, metadata["APP_NAME"], metadata))

    bundle = manifest.get("bundle", {})
    failures.extend(bundle_artifact_failures(bundle, metadata))
    bundle_path = Path(str(bundle.get("path", "")))
    if bundle_path.is_dir():
        failures.extend(bundle_info_plist_failures(bundle_path, metadata))
    widget_extension_path = Path(str(bundle.get("widget_extension", "")))
    if widget_extension_path.is_dir():
        failures.extend(widget_info_plist_failures(widget_extension_path, metadata))

    mcp = manifest.get("mcp", {})
    if mcp.get("server_name") != metadata["MCP_SERVER_NAME"]:
        failures.append("MCP server name mismatch")
    if mcp.get("host_product") != metadata["MCP_HOST_PRODUCT"]:
        failures.append("MCP host product mismatch")
    if set(mcp.get("database_environment_keys", [])) != {
        "LORVEX_APPLE_DB_PATH",
    }:
        failures.append("MCP database environment keys mismatch")
    failures.extend(
        mcp_client_config_contract_failures(
            Path(str(mcp.get("client_config", ""))),
            bundle_path,
            metadata,
        )
    )
    if mcp.get("tool_count") != len(EXPECTED_MCP_TOOLS):
        failures.append(f"MCP tool count mismatch: {mcp.get('tool_count')!r}")
    for key in [
        "expected_tools_source",
        "catalog_verifier",
        "client_config_generator",
        "client_config_verifier",
    ]:
        if not Path(mcp.get(key, "")).is_file():
            failures.append(f"MCP {key} missing: {mcp.get(key)!r}")
    failures.extend(client_config_test_glob_failures(ROOT, mcp.get("client_config_test_glob")))

    failures.extend(integration_metadata_failures(manifest.get("integrations", {}), metadata))

    failures.extend(apple_platform_manifest_failures(manifest.get("apple_platforms")))

    failures.extend(quality_gate_failures(ROOT, manifest.get("quality_gates")))

    if manifest.get("strategy") != APPLE_RELEASE_STRATEGY:
        failures.append(f"strategy metadata mismatch: {manifest.get('strategy')!r}")

    if failures:
        print("Release manifest verification failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    print(f"Release manifest verification passed: {manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
