#!/usr/bin/env python3
from __future__ import annotations

import tempfile
import unittest
import json
import zipfile
from pathlib import Path

from quality_gates import quality_gate_manifest
from release_strategy import SYSTEM_INTENTS_ACTIONS, SYSTEM_INTENTS_CAPABILITIES
from verify_release_manifest import (
    ROOT as RELEASE_ROOT,
    apple_platform_manifest_failures,
    archive_layout_failures,
    bundle_artifact_failures,
    bundle_info_plist_failures,
    client_config_test_glob_failures,
    bundle_layout_failures,
    integration_metadata_failures,
    mcp_client_config_contract_failures,
    path_containment_failures,
    privacy_manifest_failures,
    regular_file_failures,
    symlink_failures,
    widget_info_plist_failures,
)


TEST_METADATA = {
    "APP_NAME": "LorvexApple",
    "APP_DISPLAY_NAME": "Lorvex",
    "BUNDLE_ID": "com.lorvex.apple",
    "MARKETING_VERSION": "1.0.0",
    "BUILD_VERSION": "1",
    "MIN_SYSTEM_VERSION": "14.0",
    "URL_SCHEME": "lorvex",
    "MCP_SERVER_NAME": "lorvex-apple",
    "MCP_HOST_PRODUCT": "LorvexMCPHost",
    "APP_GROUP_ID": "group.com.lorvex.apple",
    "CLOUDKIT_CONTAINER_ID": "iCloud.com.lorvex.apple",
    "WIDGET_BUNDLE_ID": "com.lorvex.apple.mobile.widget.focus",
    "WIDGET_EXECUTABLE": "LorvexFocusWidget",
    "WIDGET_APPEX_NAME": "LorvexFocusWidget.appex",
    "WIDGET_KIND": "com.lorvex.apple.widget.focus",
    "WIDGET_DISPLAY_NAME": "Lorvex Focus",
    "WIDGET_EXTENSION_POINT_IDENTIFIER": "com.apple.widgetkit-extension",
    "CONTROL_WIDGET_KIND": "com.lorvex.control.focus",
    "CONTROL_WIDGET_DISPLAY_NAME": "Lorvex Focus",
    "CONTROL_WIDGET_DESCRIPTION": "Shows the current focus task.",
    "APP_CATEGORY": "public.app-category.productivity",
    "CALENDAR_WRITE_USAGE_DESCRIPTION": "Lorvex can add planning blocks you create to Apple Calendar.",
    "CALENDAR_FULL_ACCESS_USAGE_DESCRIPTION": (
        "Lorvex can read event details to build schedules and assistant context."
    ),
}


MCP_CLIENT_METADATA = {
    "app": "LorvexApple",
    "server_name": "lorvex-apple",
    "host_product": "LorvexMCPHost",
    "strategy": {
        "platform_scope": "apple-only",
        "mcp_host": "swift-native",
        "mcp_sdk": "modelcontextprotocol/swift-sdk",
    },
}


PRIVACY_MANIFEST_BYTES = b"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>NSPrivacyTracking</key><false/>
  <key>NSPrivacyTrackingDomains</key><array/>
  <key>NSPrivacyCollectedDataTypes</key><array/>
  <key>NSPrivacyAccessedAPITypes</key>
  <array>
    <dict>
      <key>NSPrivacyAccessedAPIType</key>
      <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
      <key>NSPrivacyAccessedAPITypeReasons</key>
      <array><string>CA92.1</string></array>
    </dict>
  </array>
</dict>
</plist>
"""


def executable_zip_info(name: str) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(name)
    info.external_attr = (0o100755 << 16)
    return info


class VerifyReleaseManifestTests(unittest.TestCase):
    def test_archive_layout_failures_accepts_clean_keep_parent_archive(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "LorvexApple.zip"
            with zipfile.ZipFile(archive, "w") as zip_file:
                zip_file.writestr("LorvexApple.app/", "")
                zip_file.writestr(executable_zip_info("LorvexApple.app/Contents/MacOS/LorvexApple"), "")
                zip_file.writestr("LorvexApple.app/Contents/Info.plist", "")
                zip_file.writestr("LorvexApple.app/Contents/Resources/PrivacyInfo.xcprivacy", "")

            self.assertEqual(archive_layout_failures(archive, "LorvexApple"), [])

    def test_archive_layout_failures_rejects_appledouble_sidecars(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "LorvexApple.zip"
            with zipfile.ZipFile(archive, "w") as zip_file:
                zip_file.writestr("LorvexApple.app/", "")
                zip_file.writestr(executable_zip_info("LorvexApple.app/Contents/MacOS/LorvexApple"), "")
                zip_file.writestr("LorvexApple.app/Contents/Info.plist", "")
                zip_file.writestr("LorvexApple.app/Contents/Resources/PrivacyInfo.xcprivacy", "")
                zip_file.writestr("LorvexApple.app/Contents/Resources/._Icon", "")

            self.assertEqual(
                archive_layout_failures(archive, "LorvexApple"),
                [
                    "archive contains AppleDouble sidecar file(s): "
                    "['LorvexApple.app/Contents/Resources/._Icon']"
                ],
            )

    def test_archive_layout_failures_rejects_macosx_metadata_entries(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "LorvexApple.zip"
            with zipfile.ZipFile(archive, "w") as zip_file:
                zip_file.writestr("LorvexApple.app/", "")
                zip_file.writestr(executable_zip_info("LorvexApple.app/Contents/MacOS/LorvexApple"), "")
                zip_file.writestr("LorvexApple.app/Contents/Info.plist", "")
                zip_file.writestr("LorvexApple.app/Contents/Resources/PrivacyInfo.xcprivacy", "")
                zip_file.writestr("LorvexApple.app/__MACOSX/metadata", "")

            self.assertEqual(
                archive_layout_failures(archive, "LorvexApple"),
                [
                    "archive contains __MACOSX metadata entry(s): "
                    "['LorvexApple.app/__MACOSX/metadata']"
                ],
            )

    def test_archive_layout_failures_rejects_missing_parent_bundle_and_executable(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "LorvexApple.zip"
            with zipfile.ZipFile(archive, "w") as zip_file:
                zip_file.writestr("Contents/Info.plist", "")

            self.assertEqual(
                archive_layout_failures(archive, "LorvexApple"),
                [
                    "archive contains entries outside app bundle: ['Contents/Info.plist']",
                    "archive does not keep parent app bundle: LorvexApple.app/",
                    "archive missing required entry: "
                    "LorvexApple.app/Contents/MacOS/LorvexApple",
                    "archive missing required entry: LorvexApple.app/Contents/Info.plist",
                    "archive missing required entry: "
                    "LorvexApple.app/Contents/Resources/PrivacyInfo.xcprivacy",
                ],
            )

    def test_archive_layout_failures_rejects_entries_outside_app_bundle(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "LorvexApple.zip"
            with zipfile.ZipFile(archive, "w") as zip_file:
                zip_file.writestr("LorvexApple.app/", "")
                zip_file.writestr(executable_zip_info("LorvexApple.app/Contents/MacOS/LorvexApple"), "")
                zip_file.writestr("LorvexApple.app/Contents/Info.plist", "")
                zip_file.writestr("LorvexApple.app/Contents/Resources/PrivacyInfo.xcprivacy", "")
                zip_file.writestr("../escape.txt", "")
                zip_file.writestr("README.txt", "")

            self.assertEqual(
                archive_layout_failures(archive, "LorvexApple"),
                ["archive contains entries outside app bundle: ['../escape.txt', 'README.txt']"],
            )

    def test_archive_layout_failures_rejects_symlink_entries(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "LorvexApple.zip"
            symlink_info = zipfile.ZipInfo("LorvexApple.app/Contents/Resources/link")
            symlink_info.external_attr = (0o120777 << 16)
            with zipfile.ZipFile(archive, "w") as zip_file:
                zip_file.writestr("LorvexApple.app/", "")
                zip_file.writestr(executable_zip_info("LorvexApple.app/Contents/MacOS/LorvexApple"), "")
                zip_file.writestr("LorvexApple.app/Contents/Info.plist", "")
                zip_file.writestr("LorvexApple.app/Contents/Resources/PrivacyInfo.xcprivacy", "")
                zip_file.writestr(symlink_info, "../Info.plist")

            self.assertEqual(
                archive_layout_failures(archive, "LorvexApple"),
                [
                    "archive contains symlink entry(s): "
                    "['LorvexApple.app/Contents/Resources/link']"
                ],
            )

    def test_archive_layout_failures_rejects_missing_embedded_components(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "LorvexApple.zip"
            with zipfile.ZipFile(archive, "w") as zip_file:
                zip_file.writestr("LorvexApple.app/", "")
                zip_file.writestr(executable_zip_info("LorvexApple.app/Contents/MacOS/LorvexApple"), "")
                zip_file.writestr("LorvexApple.app/Contents/Info.plist", "")
                zip_file.writestr("LorvexApple.app/Contents/Resources/PrivacyInfo.xcprivacy", "")

            self.assertEqual(
                archive_layout_failures(archive, "LorvexApple", TEST_METADATA),
                [
                    "archive missing required entry: "
                    "LorvexApple.app/Contents/Helpers/LorvexMCPHost.app/Contents/MacOS/LorvexMCPHost",
                    "archive missing required entry: "
                    "LorvexApple.app/Contents/Helpers/LorvexMCPHost.app/Contents/Info.plist",
                    "archive missing required entry: "
                    "LorvexApple.app/Contents/PlugIns/LorvexFocusWidget.appex/Contents/MacOS/LorvexFocusWidget",
                    "archive missing required entry: "
                    "LorvexApple.app/Contents/PlugIns/LorvexFocusWidget.appex/Contents/Info.plist",
                    "archive missing required entry: "
                    "LorvexApple.app/Contents/PlugIns/LorvexFocusWidget.appex/Contents/Resources/PrivacyInfo.xcprivacy",
                ],
            )

    def test_archive_layout_failures_rejects_non_executable_required_binary_entry(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "LorvexApple.zip"
            app_binary = zipfile.ZipInfo("LorvexApple.app/Contents/MacOS/LorvexApple")
            app_binary.external_attr = (0o100644 << 16)
            with zipfile.ZipFile(archive, "w") as zip_file:
                zip_file.writestr("LorvexApple.app/", "")
                zip_file.writestr(app_binary, "")
                zip_file.writestr("LorvexApple.app/Contents/Info.plist", "")
                zip_file.writestr("LorvexApple.app/Contents/Resources/PrivacyInfo.xcprivacy", "")

            self.assertEqual(
                archive_layout_failures(archive, "LorvexApple"),
                [
                    "archive required executable entry is not executable: "
                    "LorvexApple.app/Contents/MacOS/LorvexApple"
                ],
            )

    def test_integration_metadata_failures_accepts_widget_and_control_widget_metadata(self) -> None:
        self.assertEqual(
            integration_metadata_failures(
                {
                    "app_group": "group.com.lorvex.apple",
                    "cloudkit_container": "iCloud.com.lorvex.apple",
                    "cloudkit_sync_readiness": {
                        "ready": [
                            "outbound_record_export",
                            "private_database_subscription",
                            "remote_change_refresh",
                            "inbound_record_application",
                            "change_token_checkpointing",
                        ],
                        "pending": [],
                    },
                    "cloudkit_production_release_readiness": {
                        "ready": [
                            "mas_cloudkit_entitlement_template",
                            "mas_entitlement_verifier",
                        ],
                        "pending": [
                            "cloudkit_production_schema_promotion",
                            "app_store_connect_provisioning",
                        ],
                    },
                    "system_intents_product": "LorvexSystemIntents",
                    "system_intents_actions": SYSTEM_INTENTS_ACTIONS,
                    "system_intents_capabilities": SYSTEM_INTENTS_CAPABILITIES,
                    "widget_bundle_id": "com.lorvex.apple.mobile.widget.focus",
                    "widget_kind": "com.lorvex.apple.widget.focus",
                    "control_widget_kind": "com.lorvex.control.focus",
                    "control_widget_display_name": "Lorvex Focus",
                    "control_widget_description": "Shows the current focus task.",
                },
                TEST_METADATA,
            ),
            [],
        )

    def test_integration_metadata_failures_rejects_missing_control_widget_metadata(self) -> None:
        failures = integration_metadata_failures(
            {
                "app_group": "group.com.lorvex.apple",
                "cloudkit_container": "iCloud.com.lorvex.apple",
                "cloudkit_sync_readiness": {
                    "ready": [
                        "outbound_record_export",
                        "private_database_subscription",
                        "remote_change_refresh",
                        "change_token_checkpointing",
                    ],
                    "pending": [
                        "inbound_record_application",
                    ],
                },
                "cloudkit_production_release_readiness": {
                    "ready": [
                        "mas_cloudkit_entitlement_template",
                        "mas_entitlement_verifier",
                    ],
                    "pending": [
                        "cloudkit_production_schema_promotion",
                        "app_store_connect_provisioning",
                    ],
                },
                "system_intents_product": "LorvexSystemIntents",
                "system_intents_actions": SYSTEM_INTENTS_ACTIONS,
                "system_intents_capabilities": SYSTEM_INTENTS_CAPABILITIES,
                "widget_bundle_id": "com.lorvex.apple.mobile.widget.focus",
                "widget_kind": "com.lorvex.apple.widget.focus",
            },
            TEST_METADATA,
        )

        self.assertEqual(len(failures), 1)
        self.assertIn("integration metadata mismatch", failures[0])

    def test_apple_platform_manifest_failures_accepts_platform_manifest_linkage(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = root / "lorvex-apple-platform-manifest.json"
            platform_verifier = root / "verify_apple_platform_manifest.py"
            xcodegen_verifier = root / "verify_xcodegen_project.sh"
            for path in [platform_verifier, xcodegen_verifier]:
                path.write_text("#!/bin/sh\n", encoding="utf-8")
                path.chmod(0o755)
            manifest.write_text(
                json.dumps(
                    {
                        "quality_gates": quality_gate_manifest(RELEASE_ROOT),
                        "shared_targets": {
                            "system_intents": {
                                "swiftpm_product": "LorvexSystemIntents",
                                "actions": SYSTEM_INTENTS_ACTIONS,
                                "capabilities": SYSTEM_INTENTS_CAPABILITIES,
                            }
                        },
                        "simulators": {
                            "all_platforms_verifier": str(
                                RELEASE_ROOT / "script" / "verify_apple_simulators.sh"
                            )
                        },
                        "targets": {
                            "ios": {"live_activities_supported": True},
                            "visionos": {},
                            "watchos": {},
                            "watch_complication": {},
                            "widget": {},
                            "focus_filter": {},
                        },
                        "xcodegen": {
                            "verified_by": str(xcodegen_verifier),
                        },
                    }
                ),
                encoding="utf-8",
            )

            self.assertEqual(
                apple_platform_manifest_failures(
                    {
                        "manifest": str(manifest),
                        "manifest_verifier": str(platform_verifier),
                        "xcodegen_project_verifier": str(xcodegen_verifier),
                    }
                ),
                [],
            )

    def test_apple_platform_manifest_failures_rejects_missing_platform_targets(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = root / "lorvex-apple-platform-manifest.json"
            platform_verifier = root / "verify_apple_platform_manifest.py"
            xcodegen_verifier = root / "verify_xcodegen_project.sh"
            for path in [platform_verifier, xcodegen_verifier]:
                path.write_text("#!/bin/sh\n", encoding="utf-8")
                path.chmod(0o755)
            manifest.write_text(
                json.dumps(
                    {
                        "quality_gates": quality_gate_manifest(RELEASE_ROOT),
                        "shared_targets": {
                            "system_intents": {
                                "swiftpm_product": "LorvexSystemIntents",
                                "actions": ["capture_task"],
                            }
                        },
                        "simulators": {},
                        "targets": {
                            "ios": {"live_activities_supported": True},
                        },
                        "xcodegen": {
                            "verified_by": "wrong-verifier.sh",
                        },
                    }
                ),
                encoding="utf-8",
            )

            self.assertEqual(
                apple_platform_manifest_failures(
                    {
                        "manifest": str(manifest),
                        "manifest_verifier": str(platform_verifier),
                        "xcodegen_project_verifier": str(xcodegen_verifier),
                    }
                ),
                [
                    "Apple platform manifest missing target(s): "
                    "['focus_filter', 'visionos', 'watch_complication', 'watchos', 'widget']",
                    "Apple platform manifest system intents actions mismatch: ['capture_task']",
                    "Apple platform manifest XcodeGen verifier does not match release manifest",
                    "Apple simulator aggregate verifier is not a file: .",
                ],
            )

    def test_apple_platform_manifest_failures_rejects_missing_live_activity_contract(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = root / "lorvex-apple-platform-manifest.json"
            platform_verifier = root / "verify_apple_platform_manifest.py"
            xcodegen_verifier = root / "verify_xcodegen_project.sh"
            for path in [platform_verifier, xcodegen_verifier]:
                path.write_text("#!/bin/sh\n", encoding="utf-8")
                path.chmod(0o755)
            manifest.write_text(
                json.dumps(
                    {
                        "quality_gates": quality_gate_manifest(RELEASE_ROOT),
                        "shared_targets": {
                            "system_intents": {
                                "swiftpm_product": "LorvexSystemIntents",
                                "actions": SYSTEM_INTENTS_ACTIONS,
                                "capabilities": SYSTEM_INTENTS_CAPABILITIES,
                            }
                        },
                        "simulators": {
                            "all_platforms_verifier": str(
                                RELEASE_ROOT / "script" / "verify_apple_simulators.sh"
                            )
                        },
                        "targets": {
                            "ios": {},
                            "visionos": {},
                            "watchos": {},
                            "watch_complication": {},
                            "widget": {},
                            "focus_filter": {},
                        },
                        "xcodegen": {
                            "verified_by": str(xcodegen_verifier),
                        },
                    }
                ),
                encoding="utf-8",
            )

            self.assertEqual(
                apple_platform_manifest_failures(
                    {
                        "manifest": str(manifest),
                        "manifest_verifier": str(platform_verifier),
                        "xcodegen_project_verifier": str(xcodegen_verifier),
                    }
                ),
                ["Apple platform manifest ios.live_activities_supported must be a boolean"],
            )

    def test_client_config_test_glob_accepts_matching_files(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script_dir = root / "script"
            script_dir.mkdir()
            (script_dir / "test_example.py").write_text("", encoding="utf-8")

            self.assertEqual(client_config_test_glob_failures(root, "script/test_*.py"), [])

    def test_client_config_test_glob_rejects_wrong_glob(self) -> None:
        self.assertEqual(
            client_config_test_glob_failures(Path("/tmp"), "Tests/test_*.py"),
            ["MCP client config test glob mismatch: 'Tests/test_*.py'"],
        )

    def test_client_config_test_glob_rejects_empty_matches(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual(
                client_config_test_glob_failures(Path(directory), "script/test_*.py"),
                ["MCP client config test glob does not match any files"],
            )

    def test_client_config_test_glob_rejects_matching_directory(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script_dir = root / "script"
            script_dir.mkdir()
            matched_directory = script_dir / "test_directory.py"
            matched_directory.mkdir()

            self.assertEqual(
                client_config_test_glob_failures(root, "script/test_*.py"),
                [f"MCP client config test glob matched non-file path: {matched_directory}"],
            )

    def test_mcp_client_config_contract_accepts_swift_native_config(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / "LorvexApple.app"
            helper = app / "Contents" / "Helpers" / "LorvexMCPHost.app" / "Contents" / "MacOS" / "LorvexMCPHost"
            helper.parent.mkdir(parents=True)
            helper.write_text("#!/bin/sh\n", encoding="utf-8")
            helper.chmod(0o755)
            config = root / "mcp.json"
            config.write_text(
                json.dumps(
                    {
                        "lorvex": MCP_CLIENT_METADATA,
                        "mcpServers": {
                            "lorvex-apple": {
                                "command": str(helper),
                                "args": [],
                            }
                        },
                    }
                ),
                encoding="utf-8",
            )

            self.assertEqual(mcp_client_config_contract_failures(config, app, TEST_METADATA), [])

    def test_bundle_artifact_failures_require_executable_files_and_directories(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / "LorvexApple.app"
            macos = app / "Contents" / "MacOS"
            helpers = app / "Contents" / "Helpers"
            frameworks = app / "Contents" / "Frameworks"
            plugins = app / "Contents" / "PlugIns"
            resources = app / "Contents" / "Resources"
            for path in [macos, helpers, frameworks, plugins, resources]:
                path.mkdir(parents=True, exist_ok=True)
            app_executable = macos / "LorvexApple"
            helper = helpers / "LorvexMCPHost"
            widget = plugins / "LorvexFocusWidget.appex"
            widget_executable = widget / "Contents" / "MacOS" / "LorvexFocusWidget"
            widget_resources = widget / "Contents" / "Resources"
            for path in [app_executable, helper, widget_executable]:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("#!/bin/sh\n", encoding="utf-8")
                path.chmod(0o755)
            widget_resources.mkdir(parents=True)
            privacy_manifest = resources / "PrivacyInfo.xcprivacy"
            widget_privacy_manifest = widget_resources / "PrivacyInfo.xcprivacy"
            privacy_manifest.write_bytes(PRIVACY_MANIFEST_BYTES)
            widget_privacy_manifest.write_bytes(PRIVACY_MANIFEST_BYTES)

            self.assertEqual(
                bundle_artifact_failures(
                    {
                        "path": str(app),
                        "helper": str(helper),
                        "widget_extension": str(widget),
                        "privacy_manifest": str(privacy_manifest),
                        "widget_privacy_manifest": str(widget_privacy_manifest),
                    },
                    TEST_METADATA,
                ),
                [],
            )

    def test_path_containment_failures_accepts_children_inside_bundle(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "LorvexApple.app"
            helper = app / "Contents" / "Helpers" / "LorvexMCPHost"
            helper.parent.mkdir(parents=True)
            helper.write_text("#!/bin/sh\n", encoding="utf-8")

            self.assertEqual(
                path_containment_failures(app, {"MCP helper": helper}),
                [],
            )

    def test_path_containment_failures_rejects_external_artifacts(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / "LorvexApple.app"
            helper = root / "External" / "LorvexMCPHost"
            app.mkdir()
            helper.parent.mkdir()
            helper.write_text("#!/bin/sh\n", encoding="utf-8")

            self.assertEqual(
                path_containment_failures(app, {"MCP helper": helper}),
                [f"MCP helper must be inside app bundle: {helper}"],
            )

    def test_symlink_failures_rejects_symlinked_artifacts(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "target-helper"
            link = root / "LorvexMCPHost"
            target.write_text("#!/bin/sh\n", encoding="utf-8")
            link.symlink_to(target)

            self.assertEqual(
                symlink_failures({"MCP helper": link}),
                [f"MCP helper must not be a symlink: {link}"],
            )

    def test_symlink_failures_accepts_regular_files(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            helper = Path(directory) / "LorvexMCPHost"
            helper.write_text("#!/bin/sh\n", encoding="utf-8")

            self.assertEqual(symlink_failures({"MCP helper": helper}), [])

    def test_bundle_artifact_failures_rejects_symlinked_app_executable(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / "LorvexApple.app"
            macos = app / "Contents" / "MacOS"
            helpers = app / "Contents" / "Helpers"
            frameworks = app / "Contents" / "Frameworks"
            plugins = app / "Contents" / "PlugIns"
            resources = app / "Contents" / "Resources"
            for path in [macos, helpers, frameworks, plugins, resources]:
                path.mkdir(parents=True, exist_ok=True)

            app_target = root / "external-app-executable"
            app_target.write_text("#!/bin/sh\n", encoding="utf-8")
            app_target.chmod(0o755)
            app_executable = macos / "LorvexApple"
            app_executable.symlink_to(app_target)
            helper = helpers / "LorvexMCPHost"
            widget = plugins / "LorvexFocusWidget.appex"
            widget_executable = widget / "Contents" / "MacOS" / "LorvexFocusWidget"
            for path in [helper, widget_executable]:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("#!/bin/sh\n", encoding="utf-8")
                path.chmod(0o755)
            widget_resources = widget / "Contents" / "Resources"
            widget_resources.mkdir(parents=True)
            privacy_manifest = resources / "PrivacyInfo.xcprivacy"
            widget_privacy_manifest = widget_resources / "PrivacyInfo.xcprivacy"
            privacy_manifest.write_bytes(PRIVACY_MANIFEST_BYTES)
            widget_privacy_manifest.write_bytes(PRIVACY_MANIFEST_BYTES)

            failures = bundle_artifact_failures(
                {
                    "path": str(app),
                    "helper": str(helper),
                    "widget_extension": str(widget),
                    "privacy_manifest": str(privacy_manifest),
                    "widget_privacy_manifest": str(widget_privacy_manifest),
                },
                TEST_METADATA,
            )

            self.assertIn(f"app executable must not be a symlink: {app_executable}", failures)

    def test_bundle_layout_failures_rejects_wrong_internal_directory(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "LorvexApple.app"
            actual = app / "Contents" / "MacOS" / "LorvexMCPHost"
            expected = app / "Contents" / "Helpers" / "LorvexMCPHost"
            actual.parent.mkdir(parents=True)
            expected.parent.mkdir(parents=True)
            actual.write_text("#!/bin/sh\n", encoding="utf-8")
            expected.write_text("#!/bin/sh\n", encoding="utf-8")

            self.assertEqual(
                bundle_layout_failures({"MCP helper": (actual, expected)}),
                [f"MCP helper must be packaged at {expected}: {actual}"],
            )

    def test_regular_file_failures_do_not_require_executable_bit(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "PrivacyInfo.xcprivacy"
            path.write_text("<plist/>", encoding="utf-8")

            self.assertEqual(regular_file_failures(path, "privacy manifest"), [])

    def test_privacy_manifest_failures_rejects_tracking_and_missing_reason(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "PrivacyInfo.xcprivacy"
            path.write_bytes(
                b"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>NSPrivacyTracking</key><true/>
  <key>NSPrivacyTrackingDomains</key><array><string>tracker.example</string></array>
  <key>NSPrivacyCollectedDataTypes</key><array><dict/></array>
  <key>NSPrivacyAccessedAPITypes</key><array/>
</dict>
</plist>
"""
            )

            self.assertEqual(
                privacy_manifest_failures(path),
                [
                    "privacy manifest must declare NSPrivacyTracking=false",
                    "privacy manifest must declare no tracking domains",
                    "privacy manifest must declare no collected data types",
                    "privacy manifest missing UserDefaults required-reason API declaration",
                ],
            )

    def test_bundle_artifact_failures_reject_non_executable_helper(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / "LorvexApple.app"
            macos = app / "Contents" / "MacOS"
            helpers = app / "Contents" / "Helpers"
            frameworks = app / "Contents" / "Frameworks"
            plugins = app / "Contents" / "PlugIns"
            for path in [macos, helpers, frameworks, plugins]:
                path.mkdir(parents=True, exist_ok=True)
            app_executable = macos / "LorvexApple"
            helper = helpers / "LorvexMCPHost"
            widget = plugins / "LorvexFocusWidget.appex"
            widget_executable = widget / "Contents" / "MacOS" / "LorvexFocusWidget"
            widget_resources = widget / "Contents" / "Resources"
            resources = app / "Contents" / "Resources"
            resources.mkdir(parents=True)
            privacy_manifest = resources / "PrivacyInfo.xcprivacy"
            widget_privacy_manifest = widget_resources / "PrivacyInfo.xcprivacy"
            for path in [app_executable, widget_executable]:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("#!/bin/sh\n", encoding="utf-8")
                path.chmod(0o755)
            helper.write_text("#!/bin/sh\n", encoding="utf-8")
            widget_resources.mkdir(parents=True)
            privacy_manifest.write_bytes(PRIVACY_MANIFEST_BYTES)
            widget_privacy_manifest.write_bytes(PRIVACY_MANIFEST_BYTES)

            failures = bundle_artifact_failures(
                {
                    "path": str(app),
                    "helper": str(helper),
                    "widget_extension": str(widget),
                    "privacy_manifest": str(privacy_manifest),
                    "widget_privacy_manifest": str(widget_privacy_manifest),
                },
                TEST_METADATA,
            )

            self.assertEqual(failures, [f"MCP helper is not executable: {helper}"])

    def test_bundle_artifact_failures_requires_widget_executable(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / "LorvexApple.app"
            macos = app / "Contents" / "MacOS"
            helpers = app / "Contents" / "Helpers"
            frameworks = app / "Contents" / "Frameworks"
            plugins = app / "Contents" / "PlugIns"
            resources = app / "Contents" / "Resources"
            for path in [macos, helpers, frameworks, plugins, resources]:
                path.mkdir(parents=True, exist_ok=True)
            app_executable = macos / "LorvexApple"
            helper = helpers / "LorvexMCPHost"
            for path in [app_executable, helper]:
                path.write_text("#!/bin/sh\n", encoding="utf-8")
                path.chmod(0o755)
            widget = plugins / "LorvexFocusWidget.appex"
            widget_resources = widget / "Contents" / "Resources"
            widget_resources.mkdir(parents=True)
            privacy_manifest = resources / "PrivacyInfo.xcprivacy"
            widget_privacy_manifest = widget_resources / "PrivacyInfo.xcprivacy"
            privacy_manifest.write_bytes(PRIVACY_MANIFEST_BYTES)
            widget_privacy_manifest.write_bytes(PRIVACY_MANIFEST_BYTES)

            failures = bundle_artifact_failures(
                {
                    "path": str(app),
                    "helper": str(helper),
                    "widget_extension": str(widget),
                    "privacy_manifest": str(privacy_manifest),
                    "widget_privacy_manifest": str(widget_privacy_manifest),
                },
                TEST_METADATA,
            )

            widget_executable = widget / "Contents" / "MacOS" / "LorvexFocusWidget"
            self.assertIn(f"widget executable missing: {widget_executable}", failures)

    def test_bundle_info_plist_failures_accepts_matching_metadata_and_url_scheme(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            contents = root / "LorvexApple.app" / "Contents"
            contents.mkdir(parents=True)
            (contents / "Info.plist").write_bytes(
                b"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Lorvex</string>
  <key>CFBundleDisplayName</key><string>Lorvex</string>
  <key>CFBundleIdentifier</key><string>com.lorvex.apple</string>
  <key>CFBundleExecutable</key><string>LorvexApple</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSCalendarsWriteOnlyAccessUsageDescription</key><string>Lorvex can add planning blocks you create to Apple Calendar.</string>
  <key>NSCalendarsFullAccessUsageDescription</key><string>Lorvex can read event details to build schedules and assistant context.</string>
  <key>NSUserActivityTypes</key>
  <array>
    <string>com.lorvex.apple.openTask</string>
    <string>com.lorvex.apple.openDestination</string>
    <string>com.lorvex.apple.openList</string>
  </array>
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
                bundle_info_plist_failures(root / "LorvexApple.app", TEST_METADATA),
                [],
            )

    def test_bundle_info_plist_failures_rejects_mismatched_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            contents = root / "LorvexApple.app" / "Contents"
            contents.mkdir(parents=True)
            (contents / "Info.plist").write_bytes(
                b"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Wrong</string>
  <key>CFBundleDisplayName</key><string>Lorvex</string>
  <key>CFBundleIdentifier</key><string>com.lorvex.apple</string>
  <key>CFBundleExecutable</key><string>LorvexApple</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
</dict>
</plist>
"""
            )

            self.assertEqual(
                bundle_info_plist_failures(root / "LorvexApple.app", TEST_METADATA),
                [
                    "Info.plist CFBundleName mismatch: expected 'Lorvex', got 'Wrong'",
                    "Info.plist LSApplicationCategoryType mismatch: expected "
                    "'public.app-category.productivity', got None",
                    "Info.plist NSCalendarsWriteOnlyAccessUsageDescription mismatch: expected "
                    "'Lorvex can add planning blocks you create to Apple Calendar.', got None",
                    "Info.plist NSCalendarsFullAccessUsageDescription mismatch: expected "
                    "'Lorvex can read event details to build schedules and assistant context.', got None",
                    "Info.plist does not register URL scheme 'lorvex'",
                    "Info.plist NSUserActivityTypes mismatch: expected "
                    "['com.lorvex.apple.openTask', 'com.lorvex.apple.openDestination', "
                    "'com.lorvex.apple.openList'], "
                    "got None",
                ],
            )

    def test_widget_info_plist_failures_accepts_matching_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            contents = root / "LorvexFocusWidget.appex" / "Contents"
            contents.mkdir(parents=True)
            (contents / "Info.plist").write_bytes(
                b"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>LorvexFocusWidget</string>
  <key>CFBundleDisplayName</key><string>Lorvex Focus</string>
  <key>CFBundleIdentifier</key><string>com.lorvex.apple.mobile.widget.focus</string>
  <key>CFBundleExecutable</key><string>LorvexFocusWidget</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundlePackageType</key><string>XPC!</string>
  <key>NSExtension</key>
  <dict>
    <key>NSExtensionPointIdentifier</key><string>com.apple.widgetkit-extension</string>
  </dict>
</dict>
</plist>
"""
            )

            self.assertEqual(
                widget_info_plist_failures(root / "LorvexFocusWidget.appex", TEST_METADATA),
                [],
            )

    def test_widget_info_plist_failures_rejects_mismatched_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            contents = root / "LorvexFocusWidget.appex" / "Contents"
            contents.mkdir(parents=True)
            (contents / "Info.plist").write_bytes(
                b"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>WrongWidget</string>
  <key>CFBundleDisplayName</key><string>Lorvex Focus</string>
  <key>CFBundleIdentifier</key><string>wrong.bundle</string>
  <key>CFBundleExecutable</key><string>LorvexFocusWidget</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>NSExtension</key>
  <dict>
    <key>NSExtensionPointIdentifier</key><string>wrong.extension</string>
  </dict>
</dict>
</plist>
"""
            )

            self.assertEqual(
                widget_info_plist_failures(root / "LorvexFocusWidget.appex", TEST_METADATA),
                [
                    "widget Info.plist CFBundleName mismatch: expected "
                    "'LorvexFocusWidget', got 'WrongWidget'",
                    "widget Info.plist CFBundleIdentifier mismatch: expected "
                    "'com.lorvex.apple.mobile.widget.focus', got 'wrong.bundle'",
                    "widget Info.plist CFBundlePackageType mismatch: expected 'XPC!', got 'APPL'",
                    "widget Info.plist NSExtensionPointIdentifier mismatch: expected "
                    "'com.apple.widgetkit-extension', got 'wrong.extension'",
                ],
            )


if __name__ == "__main__":
    unittest.main()
