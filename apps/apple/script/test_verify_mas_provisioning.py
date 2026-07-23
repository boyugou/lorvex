#!/usr/bin/env python3
from __future__ import annotations

import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from verify_mas_provisioning import (
    embeddable_targets,
    entitlements_plan_coverage_failures,
    helper_bundle_structure_failures,
    profile_app_group_failures,
    profile_application_identifier,
    profile_aps_environment_failures,
    profile_bundle_identifier_failures,
    profile_certificate_class_failures,
    profile_cross_check_failures,
    profile_distribution_type_failures,
    profile_expiry_failures,
    profile_icloud_container_failures,
    profile_icloud_environment_failures,
    profile_team_consistency_failures,
    profile_team_identifier,
    profile_type_failures,
)


def fake_profile(entitlements: dict) -> dict:
    """A synthetic decoded-profile plist shaped like the output of
    `security cms -D -i some.provisionprofile` — everything under this
    test module exercises only the parsed-plist cross-check logic, never the
    real CMS decode, so no signing credentials are required to test it."""
    return {"Entitlements": entitlements}


class ProfileApplicationIdentifierTests(unittest.TestCase):
    def test_prefers_native_macos_key(self) -> None:
        profile = fake_profile(
            {
                "com.apple.application-identifier": "ABCDE12345.com.lorvex.apple",
                "application-identifier": "ABCDE12345.com.lorvex.apple.mobile",
            }
        )
        self.assertEqual(
            profile_application_identifier(profile), "ABCDE12345.com.lorvex.apple"
        )

    def test_falls_back_to_ios_style_key(self) -> None:
        profile = fake_profile({"application-identifier": "ABCDE12345.com.lorvex.apple"})
        self.assertEqual(
            profile_application_identifier(profile), "ABCDE12345.com.lorvex.apple"
        )

    def test_missing_both_keys_returns_empty_string(self) -> None:
        self.assertEqual(profile_application_identifier(fake_profile({})), "")


class ProfileBundleIdentifierFailuresTests(unittest.TestCase):
    def test_accepts_matching_bundle_id(self) -> None:
        profile = fake_profile(
            {"com.apple.application-identifier": "ABCDE12345.com.lorvex.apple"}
        )
        self.assertEqual(
            profile_bundle_identifier_failures("macOS app", profile, "com.lorvex.apple"),
            [],
        )

    def test_rejects_mismatched_bundle_id(self) -> None:
        profile = fake_profile(
            {"com.apple.application-identifier": "ABCDE12345.com.lorvex.apple.mobile"}
        )
        self.assertEqual(
            profile_bundle_identifier_failures("macOS app", profile, "com.lorvex.apple"),
            [
                "macOS app profile provisions bundle id 'com.lorvex.apple.mobile', "
                "expected 'com.lorvex.apple'"
            ],
        )

    def test_rejects_malformed_application_identifier(self) -> None:
        profile = fake_profile({"com.apple.application-identifier": "no-dot-here"})
        self.assertEqual(
            profile_bundle_identifier_failures("macOS app", profile, "com.lorvex.apple"),
            ["macOS app profile application-identifier is malformed: 'no-dot-here'"],
        )

    def test_rejects_missing_application_identifier(self) -> None:
        profile = fake_profile({})
        self.assertEqual(
            profile_bundle_identifier_failures("macOS app", profile, "com.lorvex.apple"),
            ["macOS app profile application-identifier is malformed: ''"],
        )

    def test_accepts_ios_style_key_as_fallback(self) -> None:
        """Platform-aware key selection still resolves a profile that only
        carries the bare iOS-family key, so a profile downloaded for the
        wrong platform reports a real mismatch rather than always failing
        with an empty application identifier."""
        profile = fake_profile({"application-identifier": "ABCDE12345.com.lorvex.apple"})
        self.assertEqual(
            profile_bundle_identifier_failures("macOS app", profile, "com.lorvex.apple"),
            [],
        )


class ProfileAppGroupFailuresTests(unittest.TestCase):
    def test_no_failure_when_target_declares_no_app_group(self) -> None:
        profile = fake_profile({})
        self.assertEqual(profile_app_group_failures("macOS app", profile, {}), [])

    def test_accepts_profile_authorizing_required_group(self) -> None:
        profile = fake_profile(
            {"com.apple.security.application-groups": ["group.com.lorvex.apple"]}
        )
        target = {"com.apple.security.application-groups": ["group.com.lorvex.apple"]}
        self.assertEqual(profile_app_group_failures("macOS app", profile, target), [])

    def test_rejects_profile_missing_required_group(self) -> None:
        profile = fake_profile({"com.apple.security.application-groups": ["group.other"]})
        target = {"com.apple.security.application-groups": ["group.com.lorvex.apple"]}
        self.assertEqual(
            profile_app_group_failures("MCP helper", profile, target),
            [
                "MCP helper profile is missing App Group(s) ['group.com.lorvex.apple']: "
                "profile authorizes ['group.other']"
            ],
        )


class ProfileIcloudContainerFailuresTests(unittest.TestCase):
    def test_no_failure_when_target_declares_no_container(self) -> None:
        profile = fake_profile({})
        self.assertEqual(profile_icloud_container_failures("macOS app", profile, {}), [])

    def test_accepts_profile_authorizing_required_container(self) -> None:
        profile = fake_profile(
            {"com.apple.developer.icloud-container-identifiers": ["iCloud.com.lorvex.apple"]}
        )
        target = {
            "com.apple.developer.icloud-container-identifiers": ["iCloud.com.lorvex.apple"]
        }
        self.assertEqual(profile_icloud_container_failures("macOS app", profile, target), [])

    def test_rejects_profile_missing_required_container(self) -> None:
        profile = fake_profile(
            {"com.apple.developer.icloud-container-identifiers": ["iCloud.com.other"]}
        )
        target = {
            "com.apple.developer.icloud-container-identifiers": ["iCloud.com.lorvex.apple"]
        }
        self.assertEqual(
            profile_icloud_container_failures("macOS app", profile, target),
            [
                "macOS app profile is missing iCloud container(s) "
                "['iCloud.com.lorvex.apple']: profile authorizes ['iCloud.com.other']"
            ],
        )


class ProfileApsEnvironmentFailuresTests(unittest.TestCase):
    def test_no_failure_when_target_declares_no_aps_environment(self) -> None:
        profile = fake_profile({"com.apple.developer.aps-environment": "development"})
        self.assertEqual(profile_aps_environment_failures("macOS app", profile, {}), [])

    def test_accepts_matching_production_aps_environment(self) -> None:
        profile = fake_profile({"com.apple.developer.aps-environment": "production"})
        target = {"com.apple.developer.aps-environment": "production"}
        self.assertEqual(profile_aps_environment_failures("macOS app", profile, target), [])

    def test_rejects_mismatched_aps_environment(self) -> None:
        profile = fake_profile({"com.apple.developer.aps-environment": "development"})
        target = {"com.apple.developer.aps-environment": "production"}
        self.assertEqual(
            profile_aps_environment_failures("macOS app", profile, target),
            [
                "macOS app profile aps-environment 'development' does not match "
                "required 'production'"
            ],
        )


class ProfileIcloudEnvironmentFailuresTests(unittest.TestCase):
    def test_no_failure_when_target_declares_no_environment(self) -> None:
        profile = fake_profile(
            {"com.apple.developer.icloud-container-environment": ["Production"]}
        )
        self.assertEqual(profile_icloud_environment_failures("macOS app", profile, {}), [])

    def test_accepts_profile_authorizing_required_production(self) -> None:
        profile = fake_profile(
            {"com.apple.developer.icloud-container-environment": ["Production"]}
        )
        target = {"com.apple.developer.icloud-container-environment": "Production"}
        self.assertEqual(
            profile_icloud_environment_failures("macOS app", profile, target), []
        )

    def test_rejects_development_environment_profile(self) -> None:
        profile = fake_profile(
            {"com.apple.developer.icloud-container-environment": ["Development"]}
        )
        target = {"com.apple.developer.icloud-container-environment": "Production"}
        self.assertEqual(
            profile_icloud_environment_failures("macOS app", profile, target),
            [
                "macOS app profile icloud-container-environment ['Development'] "
                "does not authorize required 'Production'"
            ],
        )

    def test_accepts_scalar_profile_environment(self) -> None:
        profile = fake_profile(
            {"com.apple.developer.icloud-container-environment": "Production"}
        )
        target = {"com.apple.developer.icloud-container-environment": "Production"}
        self.assertEqual(
            profile_icloud_environment_failures("macOS app", profile, target), []
        )


class ProfileDistributionTypeFailuresTests(unittest.TestCase):
    def test_accepts_distribution_profile(self) -> None:
        profile = fake_profile({"com.apple.developer.aps-environment": "production"})
        self.assertEqual(profile_distribution_type_failures("macOS app", profile), [])

    def test_rejects_profile_with_provisioned_devices(self) -> None:
        profile = {"Entitlements": {}, "ProvisionedDevices": ["00008030-000"]}
        self.assertEqual(
            profile_distribution_type_failures("macOS app", profile),
            [
                "macOS app profile is a development profile (declares ProvisionedDevices), "
                "not an App Store distribution profile"
            ],
        )

    def test_rejects_profile_with_get_task_allow(self) -> None:
        profile = {"Entitlements": {"get-task-allow": True}}
        self.assertEqual(
            profile_distribution_type_failures("MCP helper", profile),
            [
                "MCP helper profile is a development profile (get-task-allow is true), "
                "not an App Store distribution profile"
            ],
        )

    def test_reports_both_development_markers(self) -> None:
        profile = {
            "Entitlements": {"get-task-allow": True},
            "ProvisionedDevices": ["00008030-000"],
        }
        self.assertEqual(len(profile_distribution_type_failures("macOS app", profile)), 2)

    def test_rejects_profile_with_provisions_all_devices(self) -> None:
        """ProvisionsAllDevices is the Developer ID / enterprise ("in-house")
        marker — it never appears on an App Store distribution profile, so a
        profile carrying it must be rejected for a MAS package even when it has
        neither ProvisionedDevices nor get-task-allow."""
        profile = {"Entitlements": {}, "ProvisionsAllDevices": True}
        self.assertEqual(
            profile_distribution_type_failures("macOS app", profile),
            [
                "macOS app profile is a Developer ID / enterprise profile "
                "(ProvisionsAllDevices is true), not an App Store distribution profile"
            ],
        )

    def test_accepts_profile_without_provisions_all_devices_flag(self) -> None:
        # A distribution profile may carry the key set false; only a truthy
        # value marks the enterprise/Developer ID channel.
        profile = {"Entitlements": {}, "ProvisionsAllDevices": False}
        self.assertEqual(profile_distribution_type_failures("macOS app", profile), [])


class ProfileCertificateClassFailuresTests(unittest.TestCase):
    def test_no_failure_when_no_certificate_subjects(self) -> None:
        # Certificates absent or unparseable (openssl missing) — soft-skip.
        self.assertEqual(profile_certificate_class_failures("macOS app", []), [])

    def test_accepts_apple_distribution_certificate(self) -> None:
        subjects = ["subject=UID=ABCDE12345, CN=Apple Distribution: Example Inc (ABCDE12345)"]
        self.assertEqual(profile_certificate_class_failures("macOS app", subjects), [])

    def test_accepts_legacy_mac_app_distribution_certificate(self) -> None:
        subjects = ["subject=CN=3rd Party Mac Developer Application: Example Inc (ABCDE12345)"]
        self.assertEqual(profile_certificate_class_failures("macOS app", subjects), [])

    def test_rejects_developer_id_application_certificate(self) -> None:
        subjects = ["subject=CN=Developer ID Application: Example Inc (ABCDE12345)"]
        failures = profile_certificate_class_failures("MCP helper", subjects)
        self.assertEqual(len(failures), 1)
        self.assertIn("Developer ID certificate", failures[0])
        self.assertIn("not an App Store distribution certificate", failures[0])

    def test_rejects_developer_id_installer_certificate(self) -> None:
        subjects = ["subject=CN=Developer ID Installer: Example Inc (ABCDE12345)"]
        self.assertEqual(len(profile_certificate_class_failures("macOS app", subjects)), 1)


class ProfileTypeFailuresTests(unittest.TestCase):
    def test_no_failure_when_platform_absent(self) -> None:
        self.assertEqual(profile_type_failures("macOS app", fake_profile({})), [])

    def test_accepts_osx_platform(self) -> None:
        profile = {"Entitlements": {}, "Platform": ["OSX"]}
        self.assertEqual(profile_type_failures("macOS app", profile), [])

    def test_rejects_non_macos_platform(self) -> None:
        profile = {"Entitlements": {}, "Platform": ["iOS"]}
        self.assertEqual(
            profile_type_failures("macOS app", profile),
            ["macOS app profile is not a macOS distribution profile: Platform=['iOS']"],
        )


class ProfileExpiryFailuresTests(unittest.TestCase):
    def test_no_failure_when_expiration_absent(self) -> None:
        self.assertEqual(profile_expiry_failures("macOS app", fake_profile({})), [])

    def test_accepts_future_expiration(self) -> None:
        now = datetime(2026, 1, 1, tzinfo=timezone.utc)
        profile = {"Entitlements": {}, "ExpirationDate": now + timedelta(days=30)}
        self.assertEqual(profile_expiry_failures("macOS app", profile, now=now), [])

    def test_rejects_expired_profile(self) -> None:
        now = datetime(2026, 1, 1, tzinfo=timezone.utc)
        expiration = now - timedelta(days=1)
        profile = {"Entitlements": {}, "ExpirationDate": expiration}
        self.assertEqual(
            profile_expiry_failures("macOS app", profile, now=now),
            [f"macOS app provisioning profile expired on {expiration.isoformat()}"],
        )

    def test_treats_naive_expiration_as_utc(self) -> None:
        now = datetime(2026, 1, 1, tzinfo=timezone.utc)
        # plistlib decodes <date> elements as naive datetimes; the profile
        # audit must not crash comparing them against an aware "now".
        profile = {"Entitlements": {}, "ExpirationDate": datetime(2025, 12, 31)}
        failures = profile_expiry_failures("macOS app", profile, now=now)
        self.assertEqual(len(failures), 1)


class ProfileTeamIdentifierTests(unittest.TestCase):
    def test_returns_first_team_when_present(self) -> None:
        self.assertEqual(
            profile_team_identifier({"TeamIdentifier": ["ABCDE12345"]}), "ABCDE12345"
        )

    def test_returns_none_when_absent(self) -> None:
        self.assertIsNone(profile_team_identifier({}))

    def test_returns_none_when_empty(self) -> None:
        self.assertIsNone(profile_team_identifier({"TeamIdentifier": []}))


class ProfileTeamConsistencyFailuresTests(unittest.TestCase):
    def test_no_failure_when_all_teams_match(self) -> None:
        self.assertEqual(
            profile_team_consistency_failures(
                {"macOS app": "ABCDE12345", "MCP helper": "ABCDE12345"}
            ),
            [],
        )

    def test_no_failure_with_single_or_no_profile(self) -> None:
        self.assertEqual(profile_team_consistency_failures({}), [])
        self.assertEqual(
            profile_team_consistency_failures({"macOS app": "ABCDE12345"}), []
        )

    def test_rejects_mismatched_teams(self) -> None:
        failures = profile_team_consistency_failures(
            {"macOS app": "ABCDE12345", "MCP helper": "ZYXWV98765"}
        )
        self.assertEqual(len(failures), 1)
        self.assertIn("disagree on TeamIdentifier", failures[0])


class ProfileCrossCheckFailuresTests(unittest.TestCase):
    def test_accepts_fully_matching_profile(self) -> None:
        profile = fake_profile(
            {
                "com.apple.application-identifier": "ABCDE12345.com.lorvex.apple",
                "com.apple.security.application-groups": ["group.com.lorvex.apple"],
                "com.apple.developer.icloud-container-identifiers": [
                    "iCloud.com.lorvex.apple"
                ],
                "com.apple.developer.aps-environment": "production",
            }
        )
        target_entitlements = {
            "com.apple.security.application-groups": ["group.com.lorvex.apple"],
            "com.apple.developer.icloud-container-identifiers": ["iCloud.com.lorvex.apple"],
            "com.apple.developer.aps-environment": "production",
        }
        self.assertEqual(
            profile_cross_check_failures(
                "macOS app", profile, target_entitlements, "com.lorvex.apple"
            ),
            [],
        )

    def test_reports_every_mismatch_at_once(self) -> None:
        profile = fake_profile(
            {
                "com.apple.application-identifier": "ABCDE12345.com.wrong.bundle",
                "com.apple.security.application-groups": ["group.other"],
                "com.apple.developer.icloud-container-identifiers": ["iCloud.com.other"],
                "com.apple.developer.aps-environment": "development",
            }
        )
        target_entitlements = {
            "com.apple.security.application-groups": ["group.com.lorvex.apple"],
            "com.apple.developer.icloud-container-identifiers": ["iCloud.com.lorvex.apple"],
            "com.apple.developer.aps-environment": "production",
        }
        failures = profile_cross_check_failures(
            "macOS app", profile, target_entitlements, "com.lorvex.apple"
        )
        self.assertEqual(len(failures), 4)

    def test_includes_profile_type_check(self) -> None:
        """profile_cross_check_failures folds in profile_type_failures, so a
        profile downloaded for the wrong platform is caught alongside the
        bundle id / entitlement mismatches, not just when called directly."""
        profile = {
            "Entitlements": {
                "com.apple.application-identifier": "ABCDE12345.com.lorvex.apple",
            },
            "Platform": ["iOS"],
        }
        failures = profile_cross_check_failures("macOS app", profile, {}, "com.lorvex.apple")
        self.assertEqual(
            failures,
            ["macOS app profile is not a macOS distribution profile: Platform=['iOS']"],
        )

    def test_rejects_development_profile(self) -> None:
        """A development provisioning profile — enumerating ProvisionedDevices,
        allowing task-get, and scoped to the Development iCloud environment —
        fails the cross-check even when its bundle id and platform match."""
        profile = {
            "Entitlements": {
                "com.apple.application-identifier": "ABCDE12345.com.lorvex.apple",
                "com.apple.developer.icloud-container-environment": ["Development"],
                "get-task-allow": True,
            },
            "Platform": ["OSX"],
            "ProvisionedDevices": ["00008030-000"],
        }
        target_entitlements = {
            "com.apple.developer.icloud-container-environment": "Production",
        }
        failures = profile_cross_check_failures(
            "macOS app", profile, target_entitlements, "com.lorvex.apple"
        )
        self.assertEqual(
            failures,
            [
                "macOS app profile icloud-container-environment ['Development'] "
                "does not authorize required 'Production'",
                "macOS app profile is a development profile (declares ProvisionedDevices), "
                "not an App Store distribution profile",
                "macOS app profile is a development profile (get-task-allow is true), "
                "not an App Store distribution profile",
            ],
        )

    def test_rejects_developer_id_profile(self) -> None:
        """A Developer ID / enterprise profile — matching bundle id, platform,
        and environment, but carrying ``ProvisionsAllDevices`` and signed with a
        Developer ID certificate — is rejected for a MAS package. The certificate
        subjects are injected so the pure cross-check never shells out."""
        profile = {
            "Entitlements": {
                "com.apple.application-identifier": "ABCDE12345.com.lorvex.apple",
            },
            "Platform": ["OSX"],
            "ProvisionsAllDevices": True,
        }
        failures = profile_cross_check_failures(
            "macOS app",
            profile,
            {},
            "com.lorvex.apple",
            cert_subjects=["subject=CN=Developer ID Application: Example Inc (ABCDE12345)"],
        )
        self.assertEqual(
            failures,
            [
                "macOS app profile is a Developer ID / enterprise profile "
                "(ProvisionsAllDevices is true), not an App Store distribution profile",
                "macOS app profile is signed with a Developer ID certificate "
                "('subject=CN=Developer ID Application: Example Inc (ABCDE12345)'), "
                "not an App Store distribution certificate",
            ],
        )

    def test_accepts_app_store_profile_with_distribution_certificate(self) -> None:
        """The positive MAS profile shape — explicit bundle id, macOS platform,
        no development/enterprise markers, an Apple Distribution certificate —
        still passes once the new distribution-class checks are folded in."""
        profile = {
            "Entitlements": {
                "com.apple.application-identifier": "ABCDE12345.com.lorvex.apple",
                "com.apple.developer.icloud-container-environment": ["Production"],
            },
            "Platform": ["OSX"],
        }
        target_entitlements = {
            "com.apple.developer.icloud-container-environment": "Production",
        }
        failures = profile_cross_check_failures(
            "macOS app",
            profile,
            target_entitlements,
            "com.lorvex.apple",
            cert_subjects=["subject=CN=Apple Distribution: Example Inc (ABCDE12345)"],
        )
        self.assertEqual(failures, [])


class EntitlementsPlanCoverageFailuresTests(unittest.TestCase):
    def test_accepts_executables_with_non_empty_entitlements(self) -> None:
        path = Path("/App.app/Contents/MacOS/App")
        self.assertEqual(
            entitlements_plan_coverage_failures(
                [path], {path: {"com.apple.security.app-sandbox": True}}
            ),
            [],
        )

    def test_rejects_executable_with_empty_entitlements(self) -> None:
        path = Path("/App.app/Contents/MacOS/App")
        self.assertEqual(
            entitlements_plan_coverage_failures([path], {path: {}}),
            [f"executable has no entitlements plan (unsigned or unreadable): {path}"],
        )

    def test_rejects_executable_with_missing_entitlements_entry(self) -> None:
        path = Path("/App.app/Contents/MacOS/App")
        self.assertEqual(
            entitlements_plan_coverage_failures([path], {}),
            [f"executable has no entitlements plan (unsigned or unreadable): {path}"],
        )


class HelperBundleStructureFailuresTests(unittest.TestCase):
    def test_no_check_when_no_mcp_host_product_configured(self) -> None:
        self.assertEqual(
            helper_bundle_structure_failures(Path("/App.app"), ""),
            [],
        )

    def test_rejects_missing_helper_bundle(self, ) -> None:
        failures = helper_bundle_structure_failures(Path("/nonexistent/App.app"), "LorvexMCPHost")
        self.assertEqual(len(failures), 1)
        self.assertIn("MCP helper bundle is missing or not a directory", failures[0])


class EmbeddableTargetsTests(unittest.TestCase):
    def test_includes_app_helper_and_widget_when_configured(self) -> None:
        app_bundle = Path("/dist/Lorvex.app")
        metadata = {
            "BUNDLE_ID": "com.lorvex.apple",
            "MCP_HOST_PRODUCT": "LorvexMCPHost",
            "MCP_HOST_BUNDLE_ID": "com.lorvex.apple.mcp-host",
            "WIDGET_APPEX_NAME": "LorvexFocusWidget.appex",
            "WIDGET_BUNDLE_ID": "com.lorvex.apple.mobile.widget.focus",
        }
        targets = embeddable_targets(app_bundle, metadata)
        self.assertEqual(
            targets,
            [
                ("macOS app", app_bundle, "BUNDLE_ID"),
                (
                    "MCP helper",
                    app_bundle / "Contents" / "Helpers" / "LorvexMCPHost.app",
                    "MCP_HOST_BUNDLE_ID",
                ),
                (
                    "widget extension",
                    app_bundle / "Contents" / "PlugIns" / "LorvexFocusWidget.appex",
                    "WIDGET_BUNDLE_ID",
                ),
            ],
        )

    def test_omits_helper_and_widget_when_unconfigured(self) -> None:
        app_bundle = Path("/dist/Lorvex.app")
        targets = embeddable_targets(app_bundle, {"BUNDLE_ID": "com.lorvex.apple"})
        self.assertEqual(targets, [("macOS app", app_bundle, "BUNDLE_ID")])


if __name__ == "__main__":
    unittest.main()
