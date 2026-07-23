#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import plistlib
import tempfile
import unittest

from verify_app_metadata import (
    verify_carplay_entitlements,
    verify_entitlements,
    verify_export_compliance_key,
    verify_macos_export_compliance_marker,
    verify_mobile_carplay_activation_template,
)


class VerifyAppMetadataTests(unittest.TestCase):
    def test_entitlements_forbid_aps_environment_rejects_push_capability(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "LorvexVisionAppCloudKitAppStore.entitlements"
            with path.open("wb") as file:
                plistlib.dump(
                    {
                        "com.apple.security.application-groups": ["group.com.lorvex.apple"],
                        "com.apple.developer.icloud-container-identifiers": [
                            "iCloud.com.lorvex.apple"
                        ],
                        "com.apple.developer.icloud-services": ["CloudKit"],
                        "aps-environment": "production",
                    },
                    file,
                )

            failures: list[str] = []
            verify_entitlements(
                path,
                "group.com.lorvex.apple",
                "iCloud.com.lorvex.apple",
                True,
                False,
                False,
                failures,
                forbid_aps_environment=True,
            )

            self.assertEqual(
                failures,
                [
                    f"{path} unexpectedly declares aps-environment 'production'; this "
                    "target has no push-notification delivery path and must not request "
                    "the aps-environment capability"
                ],
            )

    def test_entitlements_forbid_aps_environment_accepts_no_push_capability(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "LorvexVisionAppCloudKitAppStore.entitlements"
            with path.open("wb") as file:
                plistlib.dump(
                    {
                        "com.apple.security.application-groups": ["group.com.lorvex.apple"],
                        "com.apple.developer.icloud-container-identifiers": [
                            "iCloud.com.lorvex.apple"
                        ],
                        "com.apple.developer.icloud-services": ["CloudKit"],
                    },
                    file,
                )

            failures: list[str] = []
            verify_entitlements(
                path,
                "group.com.lorvex.apple",
                "iCloud.com.lorvex.apple",
                True,
                False,
                False,
                failures,
                forbid_aps_environment=True,
            )

            self.assertEqual(failures, [])

    def test_carplay_entitlements_accepts_communication_template(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "LorvexCarPlay.entitlements"
            with path.open("wb") as file:
                plistlib.dump({"com.apple.developer.carplay-communication": True}, file)

            failures: list[str] = []
            verify_carplay_entitlements(path, failures)

            self.assertEqual(failures, [])

    def test_carplay_entitlements_rejects_stale_category_keys(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "LorvexCarPlay.entitlements"
            with path.open("wb") as file:
                plistlib.dump({
                    "com.apple.developer.carplay-communication": True,
                    "com.apple.developer.carplay-maps": True,
                }, file)

            failures: list[str] = []
            verify_carplay_entitlements(path, failures)

            self.assertEqual(
                failures,
                [
                    f"{path} declares unsupported CarPlay entitlement(s): "
                    "['com.apple.developer.carplay-maps']"
                ],
            )

    def test_carplay_entitlements_requires_communication_key(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "LorvexCarPlay.entitlements"
            with path.open("wb") as file:
                plistlib.dump({}, file)

            failures: list[str] = []
            verify_carplay_entitlements(path, failures)

            self.assertEqual(
                failures,
                [f"{path} missing com.apple.developer.carplay-communication"],
            )

    def test_mobile_info_plist_accepts_commented_carplay_template(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "LorvexMobileApp-Info.plist"
            path.write_text(
                """
                <plist version="1.0">
                <dict>
                  <!--
                  CarPlay activation template.
                  Config/LorvexCarPlay.entitlements
                  <key>CPSupportsTemplateApplicationScene</key>
                  <true/>
                  <key>UIApplicationSceneManifest</key>
                  <dict>
                    <key>CPTemplateApplicationSceneSessionRoleApplication</key>
                    <array>
                      <dict>
                        <key>UISceneClassName</key>
                        <string>CPTemplateApplicationScene</string>
                        <key>UISceneDelegateClassName</key>
                        <string>LorvexCarPlay.LorvexCarPlaySceneDelegate</string>
                      </dict>
                    </array>
                  </dict>
                  -->
                </dict>
                </plist>
                """,
                encoding="utf-8",
            )

            failures: list[str] = []
            verify_mobile_carplay_activation_template(path, failures)

            self.assertEqual(failures, [])

    def test_mobile_info_plist_rejects_active_carplay_scene_keys(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "LorvexMobileApp-Info.plist"
            path.write_text(
                """
                <plist version="1.0">
                <dict>
                  <!--
                  CarPlay activation template.
                  Config/LorvexCarPlay.entitlements
                  <key>CPSupportsTemplateApplicationScene</key>
                  <key>UIApplicationSceneManifest</key>
                  <key>CPTemplateApplicationSceneSessionRoleApplication</key>
                  <string>CPTemplateApplicationScene</string>
                  <string>LorvexCarPlay.LorvexCarPlaySceneDelegate</string>
                  -->
                  <key>CPSupportsTemplateApplicationScene</key>
                  <true/>
                </dict>
                </plist>
                """,
                encoding="utf-8",
            )

            failures: list[str] = []
            verify_mobile_carplay_activation_template(path, failures)

            self.assertEqual(
                failures,
                [
                    f"{path} has active CarPlay scene keys before provisioning: "
                    "['CPSupportsTemplateApplicationScene']"
                ],
            )


class VerifyExportComplianceKeyTests(unittest.TestCase):
    def test_accepts_plist_declaring_false(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Info.plist"
            with path.open("wb") as file:
                plistlib.dump({"ITSAppUsesNonExemptEncryption": False}, file)

            failures: list[str] = []
            verify_export_compliance_key(path, failures)

            self.assertEqual(failures, [])

    def test_rejects_plist_declaring_true(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Info.plist"
            with path.open("wb") as file:
                plistlib.dump({"ITSAppUsesNonExemptEncryption": True}, file)

            failures: list[str] = []
            verify_export_compliance_key(path, failures)

            self.assertEqual(
                failures,
                [
                    f"{path} must declare ITSAppUsesNonExemptEncryption=false "
                    "(Lorvex only uses exempt SHA-256 hashing)"
                ],
            )

    def test_rejects_plist_missing_key(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Info.plist"
            with path.open("wb") as file:
                plistlib.dump({"CFBundleIdentifier": "com.lorvex.apple"}, file)

            failures: list[str] = []
            verify_export_compliance_key(path, failures)

            self.assertEqual(
                failures,
                [
                    f"{path} must declare ITSAppUsesNonExemptEncryption=false "
                    "(Lorvex only uses exempt SHA-256 hashing)"
                ],
            )

    def test_rejects_missing_file(self) -> None:
        path = Path("/nonexistent/Info.plist")
        failures: list[str] = []
        verify_export_compliance_key(path, failures)

        self.assertEqual(
            failures,
            ["missing Info.plist for export-compliance check: /nonexistent/Info.plist"],
        )


class VerifyMacosExportComplianceMarkerTests(unittest.TestCase):
    def test_accepts_heredoc_declaring_false(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "build_and_run.sh"
            path.write_text(
                "cat >\"$INFO_PLIST\" <<PLIST\n"
                "  <key>ITSAppUsesNonExemptEncryption</key>\n"
                "  <false/>\n"
                "PLIST\n",
                encoding="utf-8",
            )

            failures: list[str] = []
            verify_macos_export_compliance_marker(path, failures)

            self.assertEqual(failures, [])

    def test_rejects_heredoc_declaring_true(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "build_and_run.sh"
            path.write_text(
                "  <key>ITSAppUsesNonExemptEncryption</key>\n"
                "  <true/>\n",
                encoding="utf-8",
            )

            failures: list[str] = []
            verify_macos_export_compliance_marker(path, failures)

            self.assertEqual(
                failures,
                [
                    f"{path} must set ITSAppUsesNonExemptEncryption to false in the "
                    "generated macOS Info.plist heredoc"
                ],
            )

    def test_rejects_heredoc_missing_key(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "build_and_run.sh"
            path.write_text("  <key>LSApplicationCategoryType</key>\n", encoding="utf-8")

            failures: list[str] = []
            verify_macos_export_compliance_marker(path, failures)

            self.assertEqual(
                failures,
                [
                    f"{path} must set ITSAppUsesNonExemptEncryption to false in the "
                    "generated macOS Info.plist heredoc"
                ],
            )


if __name__ == "__main__":
    unittest.main()
