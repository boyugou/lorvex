#!/usr/bin/env python3
"""Generate a manifest for Apple-platform targets beyond the macOS archive."""

from __future__ import annotations

import json
from pathlib import Path

from metadata_env import load_metadata
from quality_gates import quality_gate_manifest
from release_strategy import system_intents_platform_metadata


ROOT = Path(__file__).resolve().parents[1]
OUTPUT_PATH = ROOT / "dist" / "lorvex-apple-platform-manifest.json"


def main() -> int:
    metadata = load_metadata()
    manifest = {
        "xcodegen": {
            "spec": str(ROOT / "Config" / "XcodeGen" / "project.yml"),
            "project_name": "LorvexAppleNative",
            "verified_by": str(ROOT / "script" / "verify_xcodegen_project.sh"),
        },
        "simulators": {
            "all_platforms_verifier": str(ROOT / "script" / "verify_apple_simulators.sh"),
        },
        "targets": {
            "ios": {
                "scheme": metadata["MOBILE_APP_NAME"],
                "swiftpm_product": metadata["MOBILE_APP_NAME"],
                "xcodegen_target": metadata["MOBILE_APP_NAME"],
                "bundle_id": metadata["MOBILE_BUNDLE_ID"],
                "display_name": metadata["MOBILE_APP_DISPLAY_NAME"],
                "minimum_os": metadata["MIN_MOBILE_SYSTEM_VERSION"],
                "info_plist": str(ROOT / "Config" / "LorvexMobileApp-Info.plist"),
                "privacy_manifest": str(ROOT / "Config" / "PrivacyInfo.xcprivacy"),
                "entitlements": str(ROOT / "Config" / "LorvexMobileApp.entitlements"),
                "cloudkit_entitlements": str(
                    ROOT / "Config" / "LorvexMobileAppCloudKit.entitlements"
                ),
                "live_activities_supported": False,
                "simulator_verifier": str(ROOT / "script" / "verify_mobile_simulator.sh"),
            },
            "visionos": {
                "scheme": metadata["VISION_APP_NAME"],
                "swiftpm_product": metadata["VISION_APP_NAME"],
                "xcodegen_target": metadata["VISION_APP_NAME"],
                "bundle_id": metadata["VISION_BUNDLE_ID"],
                "display_name": metadata["VISION_APP_DISPLAY_NAME"],
                "minimum_os": metadata["MIN_VISION_SYSTEM_VERSION"],
                "info_plist": str(ROOT / "Config" / "LorvexVisionApp-Info.plist"),
                "privacy_manifest": str(ROOT / "Config" / "PrivacyInfo.xcprivacy"),
                "entitlements": str(ROOT / "Config" / "LorvexVisionApp.entitlements"),
                "cloudkit_entitlements": str(
                    ROOT / "Config" / "LorvexVisionAppCloudKit.entitlements"
                ),
                "simulator_verifier": str(ROOT / "script" / "verify_vision_simulator.sh"),
            },
            "watchos": {
                "scheme": metadata["WATCH_APP_NAME"],
                "swiftpm_product": metadata["WATCH_APP_NAME"],
                "xcodegen_target": metadata["WATCH_APP_NAME"],
                "bundle_id": metadata["WATCH_BUNDLE_ID"],
                "display_name": metadata["WATCH_APP_DISPLAY_NAME"],
                "minimum_os": metadata["MIN_WATCH_SYSTEM_VERSION"],
                "info_plist": str(ROOT / "Config" / "LorvexWatchApp-Info.plist"),
                "privacy_manifest": str(ROOT / "Config" / "PrivacyInfo.xcprivacy"),
                "entitlements": str(ROOT / "Config" / "LorvexWatchApp.entitlements"),
                "simulator_verifier": str(ROOT / "script" / "verify_watch_simulator.sh"),
            },
            "watch_complication": {
                "swiftpm_product": metadata["WATCH_COMPLICATION_PRODUCT"],
                "xcodegen_target": metadata["WATCH_COMPLICATION_PRODUCT"],
                "bundle_id": metadata["WATCH_COMPLICATION_BUNDLE_ID"],
                "kind": metadata["WATCH_COMPLICATION_KIND"],
                "display_name": metadata["WATCH_COMPLICATION_DISPLAY_NAME"],
                "info_plist": str(
                    ROOT / "Config" / "LorvexWatchComplication-Info.plist"
                ),
                "privacy_manifest": str(ROOT / "Config" / "PrivacyInfo.xcprivacy"),
                "entitlements": str(
                    ROOT / "Config" / "LorvexWatchComplication.entitlements"
                ),
                "extension_point": metadata["WIDGET_EXTENSION_POINT_IDENTIFIER"],
            },
            "widget": {
                "target": "LorvexFocusWidgetExtension",
                "swiftpm_product": "LorvexWidgetBundle",
                "standalone_swiftpm_product": metadata["WIDGET_EXECUTABLE"],
                "xcodegen_target": "LorvexFocusWidgetExtension",
                "bundle_id": metadata["WIDGET_BUNDLE_ID"],
                "kind": metadata["WIDGET_KIND"],
                "display_name": metadata["WIDGET_DISPLAY_NAME"],
                "executable": metadata["WIDGET_EXECUTABLE"],
                "appex_name": metadata["WIDGET_APPEX_NAME"],
                "info_plist": str(ROOT / "Config" / "LorvexWidgetExtension-Info.plist"),
                "privacy_manifest": str(ROOT / "Config" / "PrivacyInfo.xcprivacy"),
                "entitlements": str(ROOT / "Config" / "LorvexFocusWidgetExtension.entitlements"),
                "extension_point": metadata["WIDGET_EXTENSION_POINT_IDENTIFIER"],
            },
            "focus_filter": {
                "target": metadata["FOCUS_FILTER_EXECUTABLE"],
                "xcodegen_target": metadata["FOCUS_FILTER_EXECUTABLE"],
                "bundle_id": metadata["FOCUS_FILTER_BUNDLE_ID"],
                "executable": metadata["FOCUS_FILTER_EXECUTABLE"],
                "appex_name": metadata["FOCUS_FILTER_APPEX_NAME"],
                "info_plist": str(
                    ROOT / "Config" / "LorvexFocusFilterExtension-Info.plist"
                ),
                "privacy_manifest": str(ROOT / "Config" / "PrivacyInfo.xcprivacy"),
                "entitlements": str(
                    ROOT / "Config" / "LorvexFocusFilterExtension.entitlements"
                ),
                "extension_point": metadata[
                    "FOCUS_FILTER_EXTENSION_POINT_IDENTIFIER"
                ],
            },
        },
        "shared_targets": {
            "system_intents": system_intents_platform_metadata(ROOT),
        },
        "shared": {
            "app_group": metadata["APP_GROUP_ID"],
            "cloudkit_container": metadata["CLOUDKIT_CONTAINER_ID"],
            "url_scheme": metadata["URL_SCHEME"],
            "marketing_version": metadata["MARKETING_VERSION"],
            "build_version": metadata["BUILD_VERSION"],
        },
        "quality_gates": quality_gate_manifest(ROOT),
    }

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(f"Apple platform manifest written: {OUTPUT_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
