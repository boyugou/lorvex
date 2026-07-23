#!/usr/bin/env python3
from __future__ import annotations

import sys
import unittest

from pathlib import Path

import verify_codesign_entitlements
from verify_codesign_entitlements import (
    check_cloudkit_entitlements,
    check_sandbox_entitlement,
    helper_bundle_identifier_failures,
    is_local_signature,
    check_core_entitlements,
    check_developer_id_signature_details,
    non_sandboxed_executable_failures,
)


class VerifyCodesignEntitlementsTests(unittest.TestCase):
    def test_core_entitlements_accept_required_app_group(self) -> None:
        self.assertEqual(
            check_core_entitlements(
                "signed app",
                {"com.apple.security.application-groups": ["group.com.lorvex.apple"]},
                "group.com.lorvex.apple",
            ),
            [],
        )

    def test_core_entitlements_reject_missing_required_app_group(self) -> None:
        self.assertEqual(
            check_core_entitlements(
                "embedded widget",
                {"com.apple.security.application-groups": ["group.other"]},
                "group.com.lorvex.apple",
            ),
            [
                "embedded widget is missing app group 'group.com.lorvex.apple': "
                "['group.other']"
            ],
        )

    def test_core_entitlements_reject_absent_app_group_entitlement(self) -> None:
        self.assertEqual(
            check_core_entitlements("signed app", {}, "group.com.lorvex.apple"),
            ["signed app is missing app group 'group.com.lorvex.apple': []"],
        )

    def test_cloudkit_entitlements_accept_mas_live_sync_requirements(self) -> None:
        self.assertEqual(
            check_cloudkit_entitlements(
                "signed app",
                {
                    "com.apple.developer.icloud-container-identifiers": [
                        "iCloud.com.lorvex.apple"
                    ],
                    "com.apple.developer.icloud-services": ["CloudKit"],
                    "com.apple.developer.aps-environment": "production",
                },
                "iCloud.com.lorvex.apple",
                require_cloudkit=True,
                require_production_aps=True,
            ),
            [],
        )

    def test_cloudkit_entitlements_reject_missing_required_mas_fields(self) -> None:
        self.assertEqual(
            check_cloudkit_entitlements(
                "signed app",
                {
                    "com.apple.developer.icloud-container-identifiers": [
                        "iCloud.com.other"
                    ],
                    "com.apple.developer.icloud-services": ["Documents"],
                    "com.apple.developer.aps-environment": "development",
                },
                "iCloud.com.lorvex.apple",
                require_cloudkit=True,
                require_production_aps=True,
            ),
            [
                "signed app CloudKit container entitlement ['iCloud.com.other'] "
                "does not include 'iCloud.com.lorvex.apple'",
                "signed app iCloud services entitlement ['Documents'] does not include "
                "'CloudKit'",
                "signed app must use com.apple.developer.aps-environment 'production' "
                "for MAS live sync, got 'development'",
            ],
        )

    def test_cloudkit_entitlements_can_be_optional_for_developer_id(self) -> None:
        self.assertEqual(
            check_cloudkit_entitlements(
                "signed app",
                {},
                "iCloud.com.lorvex.apple",
                require_cloudkit=False,
                require_production_aps=False,
            ),
            [],
        )

    def test_developer_id_signature_details_accept_hardened_runtime_and_team(self) -> None:
        self.assertEqual(
            check_developer_id_signature_details(
                "Executable=/Applications/LorvexApple.app/Contents/MacOS/LorvexApple\n"
                "flags=0x10000(runtime)\n"
                "TeamIdentifier=ABCDE12345\n"
            ),
            [],
        )

    def test_developer_id_signature_details_accept_codesign_code_directory_line(self) -> None:
        self.assertEqual(
            check_developer_id_signature_details(
                "CodeDirectory v=20500 size=97084 flags=0x10000(runtime) hashes=3023+7\n"
                "TeamIdentifier=ABCDE12345\n"
            ),
            [],
        )

    def test_developer_id_signature_details_reject_missing_runtime(self) -> None:
        self.assertEqual(
            check_developer_id_signature_details(
                "flags=0x0(none)\n"
                "TeamIdentifier=ABCDE12345\n"
            ),
            ["signed app is not hardened (flags='0x0(none)'); CODE_SIGN_IDENTITY is set"],
        )

    def test_developer_id_signature_details_reject_missing_or_adhoc_team(self) -> None:
        self.assertEqual(
            check_developer_id_signature_details(
                "flags=0x10000(runtime)\n"
                "TeamIdentifier=not set\n"
            ),
            ["signed app has no TeamIdentifier (ad-hoc signature) but CODE_SIGN_IDENTITY is set"],
        )


class CheckSandboxEntitlementTests(unittest.TestCase):
    def test_accepts_sandbox_true(self) -> None:
        self.assertEqual(
            check_sandbox_entitlement("MCP helper", {"com.apple.security.app-sandbox": True}),
            [],
        )

    def test_rejects_missing_sandbox(self) -> None:
        self.assertEqual(
            check_sandbox_entitlement("MCP helper", {}),
            ["MCP helper is missing the app-sandbox entitlement"],
        )


class HelperBundleIdentifierFailuresTests(unittest.TestCase):
    def test_accepts_matching_bundle_id(self) -> None:
        self.assertEqual(
            helper_bundle_identifier_failures(
                {"CFBundleIdentifier": "com.lorvex.apple.mcp-host"},
                "com.lorvex.apple.mcp-host",
            ),
            [],
        )

    def test_rejects_mismatched_bundle_id(self) -> None:
        self.assertEqual(
            helper_bundle_identifier_failures(
                {"CFBundleIdentifier": "com.lorvex.apple"},
                "com.lorvex.apple.mcp-host",
            ),
            [
                "MCP helper Info.plist CFBundleIdentifier mismatch: "
                "expected 'com.lorvex.apple.mcp-host', got 'com.lorvex.apple'"
            ],
        )


class NonSandboxedExecutableFailuresTests(unittest.TestCase):
    def test_accepts_all_sandboxed_executables(self) -> None:
        app = Path("/App.app/Contents/MacOS/App")
        helper = Path("/App.app/Contents/Helpers/Host.app/Contents/MacOS/Host")
        self.assertEqual(
            non_sandboxed_executable_failures(
                [app, helper],
                {
                    app: {"com.apple.security.app-sandbox": True},
                    helper: {"com.apple.security.app-sandbox": True},
                },
            ),
            [],
        )

    def test_rejects_executable_missing_sandbox_entitlement(self) -> None:
        helper = Path("/App.app/Contents/Helpers/Host.app/Contents/MacOS/Host")
        self.assertEqual(
            non_sandboxed_executable_failures(
                [helper],
                {helper: {"com.apple.security.application-groups": ["group.com.lorvex.apple"]}},
            ),
            [f"non-sandboxed executable in signed bundle: {helper}"],
        )

    def test_rejects_executable_with_unreadable_entitlements(self) -> None:
        helper = Path("/App.app/Contents/Helpers/Host.app/Contents/MacOS/Host")
        self.assertEqual(
            non_sandboxed_executable_failures([helper], {}),
            [f"non-sandboxed executable in signed bundle: {helper}"],
        )


class ModuleImportsTests(unittest.TestCase):
    def test_module_binds_sys_for_failure_reporting(self) -> None:
        # main() writes each failure to sys.stderr; without `import sys` the
        # verifier raised NameError at exactly the moment it had a real
        # entitlement failure to report.
        self.assertIs(verify_codesign_entitlements.sys, sys)


class IsLocalSignatureTests(unittest.TestCase):
    def test_adhoc_signature_is_local(self):
        self.assertTrue(is_local_signature("CodeDirectory v\nSignature=adhoc\n"))

    def test_missing_team_identifier_is_local(self):
        self.assertTrue(is_local_signature("flags=0x10000(runtime)\nTeamIdentifier=not set\n"))

    def test_real_identity_is_not_local(self):
        details = "flags=0x10000(runtime)\nTeamIdentifier=ABCDE12345\nAuthority=Developer ID Application: X\n"
        self.assertFalse(is_local_signature(details))


if __name__ == "__main__":
    unittest.main()
