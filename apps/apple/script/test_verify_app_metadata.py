#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import plistlib
import tempfile
import unittest

from verify_app_metadata import (
    verify_drag_type_declarations_in_plist,
    verify_entitlements,
    verify_export_compliance_key,
    verify_macos_drag_type_declarations,
    verify_macos_export_compliance_marker,
)


class VerifyAppMetadataTests(unittest.TestCase):
    def test_entitlements_forbid_aps_environment_rejects_push_capability(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "LorvexNoPushCapability.entitlements"
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
            path = Path(directory) / "LorvexNoPushCapability.entitlements"
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

TASK_REF = "com.lorvex.apple.task-ref"


def declaration(identifier: str, conforms_to: list[str]) -> dict:
    return {"UTTypeIdentifier": identifier, "UTTypeConformsTo": conforms_to}


class VerifyDragTypeDeclarationsTests(unittest.TestCase):
    def test_plist_accepts_a_declared_public_data_type(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Info.plist"
            with path.open("wb") as file:
                plistlib.dump(
                    {"UTExportedTypeDeclarations": [declaration(TASK_REF, ["public.data"])]}, file
                )
            failures: list[str] = []
            verify_drag_type_declarations_in_plist(path, [TASK_REF], failures)
            self.assertEqual(failures, [])

    def test_plist_rejects_a_missing_declaration(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Info.plist"
            with path.open("wb") as file:
                plistlib.dump({}, file)
            failures: list[str] = []
            verify_drag_type_declarations_in_plist(path, [TASK_REF], failures)
            self.assertEqual(len(failures), 1)
            self.assertIn(f"must export {TASK_REF}", failures[0])

    def test_plist_rejects_a_type_that_does_not_conform_to_public_data(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Info.plist"
            with path.open("wb") as file:
                plistlib.dump(
                    {"UTExportedTypeDeclarations": [declaration(TASK_REF, ["public.item"])]}, file
                )
            failures: list[str] = []
            verify_drag_type_declarations_in_plist(path, [TASK_REF], failures)
            self.assertEqual(len(failures), 1)
            self.assertIn("conforming to public.data", failures[0])

    def test_macos_heredoc_accepts_a_declared_type_beside_shell_variables(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "build_and_run.sh"
            path.write_text(
                "cat >\"$INFO_PLIST\" <<PLIST\n"
                '<?xml version="1.0" encoding="UTF-8"?>\n'
                '<plist version="1.0">\n<dict>\n'
                "  <key>CFBundleName</key>\n  <string>$APP_DISPLAY_NAME</string>\n"
                "  <key>UTExportedTypeDeclarations</key>\n  <array>\n    <dict>\n"
                f"      <key>UTTypeIdentifier</key>\n      <string>{TASK_REF}</string>\n"
                "      <key>UTTypeConformsTo</key>\n      <array>\n"
                "        <string>public.data</string>\n      </array>\n"
                "    </dict>\n  </array>\n</dict>\n</plist>\n"
                "PLIST\n",
                encoding="utf-8",
            )
            failures: list[str] = []
            verify_macos_drag_type_declarations(path, [TASK_REF], failures)
            self.assertEqual(failures, [])

    def test_macos_heredoc_rejects_a_missing_declaration(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "build_and_run.sh"
            path.write_text(
                "cat >\"$INFO_PLIST\" <<PLIST\n"
                '<?xml version="1.0" encoding="UTF-8"?>\n'
                '<plist version="1.0">\n<dict>\n'
                "  <key>CFBundleName</key>\n  <string>$APP_DISPLAY_NAME</string>\n"
                "</dict>\n</plist>\n"
                "PLIST\n",
                encoding="utf-8",
            )
            failures: list[str] = []
            verify_macos_drag_type_declarations(path, [TASK_REF], failures)
            self.assertEqual(len(failures), 1)
            self.assertIn(f"must export {TASK_REF}", failures[0])


if __name__ == "__main__":
    unittest.main()
