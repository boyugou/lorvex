#!/usr/bin/env python3
from __future__ import annotations

import unittest

from verify_source_entitlements import (
    ROOT,
    overbroad_entitlement_failures,
    source_entitlement_files,
)

# A well-formed, minimal entitlements dict of the kind Lorvex ships today.
CLEAN = {
    "com.apple.security.app-sandbox": True,
    "com.apple.security.files.user-selected.read-write": True,
    "com.apple.security.personal-information.calendars": True,
    "com.apple.security.application-groups": ["group.com.lorvex.apple"],
}


class OverbroadEntitlementTests(unittest.TestCase):
    def test_clean_entitlements_pass(self) -> None:
        self.assertEqual(overbroad_entitlement_failures("clean", CLEAN), [])

    def test_sandbox_true_is_not_flagged(self) -> None:
        self.assertEqual(
            overbroad_entitlement_failures(
                "x", {"com.apple.security.app-sandbox": True}
            ),
            [],
        )

    def test_disabled_sandbox_fails(self) -> None:
        failures = overbroad_entitlement_failures(
            "x", {"com.apple.security.app-sandbox": False}
        )
        self.assertEqual(len(failures), 1)
        self.assertIn("disables the App Sandbox", failures[0])

    def test_network_client_fails(self) -> None:
        self.assertTrue(
            overbroad_entitlement_failures(
                "x", {"com.apple.security.network.client": True}
            )
        )

    def test_network_server_fails(self) -> None:
        self.assertTrue(
            overbroad_entitlement_failures(
                "x", {"com.apple.security.network.server": True}
            )
        )

    def test_files_all_fails(self) -> None:
        self.assertTrue(
            overbroad_entitlement_failures(
                "x", {"com.apple.security.files.all": True}
            )
        )

    def test_temporary_exception_any_key_fails(self) -> None:
        failures = overbroad_entitlement_failures(
            "x",
            {
                "com.apple.security.temporary-exception.files.absolute-path.read-write": [
                    "/"
                ]
            },
        )
        self.assertEqual(len(failures), 1)
        self.assertIn("temporary-exception", failures[0])

    def test_multiple_overbroad_grants_all_reported(self) -> None:
        failures = overbroad_entitlement_failures(
            "x",
            {
                "com.apple.security.app-sandbox": False,
                "com.apple.security.network.client": True,
                "com.apple.security.temporary-exception.mach-lookup.global-name": ["y"],
            },
        )
        self.assertEqual(len(failures), 3)


class SourceEntitlementFilesTests(unittest.TestCase):
    def test_repo_entitlements_are_discovered_and_clean(self) -> None:
        files = source_entitlement_files(ROOT)
        self.assertTrue(files, "expected Config/*.entitlements to be discovered")
        for path in files:
            self.assertNotIn(".build", path.parts)

    def test_all_shipped_entitlements_pass_the_gate(self) -> None:
        import plistlib

        for path in source_entitlement_files(ROOT):
            with path.open("rb") as file:
                entitlements = plistlib.load(file)
            self.assertEqual(
                overbroad_entitlement_failures(str(path), entitlements),
                [],
                f"{path} unexpectedly flagged as over-broad",
            )


if __name__ == "__main__":
    unittest.main()
