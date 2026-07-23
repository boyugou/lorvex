#!/usr/bin/env python3
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from verify_apple_platform_manifest import (
    apple_target_manifest_failures,
    cloudkit_entitlement_failures,
    companion_prefix_topology_failures,
    concrete_info_plist_failures,
    deployment_floor_failures,
    entitlement_failures,
    executable_script_failures,
    ios_live_activity_failures,
    privacy_resource_contract_failures,
    shared_target_contract_source_failures,
    simulator_manifest_failures,
    swiftpm_products,
    target_contract_source_failures,
    watch_info_plist_failures,
    widget_info_plist_failures,
    xcodegen_target_resource_paths,
    xcodegen_setting_contract_failures,
    xcodegen_target_settings,
    xcodegen_dependency_contract_failures,
    xcodegen_target_dependencies,
    xcodegen_targets,
)


TEST_METADATA = {
    "APP_CATEGORY": "public.app-category.productivity",
    "APP_GROUP_ID": "group.com.lorvex.apple",
    "BUILD_VERSION": "1",
    "CLOUDKIT_CONTAINER_ID": "iCloud.com.lorvex.apple",
    "MARKETING_VERSION": "0.1.0",
    "MOBILE_APP_NAME": "LorvexMobileApp",
    "VISION_APP_NAME": "LorvexVisionApp",
    "WATCH_APP_NAME": "LorvexWatchApp",
    "WATCH_COMPLICATION_PRODUCT": "LorvexWatchComplication",
    "WATCH_COMPLICATION_BUNDLE_ID": "com.lorvex.apple.mobile.watchkitapp.widgets",
    "WATCH_COMPLICATION_KIND": "com.lorvex.apple.mobile.watchkitapp.widgets.focus",
    "WATCH_COMPLICATION_DISPLAY_NAME": "Lorvex Focus",
    "WIDGET_EXECUTABLE": "LorvexFocusWidget",
    "FOCUS_FILTER_EXECUTABLE": "LorvexFocusFilterExtension",
    "URL_SCHEME": "lorvex",
    "CALENDAR_WRITE_USAGE_DESCRIPTION": "Lorvex can add planning blocks you create to Apple Calendar.",
    "CALENDAR_FULL_ACCESS_USAGE_DESCRIPTION": "Lorvex can read event details to build schedules and assistant context.",
}


class VerifyApplePlatformManifestTests(unittest.TestCase):
    def test_apple_target_manifest_failures_accepts_platform_target_contract(self) -> None:
        targets = {
            "ios": {
                "swiftpm_product": "LorvexMobileApp",
                "xcodegen_target": "LorvexMobileApp",
                "live_activities_supported": True,
            },
            "visionos": {
                "swiftpm_product": "LorvexVisionApp",
                "xcodegen_target": "LorvexVisionApp",
            },
            "watchos": {
                "swiftpm_product": "LorvexWatchApp",
                "xcodegen_target": "LorvexWatchApp",
            },
            "watch_complication": {
                "swiftpm_product": "LorvexWatchComplication",
                "xcodegen_target": "LorvexWatchComplication",
            },
            "widget": {
                "target": "LorvexFocusWidgetExtension",
                "swiftpm_product": "LorvexWidgetBundle",
                "standalone_swiftpm_product": "LorvexFocusWidget",
                "xcodegen_target": "LorvexFocusWidgetExtension",
            },
            "focus_filter": {
                "target": "LorvexFocusFilterExtension",
                "xcodegen_target": "LorvexFocusFilterExtension",
            },
        }

        self.assertEqual(apple_target_manifest_failures(targets, TEST_METADATA), [])

    def test_apple_target_manifest_failures_rejects_drifted_products(self) -> None:
        targets = {
            "ios": {
                "swiftpm_product": "WrongMobile",
                "xcodegen_target": "LorvexMobileApp",
            },
            "visionos": {
                "swiftpm_product": "WrongVisionProduct",
                "xcodegen_target": "WrongVision",
            },
            "watchos": {
                "swiftpm_product": "LorvexWatchApp",
                "xcodegen_target": "LorvexWatchApp",
            },
            "watch_complication": {
                "swiftpm_product": "WrongComplication",
                "xcodegen_target": "WrongComplicationTarget",
            },
            "widget": {
                "target": "LorvexFocusWidgetExtension",
                "swiftpm_product": "LorvexWidgetBundle",
                "standalone_swiftpm_product": "WrongWidget",
                "xcodegen_target": "LorvexFocusWidgetExtension",
            },
            "focus_filter": {
                "target": "LorvexFocusFilterExtension",
                "xcodegen_target": "LorvexFocusFilterExtension",
            },
        }

        self.assertEqual(
            apple_target_manifest_failures(targets, TEST_METADATA),
            [
                "ios.swiftpm_product mismatch: 'WrongMobile' != 'LorvexMobileApp'",
                "visionos.swiftpm_product mismatch: 'WrongVisionProduct' != 'LorvexVisionApp'",
                "visionos.xcodegen_target mismatch: 'WrongVision' != 'LorvexVisionApp'",
                "watch_complication.swiftpm_product mismatch: "
                "'WrongComplication' != 'LorvexWatchComplication'",
                "watch_complication.xcodegen_target mismatch: "
                "'WrongComplicationTarget' != 'LorvexWatchComplication'",
                "widget.standalone_swiftpm_product mismatch: 'WrongWidget' != 'LorvexFocusWidget'",
            ],
        )

    def test_companion_prefix_topology_accepts_nested_watch_ids(self) -> None:
        # Apple's embedded-companion rule (TN3157): watch id descends from the
        # iOS host, complication id descends from the watch app.
        metadata = {
            "MOBILE_BUNDLE_ID": "com.lorvex.apple.mobile",
            "WATCH_BUNDLE_ID": "com.lorvex.apple.mobile.watchkitapp",
            "WATCH_COMPLICATION_BUNDLE_ID": "com.lorvex.apple.mobile.watchkitapp.widgets",
        }

        self.assertEqual(companion_prefix_topology_failures(metadata), [])

    def test_companion_prefix_topology_rejects_unprefixed_watch_and_complication(self) -> None:
        metadata = {
            "MOBILE_BUNDLE_ID": "com.lorvex.apple.mobile",
            # Not prefixed by the host, and the complication is not prefixed by
            # this (broken) watch id either — both edges of the topology fail.
            "WATCH_BUNDLE_ID": "com.lorvex.apple.watch",
            "WATCH_COMPLICATION_BUNDLE_ID": "com.lorvex.apple.mobile.watchkitapp.widgets",
        }

        failures = companion_prefix_topology_failures(metadata)

        self.assertEqual(len(failures), 2)
        self.assertIn("WATCH_BUNDLE_ID", failures[0])
        self.assertIn("WATCH_COMPLICATION_BUNDLE_ID", failures[1])

    def test_swiftpm_products_extracts_library_and_executable_names(self) -> None:
        source = """
        .library(name: "LorvexCore", targets: ["LorvexCore"]),
        .executable(name: "LorvexMobileApp", targets: ["LorvexMobileApp"]),
        """

        self.assertEqual(swiftpm_products(source), {"LorvexCore", "LorvexMobileApp"})

    def test_xcodegen_targets_extracts_only_target_section_names(self) -> None:
        source = """
name: LorvexAppleNative
targets:
  LorvexMobileApp:
    type: application
  LorvexVisionApp:
    type: application
schemes:
  LorvexMobileApp:
    build:
"""

        self.assertEqual(xcodegen_targets(source), {"LorvexMobileApp", "LorvexVisionApp"})

    def test_xcodegen_target_settings_extracts_base_settings(self) -> None:
        source = """
targets:
  LorvexVisionApp:
    type: application
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.lorvex.apple.vision
        PRODUCT_NAME: LorvexVisionApp
        CODE_SIGN_ENTITLEMENTS: $(SRCROOT)/../../Config/LorvexVisionApp.entitlements
        INFOPLIST_FILE: $(SRCROOT)/../../Config/LorvexVisionApp-Info.plist
schemes:
"""

        self.assertEqual(
            xcodegen_target_settings(source, "LorvexVisionApp"),
            {
                "PRODUCT_BUNDLE_IDENTIFIER": "com.lorvex.apple.vision",
                "PRODUCT_NAME": "LorvexVisionApp",
                "CODE_SIGN_ENTITLEMENTS": "$(SRCROOT)/../../Config/LorvexVisionApp.entitlements",
                "INFOPLIST_FILE": "$(SRCROOT)/../../Config/LorvexVisionApp-Info.plist",
            },
        )

    def test_xcodegen_target_resource_paths_extracts_resource_phase_sources(self) -> None:
        source = """
targets:
  LorvexMobileApp:
    sources:
      - path: Sources/LorvexMobileApp
      - path: Config/PrivacyInfo.xcprivacy
        buildPhase: resources
      - path: Sources/LorvexCore
  LorvexVisionApp:
    sources:
      - path: Config/Other.xcprivacy
        buildPhase: resources
"""

        self.assertEqual(
            xcodegen_target_resource_paths(source, "LorvexMobileApp"),
            {"Config/PrivacyInfo.xcprivacy"},
        )

    def test_xcodegen_target_dependencies_extracts_target_dependencies(self) -> None:
        source = """
targets:
  LorvexFocusWidgetExtension:
    dependencies:
      - target: LorvexWidgetIntents
      - target: LorvexCore
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.lorvex.apple.widget.focus
"""

        self.assertEqual(
            xcodegen_target_dependencies(source, "LorvexFocusWidgetExtension"),
            {"LorvexWidgetIntents", "LorvexCore"},
        )

    def test_xcodegen_dependency_contract_failures_requires_widget_intents(self) -> None:
        targets = {
            "widget": {
                "xcodegen_target": "LorvexFocusWidgetExtension",
            }
        }
        source = """
targets:
  LorvexFocusWidgetExtension:
    dependencies:
      - target: LorvexCore
"""

        self.assertEqual(
            xcodegen_dependency_contract_failures(targets, xcodegen_source=source),
            ["widget XcodeGen dependencies missing target(s): ['LorvexWidgetIntents']"],
        )

    def test_privacy_resource_contract_failures_accepts_matching_xcodegen_resource(self) -> None:
        root = Path(__file__).resolve().parents[1]
        targets = {
            "ios": {
                "xcodegen_target": "LorvexMobileApp",
                "privacy_manifest": str(root / "Config" / "PrivacyInfo.xcprivacy"),
            }
        }
        source = """
targets:
  LorvexMobileApp:
    sources:
      - path: Sources/LorvexMobileApp
      - path: Config/PrivacyInfo.xcprivacy
        buildPhase: resources
"""

        self.assertEqual(
            privacy_resource_contract_failures(targets, xcodegen_source=source),
            [],
        )

    def test_privacy_resource_contract_failures_rejects_missing_resource_phase(self) -> None:
        root = Path(__file__).resolve().parents[1]
        targets = {
            "ios": {
                "xcodegen_target": "LorvexMobileApp",
                "privacy_manifest": str(root / "Config" / "PrivacyInfo.xcprivacy"),
            },
            "visionos": {
                "xcodegen_target": "LorvexVisionApp",
                "privacy_manifest": str(root / "Config" / "PrivacyInfo.xcprivacy"),
            },
        }
        source = """
targets:
  LorvexMobileApp:
    sources:
      - path: Sources/LorvexMobileApp
      - path: Config/PrivacyInfo.xcprivacy
  LorvexVisionApp:
    sources:
      - path: Config/WrongPrivacyInfo.xcprivacy
        buildPhase: resources
"""

        self.assertEqual(
            privacy_resource_contract_failures(targets, xcodegen_source=source),
            [
                "ios XcodeGen resources missing privacy manifest: "
                "'Config/PrivacyInfo.xcprivacy'",
                "visionos XcodeGen resources missing privacy manifest: "
                "'Config/PrivacyInfo.xcprivacy'",
            ],
        )

    def test_xcodegen_setting_contract_failures_accepts_matching_app_targets(self) -> None:
        root = Path(__file__).resolve().parents[1]
        targets = {
            "ios": {
                "xcodegen_target": "LorvexMobileApp",
                "bundle_id": "com.lorvex.apple.mobile",
                "info_plist": str(root / "Config" / "LorvexMobileApp-Info.plist"),
                "entitlements": str(root / "Config" / "LorvexMobileApp.entitlements"),
            },
            "visionos": {
                "xcodegen_target": "LorvexVisionApp",
                "bundle_id": "com.lorvex.apple.vision",
                "scheme": "LorvexVisionApp",
                "info_plist": str(root / "Config" / "LorvexVisionApp-Info.plist"),
                "entitlements": str(root / "Config" / "LorvexVisionApp.entitlements"),
            },
            "watch_complication": {
                "xcodegen_target": "LorvexWatchComplication",
                "bundle_id": "com.lorvex.apple.mobile.watchkitapp.widgets",
                "swiftpm_product": "LorvexWatchComplication",
            },
        }
        source = """
targets:
  LorvexMobileApp:
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.lorvex.apple.mobile
        CODE_SIGN_ENTITLEMENTS: $(SRCROOT)/../../Config/LorvexMobileApp.entitlements
        INFOPLIST_FILE: $(SRCROOT)/../../Config/LorvexMobileApp-Info.plist
  LorvexVisionApp:
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.lorvex.apple.vision
        PRODUCT_NAME: LorvexVisionApp
        CODE_SIGN_ENTITLEMENTS: $(SRCROOT)/../../Config/LorvexVisionApp.entitlements
        INFOPLIST_FILE: $(SRCROOT)/../../Config/LorvexVisionApp-Info.plist
  LorvexWatchComplication:
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.lorvex.apple.mobile.watchkitapp.widgets
        PRODUCT_NAME: LorvexWatchComplication
schemes:
"""

        self.assertEqual(
            xcodegen_setting_contract_failures(targets, xcodegen_source=source),
            [],
        )

    def test_xcodegen_setting_contract_failures_rejects_drifted_settings(self) -> None:
        root = Path(__file__).resolve().parents[1]
        targets = {
            "visionos": {
                "xcodegen_target": "LorvexVisionApp",
                "bundle_id": "com.lorvex.apple.vision",
                "scheme": "LorvexVisionApp",
                "info_plist": str(root / "Config" / "LorvexVisionApp-Info.plist"),
                "entitlements": str(root / "Config" / "LorvexVisionApp.entitlements"),
            }
        }
        source = """
targets:
  LorvexVisionApp:
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: wrong.bundle
        PRODUCT_NAME: WrongName
        CODE_SIGN_ENTITLEMENTS: $(SRCROOT)/../../Config/Wrong.entitlements
        INFOPLIST_FILE: $(SRCROOT)/../../Config/Wrong-Info.plist
schemes:
"""

        self.assertEqual(
            xcodegen_setting_contract_failures(targets, xcodegen_source=source),
            [
                "visionos XcodeGen PRODUCT_BUNDLE_IDENTIFIER mismatch: "
                "'wrong.bundle' != 'com.lorvex.apple.vision'",
                "visionos XcodeGen INFOPLIST_FILE mismatch: "
                "'$(SRCROOT)/../../Config/Wrong-Info.plist' != "
                "'$(SRCROOT)/../../Config/LorvexVisionApp-Info.plist'",
                "visionos XcodeGen CODE_SIGN_ENTITLEMENTS mismatch: "
                "'$(SRCROOT)/../../Config/Wrong.entitlements' != "
                "'$(SRCROOT)/../../Config/LorvexVisionApp.entitlements'",
                "visionos XcodeGen PRODUCT_NAME mismatch: 'WrongName' != 'LorvexVisionApp'",
            ],
        )

    def test_target_contract_source_failures_rejects_missing_package_and_xcode_targets(self) -> None:
        targets = {
            "ios": {
                "swiftpm_product": "LorvexMobileApp",
                "xcodegen_target": "MissingMobileTarget",
            },
            "widget": {
                "target": "LorvexFocusWidgetExtension",
                "swiftpm_product": "MissingWidgetProduct",
                "standalone_swiftpm_product": "LorvexFocusWidget",
                "xcodegen_target": "LorvexFocusWidgetExtension",
            },
        }
        package_source = """
        .executable(name: "LorvexMobileApp", targets: ["LorvexMobileApp"]),
        .executable(name: "LorvexFocusWidget", targets: ["LorvexFocusWidget"]),
        """
        xcodegen_source = """
targets:
  LorvexMobileApp:
    type: application
  LorvexFocusWidgetExtension:
    type: app-extension
"""

        self.assertEqual(
            target_contract_source_failures(
                targets,
                package_source=package_source,
                xcodegen_source=xcodegen_source,
            ),
            [
                "ios.xcodegen_target is not an XcodeGen target: 'MissingMobileTarget'",
                "widget.swiftpm_product is not a Package.swift product: 'MissingWidgetProduct'",
            ],
        )

    def test_shared_target_contract_source_failures_accepts_system_intents_targets(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source_path = Path(directory) / "LorvexSystemIntents"
            source_path.mkdir()
            (source_path / "LorvexFocusFilterIntent.swift").write_text(
                "public struct LorvexFocusFilterIntent: SetFocusFilterIntent {}",
                encoding="utf-8",
            )
            shared_targets = {
                "system_intents": {
                    "swiftpm_product": "LorvexSystemIntents",
                    "ios_target": "LorvexSystemIntents",
                    "visionos_target": "LorvexSystemIntentsVision",
                    "source_path": str(source_path),
                    "actions": ["capture_task"],
                    "capabilities": {
                        "shortcuts": ["capture_task"],
                        "focus_filter_intent": "LorvexFocusFilterIntent",
                    },
                }
            }
            package_source = '.library(name: "LorvexSystemIntents", targets: ["LorvexSystemIntents"])'
            xcodegen_source = """
targets:
  LorvexSystemIntents:
    type: framework
  LorvexSystemIntentsVision:
    type: framework
"""

            self.assertEqual(
                shared_target_contract_source_failures(
                    shared_targets,
                    package_source=package_source,
                    xcodegen_source=xcodegen_source,
                ),
                [],
            )

    def test_shared_target_contract_source_failures_rejects_system_intents_drift(self) -> None:
        shared_targets = {
            "system_intents": {
                "swiftpm_product": "MissingIntentsProduct",
                "ios_target": "LorvexSystemIntents",
                "visionos_target": "MissingVisionIntents",
                "source_path": "/tmp/lorvex-missing-system-intents-source",
                "actions": ["capture_task"],
                "capabilities": {
                    "shortcuts": ["open_task"],
                    "focus_filter_intent": "MissingFocusFilterIntent",
                },
            }
        }
        package_source = '.library(name: "LorvexCore", targets: ["LorvexCore"])'
        xcodegen_source = """
targets:
  LorvexSystemIntents:
    type: framework
"""

        self.assertEqual(
            shared_target_contract_source_failures(
                shared_targets,
                package_source=package_source,
                xcodegen_source=xcodegen_source,
            ),
            [
                "system_intents.swiftpm_product is not a Package.swift product: "
                "'MissingIntentsProduct'",
                "system_intents.visionos_target is not an XcodeGen target: "
                "'MissingVisionIntents'",
                "system_intents.source_path is not a directory: "
                "'/tmp/lorvex-missing-system-intents-source'",
                "system_intents.capabilities.shortcuts does not match actions: "
                "['open_task']",
                "system_intents.capabilities.focus_filter_intent mismatch: "
                "'MissingFocusFilterIntent'",
            ],
        )

    def test_shared_target_contract_source_failures_rejects_missing_focus_filter_source(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source_path = Path(directory) / "LorvexSystemIntents"
            source_path.mkdir()
            shared_targets = {
                "system_intents": {
                    "swiftpm_product": "LorvexSystemIntents",
                    "ios_target": "LorvexSystemIntents",
                    "visionos_target": "LorvexSystemIntentsVision",
                    "source_path": str(source_path),
                    "actions": ["capture_task"],
                    "capabilities": {
                        "shortcuts": ["capture_task"],
                        "focus_filter_intent": "LorvexFocusFilterIntent",
                    },
                }
            }
            package_source = '.library(name: "LorvexSystemIntents", targets: ["LorvexSystemIntents"])'
            xcodegen_source = """
targets:
  LorvexSystemIntents:
    type: framework
  LorvexSystemIntentsVision:
    type: framework
"""

            failures = shared_target_contract_source_failures(
                shared_targets,
                package_source=package_source,
                xcodegen_source=xcodegen_source,
            )

            self.assertEqual(len(failures), 1)
            self.assertIn("focus filter intent source missing:", failures[0])

    def test_shared_target_contract_source_failures_rejects_non_focus_filter_intent_source(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source_path = Path(directory) / "LorvexSystemIntents"
            source_path.mkdir()
            (source_path / "LorvexFocusFilterIntent.swift").write_text(
                "public struct LorvexFocusFilterIntent {}",
                encoding="utf-8",
            )
            shared_targets = {
                "system_intents": {
                    "swiftpm_product": "LorvexSystemIntents",
                    "ios_target": "LorvexSystemIntents",
                    "visionos_target": "LorvexSystemIntentsVision",
                    "source_path": str(source_path),
                    "actions": ["capture_task"],
                    "capabilities": {
                        "shortcuts": ["capture_task"],
                        "focus_filter_intent": "LorvexFocusFilterIntent",
                    },
                }
            }
            package_source = '.library(name: "LorvexSystemIntents", targets: ["LorvexSystemIntents"])'
            xcodegen_source = """
targets:
  LorvexSystemIntents:
    type: framework
  LorvexSystemIntentsVision:
    type: framework
"""

            failures = shared_target_contract_source_failures(
                shared_targets,
                package_source=package_source,
                xcodegen_source=xcodegen_source,
            )

            self.assertEqual(len(failures), 1)
            self.assertIn("focus filter intent source does not declare SetFocusFilterIntent", failures[0])

    def test_concrete_info_plist_accepts_ios_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Info.plist"
            path.write_bytes(
                b"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>LorvexMobileApp</string>
  <key>CFBundleDisplayName</key><string>Lorvex</string>
  <key>CFBundleIdentifier</key><string>com.lorvex.apple.mobile</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>MinimumOSVersion</key><string>17.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSCalendarsWriteOnlyAccessUsageDescription</key><string>Lorvex can add planning blocks you create to Apple Calendar.</string>
  <key>NSCalendarsFullAccessUsageDescription</key><string>Lorvex can read event details to build schedules and assistant context.</string>
  <key>NSSupportsLiveActivities</key><true/>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLSchemes</key>
      <array><string>lorvex</string></array>
    </dict>
  </array>
</dict>
</plist>
"""
            )

            self.assertEqual(
                concrete_info_plist_failures(
                    str(path),
                    {
                        "scheme": "LorvexMobileApp",
                        "display_name": "Lorvex",
                        "bundle_id": "com.lorvex.apple.mobile",
                        "minimum_os": "17.0",
                    },
                    TEST_METADATA,
                    "ios",
                ),
                [],
            )

    def test_concrete_info_plist_rejects_missing_url_scheme(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Info.plist"
            path.write_bytes(
                b"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Wrong</string>
</dict>
</plist>
"""
            )

            failures = concrete_info_plist_failures(
                str(path),
                {
                    "scheme": "LorvexMobileApp",
                    "display_name": "Lorvex",
                    "bundle_id": "com.lorvex.apple.mobile",
                    "minimum_os": "17.0",
                },
                TEST_METADATA,
                "ios",
            )

            self.assertIn("ios Info.plist CFBundleName mismatch: 'Wrong' != 'LorvexMobileApp'", failures)
            self.assertIn("ios Info.plist does not register URL scheme 'lorvex'", failures)

    def test_ios_live_activity_failures_accepts_consistent_true(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Info.plist"
            path.write_bytes(
                b"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>NSSupportsLiveActivities</key><true/>
</dict>
</plist>
"""
            )

            self.assertEqual(
                ios_live_activity_failures(
                    {"live_activities_supported": True, "info_plist": str(path)}
                ),
                [],
            )

    def test_ios_live_activity_failures_accepts_consistent_false(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Info.plist"
            path.write_bytes(
                b"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
"""
            )

            self.assertEqual(
                ios_live_activity_failures(
                    {"live_activities_supported": False, "info_plist": str(path)}
                ),
                [],
            )

    def test_ios_live_activity_failures_rejects_manifest_true_without_plist_declaration(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Info.plist"
            path.write_bytes(
                b"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
"""
            )

            self.assertEqual(
                ios_live_activity_failures(
                    {"live_activities_supported": True, "info_plist": str(path)}
                ),
                [
                    "ios.live_activities_supported (True) does not match Info.plist "
                    "NSSupportsLiveActivities (False)"
                ],
            )

    def test_ios_live_activity_failures_rejects_plist_declaration_without_manifest_flag(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Info.plist"
            path.write_bytes(
                b"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>NSSupportsLiveActivities</key><true/>
</dict>
</plist>
"""
            )

            self.assertEqual(
                ios_live_activity_failures(
                    {"live_activities_supported": False, "info_plist": str(path)}
                ),
                [
                    "ios.live_activities_supported (False) does not match Info.plist "
                    "NSSupportsLiveActivities (True)"
                ],
            )

    def test_ios_live_activity_failures_rejects_non_boolean_manifest_flag(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Info.plist"
            path.write_bytes(
                b"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
"""
            )

            self.assertEqual(
                ios_live_activity_failures({"info_plist": str(path)}),
                ["ios.live_activities_supported must be a boolean"],
            )

    def test_watch_info_plist_accepts_watch_flags(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Watch.plist"
            path.write_bytes(
                b"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key><string>Lorvex</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>WKApplication</key><true/>
  <key>WKWatchOnly</key><false/>
  <key>WKCompanionAppBundleIdentifier</key><string>com.lorvex.apple.mobile</string>
</dict>
</plist>
"""
            )

            self.assertEqual(
                watch_info_plist_failures(
                    str(path),
                    {"display_name": "Lorvex"},
                    "com.lorvex.apple.mobile",
                ),
                [],
            )

    def test_widget_info_plist_accepts_extension_point(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Widget.plist"
            path.write_bytes(
                b"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>LorvexFocusWidget</string>
  <key>CFBundleDisplayName</key><string>Lorvex Focus</string>
  <key>CFBundleExecutable</key><string>LorvexFocusWidget</string>
  <key>CFBundleIdentifier</key><string>com.lorvex.apple.widget.focus</string>
  <key>CFBundlePackageType</key><string>XPC!</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>NSExtension</key>
  <dict>
    <key>NSExtensionPointIdentifier</key><string>com.apple.widgetkit-extension</string>
  </dict>
</dict>
</plist>
"""
            )

            self.assertEqual(
                widget_info_plist_failures(
                    str(path),
                    {
                        "executable": "LorvexFocusWidget",
                        "display_name": "Lorvex Focus",
                        "bundle_id": "com.lorvex.apple.widget.focus",
                        "extension_point": "com.apple.widgetkit-extension",
                    },
                    TEST_METADATA,
                ),
                [],
            )

    def test_entitlement_failures_require_app_group(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "App.entitlements"
            path.write_bytes(
                b"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.application-groups</key>
  <array><string>group.com.lorvex.apple</string></array>
</dict>
</plist>
"""
            )

            self.assertEqual(entitlement_failures(str(path), TEST_METADATA, "ios"), [])

    def test_cloudkit_entitlement_failures_require_container_and_service(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Cloud.entitlements"
            path.write_bytes(
                b"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.application-groups</key>
  <array><string>group.com.lorvex.apple</string></array>
</dict>
</plist>
"""
            )

            self.assertEqual(
                cloudkit_entitlement_failures(str(path), TEST_METADATA, "ios"),
                [
                    "ios CloudKit entitlements missing container 'iCloud.com.lorvex.apple'",
                    "ios CloudKit entitlements missing CloudKit service",
                ],
            )

    def test_executable_script_failures_require_executable_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "verify.sh"
            path.write_text("#!/usr/bin/env bash\n", encoding="utf-8")

            self.assertEqual(
                executable_script_failures(str(path), "ios simulator verifier"),
                [f"ios simulator verifier is not executable: {path}"],
            )

    def test_simulator_manifest_failures_accepts_executable_aggregate_verifier(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "verify_all_simulators.sh"
            path.write_text("#!/usr/bin/env bash\n", encoding="utf-8")
            path.chmod(0o755)

            self.assertEqual(
                simulator_manifest_failures({"all_platforms_verifier": str(path)}),
                [],
            )

    def test_simulator_manifest_failures_require_aggregate_verifier(self) -> None:
        self.assertEqual(
            simulator_manifest_failures({}),
            ["simulators.all_platforms_verifier missing"],
        )

    def test_simulator_manifest_failures_require_manifest_object(self) -> None:
        self.assertEqual(
            simulator_manifest_failures(None),
            ["simulators mismatch: None"],
        )


class DeploymentFloorTests(unittest.TestCase):
    FLOOR_METADATA = {
        "MIN_SYSTEM_VERSION": "15.0",
        "MIN_MOBILE_SYSTEM_VERSION": "18.0",
        "MIN_VISION_SYSTEM_VERSION": "2.0",
        "MIN_WATCH_SYSTEM_VERSION": "11.0",
    }
    PACKAGE_SOURCE = (
        "    platforms: [\n"
        "        .macOS(.v15),\n"
        "        .iOS(.v18),\n"
        "        .visionOS(.v2),\n"
        "        .watchOS(.v11)\n"
        "    ],\n"
    )
    XCODEGEN_SOURCE = (
        "  deploymentTarget:\n"
        '    iOS: "18.0"\n'
        '    visionOS: "2.0"\n'
        '    watchOS: "11.0"\n'
        "settings:\n"
    )

    def test_deployment_floor_failures_accepts_matching_floor(self) -> None:
        self.assertEqual(
            deployment_floor_failures(
                self.FLOOR_METADATA,
                package_source=self.PACKAGE_SOURCE,
                core_package_source=self.PACKAGE_SOURCE,
                xcodegen_source=self.XCODEGEN_SOURCE,
            ),
            [],
        )

    def test_deployment_floor_failures_rejects_drifted_xcodegen_target(self) -> None:
        drifted_xcodegen = self.XCODEGEN_SOURCE.replace('iOS: "18.0"', 'iOS: "17.0"')
        failures = deployment_floor_failures(
            self.FLOOR_METADATA,
            package_source=self.PACKAGE_SOURCE,
            core_package_source=self.PACKAGE_SOURCE,
            xcodegen_source=drifted_xcodegen,
        )
        self.assertEqual(
            failures,
            [
                "XcodeGen deploymentTarget iOS mismatch: "
                "'17.0' != '18.0' (MIN_MOBILE_SYSTEM_VERSION)"
            ],
        )

    def test_deployment_floor_failures_rejects_drifted_core_package(self) -> None:
        drifted_core = self.PACKAGE_SOURCE.replace(".watchOS(.v11)", ".watchOS(.v10)")
        failures = deployment_floor_failures(
            self.FLOOR_METADATA,
            package_source=self.PACKAGE_SOURCE,
            core_package_source=drifted_core,
            xcodegen_source=self.XCODEGEN_SOURCE,
        )
        self.assertEqual(
            failures,
            [
                "core/Package.swift watchOS floor mismatch: "
                "'10.0' != '11.0' (MIN_WATCH_SYSTEM_VERSION)"
            ],
        )


if __name__ == "__main__":
    unittest.main()
