#!/usr/bin/env python3
"""Verify the Apple-platform manifest against metadata and local files."""

from __future__ import annotations

import json
import os
import plistlib
import re
import sys
from pathlib import Path

from metadata_env import load_metadata
from quality_gates import quality_gate_failures
from release_strategy import system_intents_platform_metadata


ROOT = Path(__file__).resolve().parents[1]
PACKAGE_PATH = ROOT / "Package.swift"
CORE_PACKAGE_PATH = ROOT / "core" / "Package.swift"
XCODEGEN_SPEC_PATH = ROOT / "Config" / "XcodeGen" / "project.yml"

# The deployment floor is declared in several places that must never drift apart.
# app_metadata.sh (loaded as ``metadata``) is the authority; each platform's
# floor maps to one MIN_*_SYSTEM_VERSION key. verify_app_metadata.py already ties
# that authority to ProductMetadata.swift and the shipped Info.plists;
# deployment_floor_failures() below adds the two SwiftPM manifests and the
# XcodeGen spec, so together the two verifiers pin every location.
PLATFORM_FLOOR_METADATA_KEYS = {
    "macOS": "MIN_SYSTEM_VERSION",
    "iOS": "MIN_MOBILE_SYSTEM_VERSION",
    "visionOS": "MIN_VISION_SYSTEM_VERSION",
    "watchOS": "MIN_WATCH_SYSTEM_VERSION",
}


def require_path(path: str, failures: list[str]) -> None:
    if not Path(path).exists():
        failures.append(f"missing path: {path}")


def read_plist(path: str) -> dict[str, object]:
    with Path(path).open("rb") as file:
        value = plistlib.load(file)
    return value if isinstance(value, dict) else {}


def url_scheme_failures(plist: dict[str, object], expected_scheme: str, label: str) -> list[str]:
    url_types = plist.get("CFBundleURLTypes", [])
    schemes = {
        scheme
        for url_type in url_types
        if isinstance(url_type, dict)
        for scheme in url_type.get("CFBundleURLSchemes", [])
    }
    if expected_scheme in schemes:
        return []
    return [f"{label} Info.plist does not register URL scheme {expected_scheme!r}"]


def concrete_info_plist_failures(
    path: str,
    expected: dict[str, str],
    metadata: dict[str, str],
    label: str,
) -> list[str]:
    plist = read_plist(path)
    expected_values = {
        "CFBundleName": expected["scheme"],
        "CFBundleDisplayName": expected["display_name"],
        "CFBundleIdentifier": expected["bundle_id"],
        "CFBundleShortVersionString": metadata["MARKETING_VERSION"],
        "CFBundleVersion": metadata["BUILD_VERSION"],
        "MinimumOSVersion": expected["minimum_os"],
        "CFBundlePackageType": "APPL",
        "LSApplicationCategoryType": metadata["APP_CATEGORY"],
    }
    failures: list[str] = []
    for key, expected_value in expected_values.items():
        actual = plist.get(key)
        if actual != expected_value:
            failures.append(
                f"{label} Info.plist {key} mismatch: {actual!r} != {expected_value!r}"
            )
    failures.extend(url_scheme_failures(plist, metadata["URL_SCHEME"], label))
    return failures


def ios_live_activity_failures(target: dict[str, object]) -> list[str]:
    """The manifest's live_activities_supported flag must agree with whether
    the iOS Info.plist actually declares NSSupportsLiveActivities=true. Both
    "false in the manifest, key absent/false in the plist" and "true in the
    manifest, key true in the plist" are consistent; anything else means the
    manifest is lying about the feature in one direction or the other.
    """
    manifest_value = target.get("live_activities_supported")
    if not isinstance(manifest_value, bool):
        return ["ios.live_activities_supported must be a boolean"]

    info_plist = target.get("info_plist")
    if not isinstance(info_plist, str):
        return ["ios live activity Info.plist missing"]
    plist = read_plist(info_plist)
    plist_value = plist.get("NSSupportsLiveActivities") is True

    if manifest_value == plist_value:
        return []
    return [
        "ios.live_activities_supported "
        f"({manifest_value!r}) does not match Info.plist NSSupportsLiveActivities "
        f"({plist_value!r})"
    ]


def watch_info_plist_failures(
    path: str,
    expected: dict[str, str],
    companion_bundle_id: str,
) -> list[str]:
    plist = read_plist(path)
    # The watch app ships embedded inside its iOS companion (LorvexMobileApp), so
    # it is a companion — not a standalone watch-only app. Companion apps declare
    # WKWatchOnly=false and name the iOS host via WKCompanionAppBundleIdentifier.
    expected_values = {
        "CFBundleDisplayName": expected["display_name"],
        "CFBundlePackageType": "APPL",
        "WKApplication": True,
        "WKWatchOnly": False,
        "WKCompanionAppBundleIdentifier": companion_bundle_id,
    }
    failures: list[str] = []
    for key, expected_value in expected_values.items():
        actual = plist.get(key)
        if actual != expected_value:
            failures.append(
                f"watchos Info.plist {key} mismatch: {actual!r} != {expected_value!r}"
            )
    return failures


def widget_info_plist_failures(
    path: str,
    expected: dict[str, str],
    metadata: dict[str, str],
) -> list[str]:
    plist = read_plist(path)
    expected_values = {
        "CFBundleName": expected["executable"],
        "CFBundleDisplayName": expected["display_name"],
        "CFBundleExecutable": expected["executable"],
        "CFBundleIdentifier": expected["bundle_id"],
        "CFBundlePackageType": "XPC!",
        "CFBundleShortVersionString": metadata["MARKETING_VERSION"],
        "CFBundleVersion": metadata["BUILD_VERSION"],
    }
    failures: list[str] = []
    for key, expected_value in expected_values.items():
        actual = plist.get(key)
        if actual != expected_value:
            failures.append(
                f"widget Info.plist {key} mismatch: {actual!r} != {expected_value!r}"
            )
    extension = plist.get("NSExtension", {})
    actual_extension_point = (
        extension.get("NSExtensionPointIdentifier") if isinstance(extension, dict) else None
    )
    if actual_extension_point != expected["extension_point"]:
        failures.append(
            "widget Info.plist NSExtensionPointIdentifier mismatch: "
            f"{actual_extension_point!r} != {expected['extension_point']!r}"
        )
    return failures


def watch_complication_info_plist_failures(
    path: str,
    expected: dict[str, str],
    metadata: dict[str, str],
) -> list[str]:
    plist = read_plist(path)
    expected_values = {
        "CFBundleName": expected["swiftpm_product"],
        "CFBundleDisplayName": expected["display_name"],
        "CFBundleExecutable": expected["swiftpm_product"],
        "CFBundleIdentifier": expected["bundle_id"],
        "CFBundlePackageType": "XPC!",
        "CFBundleShortVersionString": metadata["MARKETING_VERSION"],
        "CFBundleVersion": metadata["BUILD_VERSION"],
    }
    failures: list[str] = []
    for key, expected_value in expected_values.items():
        actual = plist.get(key)
        if actual != expected_value:
            failures.append(
                "watch complication Info.plist "
                f"{key} mismatch: {actual!r} != {expected_value!r}"
            )
    extension = plist.get("NSExtension", {})
    actual_extension_point = (
        extension.get("NSExtensionPointIdentifier") if isinstance(extension, dict) else None
    )
    if actual_extension_point != expected["extension_point"]:
        failures.append(
            "watch complication Info.plist NSExtensionPointIdentifier mismatch: "
            f"{actual_extension_point!r} != {expected['extension_point']!r}"
        )
    return failures


def privacy_manifest_failures(path: str, label: str) -> list[str]:
    plist = read_plist(path)
    failures: list[str] = []
    if plist.get("NSPrivacyTracking") is not False:
        failures.append(f"{label} privacy manifest must declare NSPrivacyTracking=false")
    if plist.get("NSPrivacyTrackingDomains") != []:
        failures.append(f"{label} privacy manifest must declare no tracking domains")
    if plist.get("NSPrivacyCollectedDataTypes") != []:
        failures.append(f"{label} privacy manifest must declare no collected data types")

    accessed = plist.get("NSPrivacyAccessedAPITypes")
    if not isinstance(accessed, list):
        failures.append(f"{label} privacy manifest missing NSPrivacyAccessedAPITypes array")
        return failures
    matching = [
        entry for entry in accessed
        if isinstance(entry, dict)
        and entry.get("NSPrivacyAccessedAPIType")
        == "NSPrivacyAccessedAPICategoryUserDefaults"
    ]
    if not matching:
        failures.append(
            f"{label} privacy manifest missing UserDefaults required-reason API declaration"
        )
    elif matching[0].get("NSPrivacyAccessedAPITypeReasons") != ["CA92.1"]:
        failures.append(
            f"{label} privacy manifest UserDefaults reasons mismatch: "
            f"{matching[0].get('NSPrivacyAccessedAPITypeReasons')!r}"
        )
    return failures


def entitlement_failures(path: str, metadata: dict[str, str], label: str) -> list[str]:
    entitlements = read_plist(path)
    groups = entitlements.get("com.apple.security.application-groups", [])
    if metadata["APP_GROUP_ID"] in groups:
        return []
    return [f"{label} entitlements missing app group {metadata['APP_GROUP_ID']!r}"]


def cloudkit_entitlement_failures(path: str, metadata: dict[str, str], label: str) -> list[str]:
    entitlements = read_plist(path)
    failures = entitlement_failures(path, metadata, label)
    containers = entitlements.get("com.apple.developer.icloud-container-identifiers", [])
    services = entitlements.get("com.apple.developer.icloud-services", [])
    if metadata["CLOUDKIT_CONTAINER_ID"] not in containers:
        failures.append(
            f"{label} CloudKit entitlements missing container "
            f"{metadata['CLOUDKIT_CONTAINER_ID']!r}"
        )
    if "CloudKit" not in services:
        failures.append(f"{label} CloudKit entitlements missing CloudKit service")
    return failures


def executable_script_failures(path: str, label: str) -> list[str]:
    script = Path(path)
    if not script.exists():
        return [f"{label} missing: {path}"]
    if not script.is_file():
        return [f"{label} is not a file: {path}"]
    if not os.access(script, os.X_OK):
        return [f"{label} is not executable: {path}"]
    return []


def simulator_manifest_failures(simulators: object) -> list[str]:
    if not isinstance(simulators, dict):
        return [f"simulators mismatch: {simulators!r}"]

    verifier = simulators.get("all_platforms_verifier")
    if not verifier:
        return ["simulators.all_platforms_verifier missing"]

    return executable_script_failures(
        str(verifier),
        "Apple simulator aggregate verifier",
    )


def apple_target_manifest_failures(targets: object, metadata: dict[str, str]) -> list[str]:
    if not isinstance(targets, dict):
        return [f"targets mismatch: {targets!r}"]

    expected_values = {
        "ios": {
            "swiftpm_product": metadata["MOBILE_APP_NAME"],
            "xcodegen_target": metadata["MOBILE_APP_NAME"],
        },
        "visionos": {
            "swiftpm_product": metadata["VISION_APP_NAME"],
            "xcodegen_target": metadata["VISION_APP_NAME"],
        },
        "watchos": {
            "swiftpm_product": metadata["WATCH_APP_NAME"],
            "xcodegen_target": metadata["WATCH_APP_NAME"],
        },
        "watch_complication": {
            "swiftpm_product": metadata["WATCH_COMPLICATION_PRODUCT"],
            "xcodegen_target": metadata["WATCH_COMPLICATION_PRODUCT"],
        },
        "widget": {
            "target": "LorvexFocusWidgetExtension",
            "swiftpm_product": "LorvexWidgetBundle",
            "standalone_swiftpm_product": metadata["WIDGET_EXECUTABLE"],
            "xcodegen_target": "LorvexFocusWidgetExtension",
        },
        "focus_filter": {
            "target": metadata["FOCUS_FILTER_EXECUTABLE"],
            "xcodegen_target": metadata["FOCUS_FILTER_EXECUTABLE"],
        },
    }

    failures: list[str] = []
    for target_name, expected in expected_values.items():
        target = targets.get(target_name)
        if not isinstance(target, dict):
            failures.append(f"{target_name} target metadata mismatch: {target!r}")
            continue
        for key, expected_value in expected.items():
            actual = target.get(key)
            if actual != expected_value:
                failures.append(
                    f"{target_name}.{key} mismatch: {actual!r} != {expected_value!r}"
                )
    return failures


def swiftpm_products(source: str) -> set[str]:
    return set(re.findall(r'\.(?:executable|library)\s*\(\s*name:\s*"([^"]+)"', source))


def swiftpm_platform_floors(source: str) -> dict[str, str]:
    """Map each `platforms:` entry in a Package.swift to a dotted floor string.

    `.macOS(.v15)` → "15.0", `.visionOS(.v2)` → "2.0". Only the major-version
    `.vN` spelling is recognized (the sole form these packages use); a
    `.macOS("15.4")`-style string literal is intentionally not matched, so it
    surfaces as a missing platform rather than a silently-passing floor.
    """
    return {
        platform: f"{major}.0"
        for platform, major in re.findall(
            r"\.(macOS|iOS|visionOS|watchOS)\(\.v(\d+)\)", source
        )
    }


def xcodegen_deployment_targets(source: str) -> dict[str, str]:
    """Parse the XcodeGen spec's top-level `deploymentTarget:` block into
    {platform: version}. The spec pins iOS/visionOS/watchOS only — the macOS app
    is a SwiftPM product built outside this Xcode project.
    """
    block = re.search(
        r"^  deploymentTarget:\n(?P<body>(?:^    .+\n?)+)",
        source,
        flags=re.MULTILINE,
    )
    if block is None:
        return {}
    return {
        platform: version
        for platform, version in re.findall(
            r'^\s{4}(macOS|iOS|visionOS|watchOS):\s*"([^"]+)"',
            block.group("body"),
            flags=re.MULTILINE,
        )
    }


def deployment_floor_failures(
    metadata: dict[str, str],
    *,
    package_source: str,
    core_package_source: str,
    xcodegen_source: str,
) -> list[str]:
    """Assert the deployment floor is identical across every place that encodes
    it, so raising it can't silently leave one location behind.

    ``metadata`` (app_metadata.sh) is the authority. The app and core SwiftPM
    manifests must declare the same per-platform floor through their
    `platforms:` arrays, and the XcodeGen spec's `deploymentTarget:` must agree
    for the three platforms it builds (iOS/visionOS/watchOS). The macOS floor is
    carried by the SwiftPM manifests and metadata only — no XcodeGen entry.
    """
    failures: list[str] = []
    app_floors = swiftpm_platform_floors(package_source)
    core_floors = swiftpm_platform_floors(core_package_source)
    xcode_targets = xcodegen_deployment_targets(xcodegen_source)

    for platform, metadata_key in PLATFORM_FLOOR_METADATA_KEYS.items():
        expected = metadata.get(metadata_key)
        if expected is None:
            failures.append(f"metadata missing {metadata_key}")
            continue

        app_floor = app_floors.get(platform)
        if app_floor != expected:
            failures.append(
                f"Package.swift {platform} floor mismatch: "
                f"{app_floor!r} != {expected!r} ({metadata_key})"
            )
        core_floor = core_floors.get(platform)
        if core_floor != expected:
            failures.append(
                f"core/Package.swift {platform} floor mismatch: "
                f"{core_floor!r} != {expected!r} ({metadata_key})"
            )
        if platform != "macOS":
            xcode_floor = xcode_targets.get(platform)
            if xcode_floor != expected:
                failures.append(
                    f"XcodeGen deploymentTarget {platform} mismatch: "
                    f"{xcode_floor!r} != {expected!r} ({metadata_key})"
                )

    return failures


def xcodegen_targets(source: str) -> set[str]:
    in_targets = False
    targets: set[str] = set()
    for line in source.splitlines():
        if line == "targets:":
            in_targets = True
            continue
        if in_targets and line and not line.startswith(" "):
            break
        if in_targets:
            match = re.match(r"^  ([A-Za-z0-9_]+):\s*$", line)
            if match:
                targets.add(match.group(1))
    return targets


def xcodegen_target_settings(source: str, target_name: str) -> dict[str, str]:
    target_body = xcodegen_target_body(source, target_name)
    if target_body is None:
        return {}
    return {
        key: value.strip().strip('"')
        for key, value in re.findall(
            r"^\s{8}([A-Z0-9_]+):\s*(.+)$",
            target_body,
            flags=re.MULTILINE,
        )
    }


def xcodegen_target_body(source: str, target_name: str) -> str | None:
    target_match = re.search(
        rf"^  {re.escape(target_name)}:\n(?P<body>.*?)(?=^  [A-Za-z0-9_]+:\n|^schemes:|\Z)",
        source,
        flags=re.MULTILINE | re.DOTALL,
    )
    return None if target_match is None else target_match.group("body")


def xcodegen_target_resource_paths(source: str, target_name: str) -> set[str]:
    target_body = xcodegen_target_body(source, target_name)
    if target_body is None:
        return set()

    resource_paths: set[str] = set()
    source_entries = re.finditer(
        r"^\s{6}- path:\s*(?P<path>[^\n]+)\n(?P<body>.*?)(?=^\s{6}- path:|\Z)",
        target_body,
        flags=re.MULTILINE | re.DOTALL,
    )
    for entry in source_entries:
        if re.search(r"^\s{8}buildPhase:\s*resources\s*$", entry.group("body"), re.MULTILINE):
            resource_paths.add(entry.group("path").strip().strip('"'))
    return resource_paths


def xcodegen_target_dependencies(source: str, target_name: str) -> set[str]:
    target_body = xcodegen_target_body(source, target_name)
    if target_body is None:
        return set()

    dependency_match = re.search(
        r"^\s{4}dependencies:\n(?P<body>.*?)(?=^\s{4}[A-Za-z_]+:|\Z)",
        target_body,
        flags=re.MULTILINE | re.DOTALL,
    )
    if dependency_match is None:
        return set()

    return set(re.findall(r"^\s{6}- target:\s*([A-Za-z0-9_]+)\s*$", dependency_match.group("body"), re.MULTILINE))


def xcodegen_dependency_contract_failures(
    targets: object,
    *,
    xcodegen_source: str,
) -> list[str]:
    if not isinstance(targets, dict):
        return [f"targets mismatch: {targets!r}"]

    expected_dependencies = {
        "widget": {"LorvexWidgetIntents"},
    }

    failures: list[str] = []
    for manifest_key, required_dependencies in expected_dependencies.items():
        target = targets.get(manifest_key)
        if not isinstance(target, dict):
            continue
        xcode_target = target.get("xcodegen_target")
        if not isinstance(xcode_target, str):
            continue
        dependencies = xcodegen_target_dependencies(xcodegen_source, xcode_target)
        missing = sorted(required_dependencies - dependencies)
        if missing:
            failures.append(
                f"{manifest_key} XcodeGen dependencies missing target(s): {missing}"
            )
    return failures


def privacy_resource_contract_failures(
    targets: object,
    *,
    xcodegen_source: str,
) -> list[str]:
    if not isinstance(targets, dict):
        return [f"targets mismatch: {targets!r}"]

    failures: list[str] = []
    for manifest_key, target in targets.items():
        if not isinstance(target, dict):
            continue
        privacy_manifest = target.get("privacy_manifest")
        xcode_target = target.get("xcodegen_target")
        if not isinstance(privacy_manifest, str) or not isinstance(xcode_target, str):
            continue
        expected_resource = str(Path(privacy_manifest).relative_to(ROOT))
        resources = xcodegen_target_resource_paths(xcodegen_source, xcode_target)
        if expected_resource not in resources:
            failures.append(
                f"{manifest_key} XcodeGen resources missing privacy manifest: "
                f"{expected_resource!r}"
            )
    return failures


def xcodegen_setting_contract_failures(
    targets: object,
    *,
    xcodegen_source: str,
) -> list[str]:
    if not isinstance(targets, dict):
        return [f"targets mismatch: {targets!r}"]

    expected_by_manifest_key = {
        "ios": {
            "bundle": "bundle_id",
            "info_plist": "info_plist",
            "entitlements": "entitlements",
        },
        "visionos": {
            "bundle": "bundle_id",
            "info_plist": "info_plist",
            "entitlements": "entitlements",
            "product_name": "scheme",
        },
        "watchos": {
            "bundle": "bundle_id",
            "info_plist": "info_plist",
            "entitlements": "entitlements",
            "product_name": "scheme",
        },
        "widget": {
            "bundle": "bundle_id",
            "info_plist": "info_plist",
            "entitlements": "entitlements",
            "product_name": "executable",
        },
        "focus_filter": {
            "bundle": "bundle_id",
            "info_plist": "info_plist",
            "entitlements": "entitlements",
            "product_name": "executable",
        },
        "watch_complication": {
            "bundle": "bundle_id",
            "info_plist": "info_plist",
            "entitlements": "entitlements",
            "product_name": "swiftpm_product",
        },
    }

    failures: list[str] = []
    for manifest_key, expected_keys in expected_by_manifest_key.items():
        target = targets.get(manifest_key)
        if not isinstance(target, dict):
            continue
        xcode_target = target.get("xcodegen_target")
        if not isinstance(xcode_target, str):
            continue
        settings = xcodegen_target_settings(xcodegen_source, xcode_target)
        if not settings:
            failures.append(f"{manifest_key}.xcodegen_target has no XcodeGen settings: {xcode_target!r}")
            continue

        expected_bundle = target.get(expected_keys["bundle"])
        actual_bundle = settings.get("PRODUCT_BUNDLE_IDENTIFIER")
        if expected_bundle is not None and actual_bundle != expected_bundle:
            failures.append(
                f"{manifest_key} XcodeGen PRODUCT_BUNDLE_IDENTIFIER mismatch: "
                f"{actual_bundle!r} != {expected_bundle!r}"
            )

        for setting_key, manifest_path_key in [
            ("INFOPLIST_FILE", expected_keys.get("info_plist")),
            ("CODE_SIGN_ENTITLEMENTS", expected_keys.get("entitlements")),
        ]:
            if manifest_path_key is None:
                continue
            expected_path = target.get(manifest_path_key)
            if not isinstance(expected_path, str):
                continue
            expected_setting = "$(SRCROOT)/../../" + str(Path(expected_path).relative_to(ROOT))
            actual_setting = settings.get(setting_key)
            if actual_setting != expected_setting:
                failures.append(
                    f"{manifest_key} XcodeGen {setting_key} mismatch: "
                    f"{actual_setting!r} != {expected_setting!r}"
                )

        product_manifest_key = expected_keys.get("product_name")
        if product_manifest_key is not None:
            expected_product_name = target.get(product_manifest_key)
            actual_product_name = settings.get("PRODUCT_NAME")
            if actual_product_name != expected_product_name:
                failures.append(
                    f"{manifest_key} XcodeGen PRODUCT_NAME mismatch: "
                    f"{actual_product_name!r} != {expected_product_name!r}"
                )

    return failures


def target_contract_source_failures(
    targets: object,
    *,
    package_source: str,
    xcodegen_source: str,
) -> list[str]:
    if not isinstance(targets, dict):
        return [f"targets mismatch: {targets!r}"]

    products = swiftpm_products(package_source)
    xcode_targets = xcodegen_targets(xcodegen_source)
    failures: list[str] = []

    for target_name, target in targets.items():
        if not isinstance(target, dict):
            continue
        for key in ["swiftpm_product", "standalone_swiftpm_product"]:
            product = target.get(key)
            if isinstance(product, str) and product not in products:
                failures.append(
                    f"{target_name}.{key} is not a Package.swift product: {product!r}"
                )
        for key in ["target", "xcodegen_target"]:
            xcode_target = target.get(key)
            if isinstance(xcode_target, str) and xcode_target not in xcode_targets:
                failures.append(
                    f"{target_name}.{key} is not an XcodeGen target: {xcode_target!r}"
                )

    return failures


def shared_target_contract_source_failures(
    shared_targets: object,
    *,
    package_source: str,
    xcodegen_source: str,
) -> list[str]:
    if not isinstance(shared_targets, dict):
        return [f"shared_targets mismatch: {shared_targets!r}"]

    products = swiftpm_products(package_source)
    xcode_targets = xcodegen_targets(xcodegen_source)
    failures: list[str] = []

    system_intents = shared_targets.get("system_intents")
    if not isinstance(system_intents, dict):
        return [f"shared_targets.system_intents mismatch: {system_intents!r}"]

    swiftpm_product = system_intents.get("swiftpm_product")
    if isinstance(swiftpm_product, str) and swiftpm_product not in products:
        failures.append(
            "system_intents.swiftpm_product is not a Package.swift product: "
            f"{swiftpm_product!r}"
        )

    for key in ["ios_target", "visionos_target"]:
        target = system_intents.get(key)
        if isinstance(target, str) and target not in xcode_targets:
            failures.append(
                f"system_intents.{key} is not an XcodeGen target: {target!r}"
            )

    source_path = system_intents.get("source_path")
    source_directory = Path(source_path) if isinstance(source_path, str) else None
    if source_directory is not None and not source_directory.is_dir():
        failures.append(f"system_intents.source_path is not a directory: {source_path!r}")

    capabilities = system_intents.get("capabilities")
    if not isinstance(capabilities, dict):
        failures.append(f"system_intents.capabilities mismatch: {capabilities!r}")
    else:
        if capabilities.get("shortcuts") != system_intents.get("actions"):
            failures.append(
                "system_intents.capabilities.shortcuts does not match actions: "
                f"{capabilities.get('shortcuts')!r}"
            )
        focus_filter_intent = capabilities.get("focus_filter_intent")
        if focus_filter_intent != "LorvexFocusFilterIntent":
            failures.append(
                "system_intents.capabilities.focus_filter_intent mismatch: "
                f"{focus_filter_intent!r}"
            )
        elif source_directory is not None and source_directory.is_dir():
            focus_filter_source = source_directory / f"{focus_filter_intent}.swift"
            if not focus_filter_source.is_file():
                failures.append(f"focus filter intent source missing: {focus_filter_source}")
            elif f"struct {focus_filter_intent}: SetFocusFilterIntent" not in focus_filter_source.read_text(
                encoding="utf-8"
            ):
                failures.append(
                    f"focus filter intent source does not declare SetFocusFilterIntent: "
                    f"{focus_filter_source}"
                )

    return failures


def companion_prefix_topology_failures(metadata: dict[str, str]) -> list[str]:
    """Assert the embedded Watch app's bundle-ID nesting under the iOS host.

    Apple's embedded-companion rule (TN3157) requires an embedded companion
    watchOS app's bundle ID to be prefixed by its iOS host app's bundle ID, and
    the watch app-extension (complication) to be prefixed by the watch app's.
    A watch app whose ID does not descend from the host fails install and
    submission validation, so this pins the parent/child topology rather than
    only checking that each identifier matches its own pinned literal elsewhere.
    """
    host = metadata["MOBILE_BUNDLE_ID"]
    watch = metadata["WATCH_BUNDLE_ID"]
    complication = metadata["WATCH_COMPLICATION_BUNDLE_ID"]
    failures: list[str] = []
    if not watch.startswith(host + "."):
        failures.append(
            f"WATCH_BUNDLE_ID {watch!r} must be prefixed by iOS host "
            f"{host!r} + '.' (Apple companion-prefix rule, TN3157)"
        )
    if not complication.startswith(watch + "."):
        failures.append(
            f"WATCH_COMPLICATION_BUNDLE_ID {complication!r} must be prefixed by "
            f"watch app {watch!r} + '.' (Apple embedded-extension nesting rule)"
        )
    return failures


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} manifest.json", file=sys.stderr)
        return 2

    metadata = load_metadata()
    manifest_path = Path(sys.argv[1])
    manifest = json.loads(manifest_path.read_text())
    failures: list[str] = []

    # Apple companion-prefix topology (TN3157): the embedded Watch app's bundle
    # ID must descend from the iOS host's, and the complication's from the Watch
    # app's. See companion_prefix_topology_failures.
    failures.extend(companion_prefix_topology_failures(metadata))

    xcodegen = manifest.get("xcodegen", {})
    if xcodegen.get("project_name") != "LorvexAppleNative":
        failures.append("XcodeGen project name mismatch")
    for key in ["spec", "verified_by"]:
        require_path(xcodegen.get(key, ""), failures)
    if xcodegen.get("verified_by"):
        failures.extend(
            executable_script_failures(xcodegen["verified_by"], "XcodeGen verifier")
        )

    failures.extend(simulator_manifest_failures(manifest.get("simulators")))

    expected_targets = {
        "ios": {
            "scheme": metadata["MOBILE_APP_NAME"],
            "bundle_id": metadata["MOBILE_BUNDLE_ID"],
            "display_name": metadata["MOBILE_APP_DISPLAY_NAME"],
            "minimum_os": metadata["MIN_MOBILE_SYSTEM_VERSION"],
        },
        "visionos": {
            "scheme": metadata["VISION_APP_NAME"],
            "bundle_id": metadata["VISION_BUNDLE_ID"],
            "display_name": metadata["VISION_APP_DISPLAY_NAME"],
            "minimum_os": metadata["MIN_VISION_SYSTEM_VERSION"],
        },
        "watchos": {
            "scheme": metadata["WATCH_APP_NAME"],
            "bundle_id": metadata["WATCH_BUNDLE_ID"],
            "display_name": metadata["WATCH_APP_DISPLAY_NAME"],
            "minimum_os": metadata["MIN_WATCH_SYSTEM_VERSION"],
        },
        "watch_complication": {
            "swiftpm_product": metadata["WATCH_COMPLICATION_PRODUCT"],
            "xcodegen_target": metadata["WATCH_COMPLICATION_PRODUCT"],
            "bundle_id": metadata["WATCH_COMPLICATION_BUNDLE_ID"],
            "kind": metadata["WATCH_COMPLICATION_KIND"],
            "display_name": metadata["WATCH_COMPLICATION_DISPLAY_NAME"],
            "extension_point": metadata["WIDGET_EXTENSION_POINT_IDENTIFIER"],
        },
        "widget": {
            "target": "LorvexFocusWidgetExtension",
            "bundle_id": metadata["WIDGET_BUNDLE_ID"],
            "kind": metadata["WIDGET_KIND"],
            "display_name": metadata["WIDGET_DISPLAY_NAME"],
            "executable": metadata["WIDGET_EXECUTABLE"],
            "appex_name": metadata["WIDGET_APPEX_NAME"],
            "extension_point": metadata["WIDGET_EXTENSION_POINT_IDENTIFIER"],
        },
        "focus_filter": {
            "target": metadata["FOCUS_FILTER_EXECUTABLE"],
            "xcodegen_target": metadata["FOCUS_FILTER_EXECUTABLE"],
            "bundle_id": metadata["FOCUS_FILTER_BUNDLE_ID"],
            "executable": metadata["FOCUS_FILTER_EXECUTABLE"],
            "appex_name": metadata["FOCUS_FILTER_APPEX_NAME"],
            "extension_point": metadata[
                "FOCUS_FILTER_EXTENSION_POINT_IDENTIFIER"
            ],
        },
    }

    targets = manifest.get("targets", {})
    failures.extend(apple_target_manifest_failures(targets, metadata))
    failures.extend(
        deployment_floor_failures(
            metadata,
            package_source=PACKAGE_PATH.read_text(encoding="utf-8"),
            core_package_source=CORE_PACKAGE_PATH.read_text(encoding="utf-8"),
            xcodegen_source=XCODEGEN_SPEC_PATH.read_text(encoding="utf-8"),
        )
    )
    failures.extend(
        target_contract_source_failures(
            targets,
            package_source=PACKAGE_PATH.read_text(encoding="utf-8"),
            xcodegen_source=XCODEGEN_SPEC_PATH.read_text(encoding="utf-8"),
        )
    )
    failures.extend(
        xcodegen_setting_contract_failures(
            targets,
            xcodegen_source=XCODEGEN_SPEC_PATH.read_text(encoding="utf-8"),
        )
    )
    failures.extend(
        xcodegen_dependency_contract_failures(
            targets,
            xcodegen_source=XCODEGEN_SPEC_PATH.read_text(encoding="utf-8"),
        )
    )
    failures.extend(
        privacy_resource_contract_failures(
            targets,
            xcodegen_source=XCODEGEN_SPEC_PATH.read_text(encoding="utf-8"),
        )
    )
    for target_name, expected in expected_targets.items():
        target = targets.get(target_name, {})
        for key, value in expected.items():
            if target.get(key) != value:
                failures.append(
                    f"{target_name}.{key} mismatch: {target.get(key)!r} != {value!r}"
                )
        for path_key in [
            "info_plist",
            "privacy_manifest",
            "entitlements",
            "cloudkit_entitlements",
            "simulator_verifier",
        ]:
            if path_key in target:
                require_path(target[path_key], failures)

        if target_name in {"ios", "visionos"} and "info_plist" in target:
            failures.extend(
                concrete_info_plist_failures(
                    target["info_plist"],
                    expected,
                    metadata,
                    target_name,
                )
            )
        if target_name == "ios":
            failures.extend(ios_live_activity_failures(target))
        if target_name == "watchos" and "info_plist" in target:
            failures.extend(
                watch_info_plist_failures(
                    target["info_plist"],
                    expected,
                    metadata["MOBILE_BUNDLE_ID"],
                )
            )
        if target_name == "watch_complication" and "info_plist" in target:
            failures.extend(
                watch_complication_info_plist_failures(
                    target["info_plist"],
                    expected,
                    metadata,
                )
            )
        if target_name == "widget" and "info_plist" in target:
            failures.extend(widget_info_plist_failures(target["info_plist"], expected, metadata))
        if "privacy_manifest" in target:
            failures.extend(privacy_manifest_failures(target["privacy_manifest"], target_name))
        if "entitlements" in target:
            failures.extend(entitlement_failures(target["entitlements"], metadata, target_name))
        if "cloudkit_entitlements" in target:
            failures.extend(
                cloudkit_entitlement_failures(
                    target["cloudkit_entitlements"],
                    metadata,
                    target_name,
                )
            )
        if "simulator_verifier" in target:
            failures.extend(
                executable_script_failures(
                    target["simulator_verifier"],
                    f"{target_name} simulator verifier",
                )
            )

    shared = manifest.get("shared", {})
    expected_shared = {
        "app_group": metadata["APP_GROUP_ID"],
        "cloudkit_container": metadata["CLOUDKIT_CONTAINER_ID"],
        "url_scheme": metadata["URL_SCHEME"],
        "marketing_version": metadata["MARKETING_VERSION"],
        "build_version": metadata["BUILD_VERSION"],
    }
    if shared != expected_shared:
        failures.append(f"shared metadata mismatch: {shared!r}")

    shared_targets = manifest.get("shared_targets", {})
    system_intents = shared_targets.get("system_intents", {})
    expected_system_intents = system_intents_platform_metadata(ROOT)
    if system_intents != expected_system_intents:
        failures.append(f"system intents metadata mismatch: {system_intents!r}")
    if system_intents.get("source_path"):
        require_path(system_intents["source_path"], failures)
    failures.extend(
        shared_target_contract_source_failures(
            shared_targets,
            package_source=PACKAGE_PATH.read_text(encoding="utf-8"),
            xcodegen_source=XCODEGEN_SPEC_PATH.read_text(encoding="utf-8"),
        )
    )

    failures.extend(quality_gate_failures(ROOT, manifest.get("quality_gates")))

    if failures:
        print("Apple platform manifest verification failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    print(f"Apple platform manifest verification passed: {manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
