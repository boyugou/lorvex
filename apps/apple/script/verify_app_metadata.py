#!/usr/bin/env python3
"""Verify that script metadata and Swift app metadata stay in sync."""

from __future__ import annotations

import re
import plistlib
from pathlib import Path

from metadata_env import load_metadata


ROOT = Path(__file__).resolve().parents[1]
SWIFT_METADATA_PATH = ROOT / "Sources" / "LorvexCore" / "Models" / "ProductMetadata.swift"
APP_ENTITLEMENTS_PATH = ROOT / "Config" / "LorvexApple.entitlements"
CLOUDKIT_ENTITLEMENTS_PATH = ROOT / "Config" / "LorvexAppleCloudKit.entitlements"
MOBILE_ENTITLEMENTS_PATH = ROOT / "Config" / "LorvexMobileApp.entitlements"
MOBILE_CLOUDKIT_ENTITLEMENTS_PATH = ROOT / "Config" / "LorvexMobileAppCloudKit.entitlements"
VISION_ENTITLEMENTS_PATH = ROOT / "Config" / "LorvexVisionApp.entitlements"
VISION_CLOUDKIT_ENTITLEMENTS_PATH = ROOT / "Config" / "LorvexVisionAppCloudKit.entitlements"
VISION_CLOUDKIT_APPSTORE_ENTITLEMENTS_PATH = (
    ROOT / "Config" / "LorvexVisionAppCloudKitAppStore.entitlements"
)
WATCH_ENTITLEMENTS_PATH = ROOT / "Config" / "LorvexWatchApp.entitlements"
WATCH_COMPLICATION_ENTITLEMENTS_PATH = ROOT / "Config" / "LorvexWatchComplication.entitlements"
WIDGET_ENTITLEMENTS_PATH = ROOT / "Config" / "LorvexWidgetExtension.entitlements"
CARPLAY_ENTITLEMENTS_PATH = ROOT / "Config" / "LorvexCarPlay.entitlements"
MOBILE_INFO_PLIST_PATH = ROOT / "Config" / "LorvexMobileApp-Info.plist"
VISION_INFO_PLIST_PATH = ROOT / "Config" / "LorvexVisionApp-Info.plist"
WATCH_INFO_PLIST_PATH = ROOT / "Config" / "LorvexWatchApp-Info.plist"
WATCH_COMPLICATION_INFO_PLIST_PATH = ROOT / "Config" / "LorvexWatchComplication-Info.plist"
WIDGET_INFO_PLIST_PATH = ROOT / "Config" / "LorvexWidgetExtension-Info.plist"
MCP_HOST_INFO_PLIST_PATH = ROOT / "Config" / "LorvexMCPHost-Info.plist"
BUILD_AND_RUN_SCRIPT_PATH = ROOT / "script" / "build_and_run.sh"
# Every shipped Info.plist — checked-in static files and the macOS app's
# heredoc-generated plist in build_and_run.sh — must declare this export-
# compliance key. Lorvex only uses SHA-256 hashing (idempotency keys, content
# checksums), which App Store Connect classifies as exempt; without this key
# a submission with no declared exemption blocks on the export-compliance
# questionnaire at every upload.
EXPORT_COMPLIANCE_INFO_PLIST_PATHS = [
    MOBILE_INFO_PLIST_PATH,
    VISION_INFO_PLIST_PATH,
    WATCH_INFO_PLIST_PATH,
    WATCH_COMPLICATION_INFO_PLIST_PATH,
    WIDGET_INFO_PLIST_PATH,
    MCP_HOST_INFO_PLIST_PATH,
]
PRIVACY_MANIFEST_PATH = ROOT / "Config" / "PrivacyInfo.xcprivacy"
MACOS_PRIVACY_MANIFEST_PATH = ROOT / "Sources" / "LorvexApple" / "Resources" / "PrivacyInfo.xcprivacy"
MACOS_ONLY_INTENTS_PATH = ROOT / "Sources" / "LorvexApple" / "Intents"
SYSTEM_INTENTS_PATH = ROOT / "Sources" / "LorvexSystemIntents"
SYSTEM_INTENTS_REQUIRED_FILES = [
    "CaptureLorvexTaskIntent.swift",
    "LorvexShortcutsProvider.swift",
    "LorvexTaskIntentRunner.swift",
]

METADATA_MAP = {
    "APP_NAME": "appName",
    "APP_DISPLAY_NAME": "appDisplayName",
    "MOBILE_APP_NAME": "mobileAppName",
    "MOBILE_APP_DISPLAY_NAME": "mobileAppDisplayName",
    "VISION_APP_NAME": "visionAppName",
    "VISION_APP_DISPLAY_NAME": "visionAppDisplayName",
    "WATCH_APP_NAME": "watchAppName",
    "WATCH_APP_DISPLAY_NAME": "watchAppDisplayName",
    "WATCH_COMPLICATION_PRODUCT": "watchComplicationProduct",
    "WATCH_COMPLICATION_BUNDLE_ID": "watchComplicationBundleIdentifier",
    "WATCH_COMPLICATION_KIND": "watchComplicationKind",
    "WATCH_COMPLICATION_DISPLAY_NAME": "watchComplicationDisplayName",
    "MCP_HOST_PRODUCT": "mcpHostProduct",
    "MCP_HOST_BUNDLE_ID": "mcpHostBundleIdentifier",
    "MCP_SERVER_NAME": "mcpServerName",
    "BUNDLE_ID": "bundleIdentifier",
    "MOBILE_BUNDLE_ID": "mobileBundleIdentifier",
    "VISION_BUNDLE_ID": "visionBundleIdentifier",
    "WATCH_BUNDLE_ID": "watchBundleIdentifier",
    "WIDGET_BUNDLE_ID": "widgetBundleIdentifier",
    "WIDGET_EXECUTABLE": "widgetExecutable",
    "WIDGET_APPEX_NAME": "widgetAppeXName",
    "WIDGET_KIND": "widgetKind",
    "WIDGET_DISPLAY_NAME": "widgetDisplayName",
    "WIDGET_DESCRIPTION": "widgetDescription",
    "WIDGET_EXTENSION_POINT_IDENTIFIER": "widgetExtensionPointIdentifier",
    "CONTROL_WIDGET_KIND": "controlWidgetKind",
    "CONTROL_WIDGET_DISPLAY_NAME": "controlWidgetDisplayName",
    "CONTROL_WIDGET_DESCRIPTION": "controlWidgetDescription",
    "APP_GROUP_ID": "appGroupIdentifier",
    "CLOUDKIT_CONTAINER_ID": "cloudKitContainerIdentifier",
    "MARKETING_VERSION": "marketingVersion",
    "BUILD_VERSION": "buildVersion",
    "MIN_SYSTEM_VERSION": "minimumSystemVersion",
    "MIN_MOBILE_SYSTEM_VERSION": "minimumMobileSystemVersion",
    "MIN_VISION_SYSTEM_VERSION": "minimumVisionSystemVersion",
    "MIN_WATCH_SYSTEM_VERSION": "minimumWatchSystemVersion",
    "URL_SCHEME": "urlScheme",
    "APP_CATEGORY": "appCategory",
    "CALENDAR_WRITE_USAGE_DESCRIPTION": "calendarWriteUsageDescription",
    "CALENDAR_FULL_ACCESS_USAGE_DESCRIPTION": "calendarFullAccessUsageDescription",
}


def load_swift_metadata() -> dict[str, str]:
    source = SWIFT_METADATA_PATH.read_text(encoding="utf-8")
    matches = re.findall(
        r'static\s+let\s+([A-Za-z0-9_]+)\s*=\s*"([^"]*)"',
        source,
    )
    return dict(matches)


def load_entitlements(path: Path) -> dict:
    with path.open("rb") as file:
        return plistlib.load(file)


def display_path(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def verify_entitlements(
    path: Path,
    app_group_id: str | None,
    cloudkit_container_id: str | None,
    requires_cloudkit: bool,
    requires_user_selected_files: bool,
    requires_calendar_access: bool,
    failures: list[str],
    *,
    forbid_aps_environment: bool = False,
) -> None:
    """Validate one checked-in `.entitlements` file against the platform's
    entitlement contract.

    ``forbid_aps_environment`` asserts the file declares no `aps-environment`
    key at all. Use it for targets with no push-notification delivery path
    (visionOS converges via foreground/scene-active polling, not a CloudKit
    push subscription) so an unused push capability can't be silently
    reintroduced — App Store review rejects capabilities without a matching
    implementation."""
    if not path.is_file():
        failures.append(f"missing entitlements file: {path.relative_to(ROOT)}")
        return

    entitlements = load_entitlements(path)
    app_groups = entitlements.get("com.apple.security.application-groups", [])
    if app_group_id not in app_groups:
        failures.append(
            f"{path.relative_to(ROOT)} missing app group {app_group_id!r}: {app_groups!r}"
        )

    if forbid_aps_environment and "aps-environment" in entitlements:
        failures.append(
            f"{display_path(path)} unexpectedly declares aps-environment "
            f"{entitlements['aps-environment']!r}; this target has no push-notification "
            "delivery path and must not request the aps-environment capability"
        )

    if requires_cloudkit:
        containers = entitlements.get("com.apple.developer.icloud-container-identifiers", [])
        services = entitlements.get("com.apple.developer.icloud-services", [])
        if cloudkit_container_id not in containers:
            failures.append(
                f"{path.relative_to(ROOT)} missing CloudKit container "
                f"{cloudkit_container_id!r}: {containers!r}"
            )
        if "CloudKit" not in services:
            failures.append(
                f"{path.relative_to(ROOT)} missing CloudKit service entitlement: {services!r}"
            )

    if requires_user_selected_files:
        if not entitlements.get("com.apple.security.files.user-selected.read-write"):
            failures.append(
                f"{path.relative_to(ROOT)} missing user-selected read/write file entitlement"
            )

    if requires_calendar_access:
        if not entitlements.get("com.apple.security.personal-information.calendars"):
            failures.append(
                f"{path.relative_to(ROOT)} missing Calendar personal-information entitlement"
            )


def verify_carplay_entitlements(path: Path, failures: list[str]) -> None:
    if not path.is_file():
        failures.append(f"missing CarPlay entitlements file: {display_path(path)}")
        return

    entitlements = load_entitlements(path)
    expected_key = "com.apple.developer.carplay-communication"
    if entitlements.get(expected_key) is not True:
        failures.append(f"{display_path(path)} missing {expected_key}")

    stale_keys = sorted(
        key for key in entitlements
        if key.startswith("com.apple.developer.carplay-") and key != expected_key
    )
    if stale_keys:
        failures.append(
            f"{display_path(path)} declares unsupported CarPlay entitlement(s): {stale_keys!r}"
        )


def verify_mobile_carplay_activation_template(path: Path, failures: list[str]) -> None:
    if not path.is_file():
        failures.append(f"missing mobile Info.plist: {display_path(path)}")
        return

    source = path.read_text(encoding="utf-8")
    required_markers = [
        "CarPlay activation template.",
        "<key>CPSupportsTemplateApplicationScene</key>",
        "<key>UIApplicationSceneManifest</key>",
        "<key>CPTemplateApplicationSceneSessionRoleApplication</key>",
        "<string>CPTemplateApplicationScene</string>",
        "<string>LorvexCarPlay.LorvexCarPlaySceneDelegate</string>",
        "Config/LorvexCarPlay.entitlements",
    ]
    for marker in required_markers:
        if marker not in source:
            failures.append(f"{display_path(path)} missing CarPlay activation marker {marker!r}")

    active_keys = [
        "CPSupportsTemplateApplicationScene",
        "CPTemplateApplicationSceneSessionRoleApplication",
        "LorvexCarPlay.LorvexCarPlaySceneDelegate",
    ]
    active_section = re.sub(r"<!--.*?-->", "", source, flags=re.DOTALL)
    active_markers = [marker for marker in active_keys if marker in active_section]
    if active_markers:
        failures.append(
            f"{display_path(path)} has active CarPlay scene keys before provisioning: {active_markers!r}"
        )


def verify_widget_info_plist(
    path: Path,
    metadata: dict[str, str],
    failures: list[str],
) -> None:
    if not path.is_file():
        failures.append(f"missing widget Info.plist: {path.relative_to(ROOT)}")
        return

    with path.open("rb") as file:
        plist = plistlib.load(file)

    expected_values = {
        "CFBundleDisplayName": metadata.get("WIDGET_DISPLAY_NAME"),
        "CFBundleExecutable": metadata.get("WIDGET_EXECUTABLE"),
        "CFBundleIdentifier": metadata.get("WIDGET_BUNDLE_ID"),
        "CFBundlePackageType": "XPC!",
        "CFBundleShortVersionString": metadata.get("MARKETING_VERSION"),
        "CFBundleVersion": metadata.get("BUILD_VERSION"),
    }
    for key, expected in expected_values.items():
        actual = plist.get(key)
        if actual != expected:
            failures.append(
                f"{path.relative_to(ROOT)} {key} mismatch: plist={actual!r} expected={expected!r}"
            )

    extension = plist.get("NSExtension", {})
    extension_point = extension.get("NSExtensionPointIdentifier")
    expected_extension_point = metadata.get("WIDGET_EXTENSION_POINT_IDENTIFIER")
    if extension_point != expected_extension_point:
        failures.append(
            f"{path.relative_to(ROOT)} NSExtensionPointIdentifier mismatch: "
            f"plist={extension_point!r} expected={expected_extension_point!r}"
        )


def verify_mcp_host_info_plist(
    path: Path,
    metadata: dict[str, str],
    failures: list[str],
) -> None:
    if not path.is_file():
        failures.append(f"missing MCP host Info.plist: {path.relative_to(ROOT)}")
        return

    with path.open("rb") as file:
        plist = plistlib.load(file)

    expected_values = {
        "CFBundleDisplayName": "Lorvex MCP Host",
        "CFBundleExecutable": metadata.get("MCP_HOST_PRODUCT"),
        "CFBundleIdentifier": metadata.get("MCP_HOST_BUNDLE_ID"),
        "CFBundleName": metadata.get("MCP_HOST_PRODUCT"),
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": metadata.get("MARKETING_VERSION"),
        "CFBundleVersion": metadata.get("BUILD_VERSION"),
        "LSMinimumSystemVersion": metadata.get("MIN_SYSTEM_VERSION"),
        "LSUIElement": True,
        "LSBackgroundOnly": True,
    }
    for key, expected in expected_values.items():
        actual = plist.get(key)
        if actual != expected:
            failures.append(
                f"{path.relative_to(ROOT)} {key} mismatch: plist={actual!r} expected={expected!r}"
            )


def verify_watch_complication_info_plist(
    path: Path,
    metadata: dict[str, str],
    failures: list[str],
) -> None:
    if not path.is_file():
        failures.append(f"missing watch complication Info.plist: {path.relative_to(ROOT)}")
        return

    with path.open("rb") as file:
        plist = plistlib.load(file)

    expected_values = {
        "CFBundleDisplayName": metadata.get("WATCH_COMPLICATION_DISPLAY_NAME"),
        "CFBundleExecutable": metadata.get("WATCH_COMPLICATION_PRODUCT"),
        "CFBundleIdentifier": metadata.get("WATCH_COMPLICATION_BUNDLE_ID"),
        "CFBundleName": metadata.get("WATCH_COMPLICATION_PRODUCT"),
        "CFBundlePackageType": "XPC!",
        "CFBundleShortVersionString": metadata.get("MARKETING_VERSION"),
        "CFBundleVersion": metadata.get("BUILD_VERSION"),
    }
    for key, expected in expected_values.items():
        actual = plist.get(key)
        if actual != expected:
            failures.append(
                f"{path.relative_to(ROOT)} {key} mismatch: plist={actual!r} expected={expected!r}"
            )

    extension = plist.get("NSExtension", {})
    extension_point = extension.get("NSExtensionPointIdentifier")
    expected_extension_point = metadata.get("WIDGET_EXTENSION_POINT_IDENTIFIER")
    if extension_point != expected_extension_point:
        failures.append(
            f"{path.relative_to(ROOT)} NSExtensionPointIdentifier mismatch: "
            f"plist={extension_point!r} expected={expected_extension_point!r}"
        )


def verify_export_compliance_key(path: Path, failures: list[str]) -> None:
    """Every checked-in Info.plist must declare
    ``ITSAppUsesNonExemptEncryption=false`` — Lorvex only uses exempt SHA-256
    hashing, and an undeclared key blocks App Store Connect uploads on the
    export-compliance questionnaire."""
    if not path.is_file():
        failures.append(f"missing Info.plist for export-compliance check: {display_path(path)}")
        return

    with path.open("rb") as file:
        plist = plistlib.load(file)

    if plist.get("ITSAppUsesNonExemptEncryption") is not False:
        failures.append(
            f"{display_path(path)} must declare ITSAppUsesNonExemptEncryption=false "
            "(Lorvex only uses exempt SHA-256 hashing)"
        )


def verify_macos_export_compliance_marker(path: Path, failures: list[str]) -> None:
    """The macOS app's Info.plist has no checked-in static file — it is
    generated by a heredoc in build_and_run.sh — so its export-compliance
    declaration is asserted against that generator's source text instead of
    a parsed plist."""
    if not path.is_file():
        failures.append(f"missing build_and_run.sh: {display_path(path)}")
        return

    source = path.read_text(encoding="utf-8")
    match = re.search(
        r"<key>ITSAppUsesNonExemptEncryption</key>\s*\n\s*<(true|false)/>",
        source,
    )
    if match is None or match.group(1) != "false":
        failures.append(
            f"{display_path(path)} must set ITSAppUsesNonExemptEncryption to false in the "
            "generated macOS Info.plist heredoc"
        )


def verify_privacy_manifest(path: Path, failures: list[str]) -> None:
    if not path.is_file():
        failures.append(f"missing privacy manifest: {path.relative_to(ROOT)}")
        return

    with path.open("rb") as file:
        plist = plistlib.load(file)

    if plist.get("NSPrivacyTracking") is not False:
        failures.append(f"{path.relative_to(ROOT)} must declare NSPrivacyTracking=false")
    if plist.get("NSPrivacyTrackingDomains") != []:
        failures.append(f"{path.relative_to(ROOT)} must declare no tracking domains")
    if plist.get("NSPrivacyCollectedDataTypes") != []:
        failures.append(f"{path.relative_to(ROOT)} must declare no collected data types")

    accessed_api_types = plist.get("NSPrivacyAccessedAPITypes")
    if not isinstance(accessed_api_types, list):
        failures.append(f"{path.relative_to(ROOT)} missing NSPrivacyAccessedAPITypes array")
        return
    user_defaults = [
        entry for entry in accessed_api_types
        if isinstance(entry, dict)
        and entry.get("NSPrivacyAccessedAPIType")
        == "NSPrivacyAccessedAPICategoryUserDefaults"
    ]
    if not user_defaults:
        failures.append(
            f"{path.relative_to(ROOT)} missing UserDefaults required-reason API declaration"
        )
        return
    reasons = user_defaults[0].get("NSPrivacyAccessedAPITypeReasons")
    if reasons != ["CA92.1"]:
        failures.append(
            f"{path.relative_to(ROOT)} UserDefaults reasons mismatch: {reasons!r}"
        )


def verify_watch_info_plist(
    path: Path,
    metadata: dict[str, str],
    failures: list[str],
) -> None:
    if not path.is_file():
        failures.append(f"missing watch Info.plist: {path.relative_to(ROOT)}")
        return

    with path.open("rb") as file:
        plist = plistlib.load(file)

    expected_values = {
        "CFBundleDisplayName": metadata.get("WATCH_APP_DISPLAY_NAME"),
        "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
        "CFBundleName": "$(PRODUCT_NAME)",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "$(MARKETING_VERSION)",
        "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
        "WKApplication": True,
        # The watch app ships embedded inside its iOS companion (LorvexMobileApp),
        # so it is a companion — not a standalone watch-only app. Companion apps
        # declare WKWatchOnly=false and name the iOS host via
        # WKCompanionAppBundleIdentifier.
        "WKWatchOnly": False,
        "WKCompanionAppBundleIdentifier": metadata.get("MOBILE_BUNDLE_ID"),
    }
    for key, expected in expected_values.items():
        actual = plist.get(key)
        if actual != expected:
            failures.append(
                f"{path.relative_to(ROOT)} {key} mismatch: "
                f"plist={actual!r} expected={expected!r}"
            )


def verify_platform_app_info_plist(
    path: Path,
    metadata: dict[str, str],
    prefix: str,
    failures: list[str],
) -> None:
    if not path.is_file():
        failures.append(f"missing {prefix.lower()} Info.plist: {path.relative_to(ROOT)}")
        return

    with path.open("rb") as file:
        plist = plistlib.load(file)

    expected_values = {
        "CFBundleDisplayName": metadata.get(f"{prefix}_APP_DISPLAY_NAME"),
        "CFBundleIdentifier": metadata.get(f"{prefix}_BUNDLE_ID"),
        "CFBundleName": metadata.get(f"{prefix}_APP_NAME"),
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": metadata.get("MARKETING_VERSION"),
        "CFBundleVersion": metadata.get("BUILD_VERSION"),
        "LSApplicationCategoryType": metadata.get("APP_CATEGORY"),
        "MinimumOSVersion": metadata.get(f"MIN_{prefix}_SYSTEM_VERSION"),
    }
    for key, expected in expected_values.items():
        actual = plist.get(key)
        if actual != expected:
            failures.append(
                f"{path.relative_to(ROOT)} {key} mismatch: "
                f"plist={actual!r} expected={expected!r}"
            )

    url_types = plist.get("CFBundleURLTypes", [])
    schemes: list[str] = []
    for url_type in url_types:
        schemes.extend(url_type.get("CFBundleURLSchemes", []))
    expected_scheme = metadata.get("URL_SCHEME")
    if expected_scheme not in schemes:
        failures.append(
            f"{path.relative_to(ROOT)} missing URL scheme "
            f"{expected_scheme!r}: {schemes!r}"
        )


def verify_system_intents_layout(failures: list[str]) -> None:
    if MACOS_ONLY_INTENTS_PATH.exists():
        failures.append(
            f"{MACOS_ONLY_INTENTS_PATH.relative_to(ROOT)} should not exist; "
            "shared App Intents live in Sources/LorvexSystemIntents"
        )

    if not SYSTEM_INTENTS_PATH.is_dir():
        failures.append(f"missing shared App Intents directory: {SYSTEM_INTENTS_PATH.relative_to(ROOT)}")
        return

    for filename in SYSTEM_INTENTS_REQUIRED_FILES:
        path = SYSTEM_INTENTS_PATH / filename
        if not path.is_file():
            failures.append(f"missing shared App Intents file: {path.relative_to(ROOT)}")


def main() -> int:
    shell_metadata = load_metadata()
    swift_metadata = load_swift_metadata()
    failures: list[str] = []

    for shell_key, swift_key in METADATA_MAP.items():
        shell_value = shell_metadata.get(shell_key)
        swift_value = swift_metadata.get(swift_key)
        if shell_value != swift_value:
            failures.append(
                f"{shell_key}/{swift_key} mismatch: shell={shell_value!r} swift={swift_value!r}"
            )

    verify_entitlements(
        APP_ENTITLEMENTS_PATH,
        shell_metadata.get("APP_GROUP_ID"),
        shell_metadata.get("CLOUDKIT_CONTAINER_ID"),
        False,
        True,
        True,
        failures,
    )
    verify_entitlements(
        CLOUDKIT_ENTITLEMENTS_PATH,
        shell_metadata.get("APP_GROUP_ID"),
        shell_metadata.get("CLOUDKIT_CONTAINER_ID"),
        True,
        True,
        True,
        failures,
    )
    verify_entitlements(
        MOBILE_ENTITLEMENTS_PATH,
        shell_metadata.get("APP_GROUP_ID"),
        shell_metadata.get("CLOUDKIT_CONTAINER_ID"),
        False,
        False,
        False,
        failures,
    )
    verify_entitlements(
        MOBILE_CLOUDKIT_ENTITLEMENTS_PATH,
        shell_metadata.get("APP_GROUP_ID"),
        shell_metadata.get("CLOUDKIT_CONTAINER_ID"),
        True,
        False,
        False,
        failures,
    )
    verify_entitlements(
        VISION_ENTITLEMENTS_PATH,
        shell_metadata.get("APP_GROUP_ID"),
        shell_metadata.get("CLOUDKIT_CONTAINER_ID"),
        False,
        False,
        False,
        failures,
        forbid_aps_environment=True,
    )
    verify_entitlements(
        VISION_CLOUDKIT_ENTITLEMENTS_PATH,
        shell_metadata.get("APP_GROUP_ID"),
        shell_metadata.get("CLOUDKIT_CONTAINER_ID"),
        True,
        False,
        False,
        failures,
        forbid_aps_environment=True,
    )
    verify_entitlements(
        VISION_CLOUDKIT_APPSTORE_ENTITLEMENTS_PATH,
        shell_metadata.get("APP_GROUP_ID"),
        shell_metadata.get("CLOUDKIT_CONTAINER_ID"),
        True,
        False,
        False,
        failures,
        forbid_aps_environment=True,
    )
    verify_entitlements(
        WATCH_ENTITLEMENTS_PATH,
        shell_metadata.get("APP_GROUP_ID"),
        shell_metadata.get("CLOUDKIT_CONTAINER_ID"),
        False,
        False,
        False,
        failures,
    )
    verify_entitlements(
        WATCH_COMPLICATION_ENTITLEMENTS_PATH,
        shell_metadata.get("APP_GROUP_ID"),
        shell_metadata.get("CLOUDKIT_CONTAINER_ID"),
        False,
        False,
        False,
        failures,
    )
    verify_entitlements(
        WIDGET_ENTITLEMENTS_PATH,
        shell_metadata.get("APP_GROUP_ID"),
        shell_metadata.get("CLOUDKIT_CONTAINER_ID"),
        False,
        False,
        False,
        failures,
    )
    verify_carplay_entitlements(CARPLAY_ENTITLEMENTS_PATH, failures)
    verify_mobile_carplay_activation_template(MOBILE_INFO_PLIST_PATH, failures)
    verify_platform_app_info_plist(MOBILE_INFO_PLIST_PATH, shell_metadata, "MOBILE", failures)
    verify_platform_app_info_plist(VISION_INFO_PLIST_PATH, shell_metadata, "VISION", failures)
    verify_watch_info_plist(WATCH_INFO_PLIST_PATH, shell_metadata, failures)
    verify_watch_complication_info_plist(WATCH_COMPLICATION_INFO_PLIST_PATH, shell_metadata, failures)
    verify_widget_info_plist(WIDGET_INFO_PLIST_PATH, shell_metadata, failures)
    verify_mcp_host_info_plist(MCP_HOST_INFO_PLIST_PATH, shell_metadata, failures)
    for info_plist_path in EXPORT_COMPLIANCE_INFO_PLIST_PATHS:
        verify_export_compliance_key(info_plist_path, failures)
    verify_macos_export_compliance_marker(BUILD_AND_RUN_SCRIPT_PATH, failures)
    verify_privacy_manifest(PRIVACY_MANIFEST_PATH, failures)
    verify_privacy_manifest(MACOS_PRIVACY_MANIFEST_PATH, failures)
    if (
        PRIVACY_MANIFEST_PATH.is_file()
        and MACOS_PRIVACY_MANIFEST_PATH.is_file()
        and PRIVACY_MANIFEST_PATH.read_bytes() != MACOS_PRIVACY_MANIFEST_PATH.read_bytes()
    ):
        failures.append("macOS PrivacyInfo.xcprivacy must match Config/PrivacyInfo.xcprivacy")
    verify_system_intents_layout(failures)

    if failures:
        for failure in failures:
            print(failure)
        return 1

    print("App metadata consistency verification passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
