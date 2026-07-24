#!/usr/bin/env python3
from __future__ import annotations

import io
import plistlib
import tempfile
import unittest
from contextlib import redirect_stdout
from datetime import UTC, datetime
from pathlib import Path

import verify_ios_ipa
from metadata_env import load_metadata
from verify_ios_ipa import (
    COMPLICATION_ROLE,
    FOCUS_FILTER_ROLE,
    HOST_ROLE,
    IPHONE_PLATFORM,
    VISIONOS_PLATFORM,
    WATCHOS_PLATFORM,
    WATCH_ROLE,
    WIDGET_ROLE,
    app_id_authorizes_bundle,
    bundle_id_from_application_identifier,
    bundle_set_failures,
    discover_payload_bundles,
    embedded_profile_failures,
    embedded_profile_path,
    entitlements_failures,
    platform_for_payload,
    privacy_manifest_present,
    read_info_plist,
    signature_failures,
    team_consistency_failures,
    prefix_from_application_identifier,
    verify_payload_app,
    version_metadata_failures,
)


TEAM = "ABCDE12345"


class IpaFixture:
    """A synthetic ``Payload/<App>.app`` tree with injectable per-bundle
    signature results, entitlements, and decoded profiles — the whole
    recursive verification runs against it with no signing credentials, the
    way `test_verify_macho_closure.BundleFixture` drives the closure walker."""

    def __init__(self, root: Path, metadata: dict[str, str]) -> None:
        self.root = root
        self.metadata = metadata
        self.payload_app = root / "Payload" / "LorvexMobileApp.app"
        self.signatures: dict[Path, tuple[bool, str]] = {}
        self.entitlements: dict[Path, dict] = {}
        self.profiles: dict[Path, dict] = {}

    def add_bundle(
        self,
        path: Path,
        bundle_id: str,
        *,
        short: str = "1.0.0",
        build: str = "2",
        privacy: bool = True,
        profile: bool = True,
        profile_app_id: str | None = None,
        profile_team: str = TEAM,
        entitlements_app_id: str | None = None,
        app_groups: list[str] | None = None,
        profile_app_groups: list[str] | None = None,
        team: str = TEAM,
        signature: tuple[bool, str] = (True, ""),
    ) -> Path:
        path.mkdir(parents=True, exist_ok=True)
        with (path / "Info.plist").open("wb") as handle:
            plistlib.dump(
                {
                    "CFBundleIdentifier": bundle_id,
                    "CFBundleExecutable": path.stem,
                    "CFBundleShortVersionString": short,
                    "CFBundleVersion": build,
                },
                handle,
            )
        if privacy:
            (path / "PrivacyInfo.xcprivacy").write_bytes(b"<plist/>")

        resolved = path.resolve()
        self.signatures[resolved] = signature
        entitlements_app_id = entitlements_app_id or f"{team}.{bundle_id}"
        self.entitlements[resolved] = {
            "application-identifier": entitlements_app_id,
            "com.apple.developer.team-identifier": team,
        }
        if app_groups:
            self.entitlements[resolved]["com.apple.security.application-groups"] = app_groups
        if profile:
            profile_path = path / "embedded.mobileprovision"
            profile_path.write_bytes(b"cms-blob")
            profile_entitlements: dict[str, object] = {
                "application-identifier": profile_app_id or f"{team}.{bundle_id}"
            }
            resolved_profile_groups = (
                app_groups if profile_app_groups is None else profile_app_groups
            )
            if resolved_profile_groups:
                profile_entitlements[
                    "com.apple.security.application-groups"
                ] = resolved_profile_groups
            self.profiles[profile_path.resolve()] = {
                "Entitlements": profile_entitlements,
                "ApplicationIdentifierPrefix": [
                    (profile_app_id or f"{team}.{bundle_id}").partition(".")[0]
                ],
                "TeamIdentifier": [profile_team],
                "ExpirationDate": datetime(2036, 1, 1, tzinfo=UTC),
            }
        return path

    def add_focus_filter(self) -> Path:
        return self.add_bundle(
            self.payload_app / "PlugIns" / self.metadata["FOCUS_FILTER_APPEX_NAME"],
            self.metadata["FOCUS_FILTER_BUNDLE_ID"],
            app_groups=["group.com.lorvex.apple"],
        )

    def build_full(self) -> None:
        """A well-formed iPhone release payload: host app + widget + Watch app +
        complication, every bundle id / version drawn from release metadata."""
        m = self.metadata
        self.add_bundle(self.payload_app, m["MOBILE_BUNDLE_ID"])
        self.add_bundle(
            self.payload_app / "PlugIns" / "LorvexFocusWidget.appex",
            m["WIDGET_BUNDLE_ID"],
        )
        self.add_focus_filter()
        watch_app = self.payload_app / "Watch" / "LorvexWatchApp.app"
        self.add_bundle(watch_app, m["WATCH_BUNDLE_ID"])
        self.add_bundle(
            watch_app / "PlugIns" / "LorvexWatchComplication.appex",
            m["WATCH_COMPLICATION_BUNDLE_ID"],
        )

    def build_vision(self) -> None:
        """A well-formed visionOS release payload: the host app alone (visionOS
        embeds no widget or Watch payload)."""
        self.payload_app = self.root / "Payload" / "LorvexVisionApp.app"
        self.add_bundle(self.payload_app, self.metadata["VISION_BUNDLE_ID"])

    def build_watch_standalone(self) -> None:
        """A well-formed standalone (development-export) watchOS payload: the
        Watch app host and its complication under ``PlugIns/``."""
        self.payload_app = self.root / "Payload" / "LorvexWatchApp.app"
        self.add_bundle(self.payload_app, self.metadata["WATCH_BUNDLE_ID"])
        self.add_bundle(
            self.payload_app / "PlugIns" / "LorvexWatchComplication.appex",
            self.metadata["WATCH_COMPLICATION_BUNDLE_ID"],
        )

    # Injected adapters -----------------------------------------------------
    def verify_signature(self, bundle: Path) -> tuple[bool, str]:
        return self.signatures.get(bundle.resolve(), (True, ""))

    def read_entitlements(self, bundle: Path) -> dict:
        return self.entitlements.get(bundle.resolve(), {})

    def decode_profile(self, profile_path: Path) -> dict:
        return self.profiles[profile_path.resolve()]

    def run(
        self,
        *,
        expected_team: str | None = None,
        platform=IPHONE_PLATFORM,
        require_app_store_profile: bool = False,
    ) -> list[str]:
        return verify_payload_app(
            self.payload_app,
            self.metadata,
            verify_signature=self.verify_signature,
            read_entitlements=self.read_entitlements,
            decode_profile=self.decode_profile,
            expected_team=expected_team,
            platform=platform,
            require_app_store_profile=require_app_store_profile,
        )


class PureHelperTests(unittest.TestCase):
    def test_prefix_and_bundle_id_from_application_identifier(self) -> None:
        self.assertEqual(prefix_from_application_identifier("ABCDE12345.com.lorvex.apple"), "ABCDE12345")
        self.assertEqual(
            bundle_id_from_application_identifier("ABCDE12345.com.lorvex.apple.mobile"),
            "com.lorvex.apple.mobile",
        )

    def test_app_id_authorizes_bundle_exact_and_wildcard(self) -> None:
        self.assertTrue(app_id_authorizes_bundle("com.lorvex.apple.mobile", "com.lorvex.apple.mobile"))
        self.assertTrue(app_id_authorizes_bundle("com.lorvex.*", "com.lorvex.apple.mobile"))
        self.assertTrue(app_id_authorizes_bundle("*", "com.lorvex.apple.mobile"))
        self.assertFalse(app_id_authorizes_bundle("com.other.*", "com.lorvex.apple.mobile"))
        self.assertFalse(app_id_authorizes_bundle("com.lorvex.apple", "com.lorvex.apple.mobile"))

    def test_signature_failures(self) -> None:
        self.assertEqual(signature_failures("host app", True, ""), [])
        failures = signature_failures("host app", False, "not signed")
        self.assertEqual(len(failures), 1)
        self.assertIn("code signature is invalid", failures[0])

    def test_entitlements_failures(self) -> None:
        self.assertEqual(len(entitlements_failures("host app", {}, "com.lorvex.apple.mobile")), 1)
        ok = {"application-identifier": "ABCDE12345.com.lorvex.apple.mobile"}
        self.assertEqual(entitlements_failures("host app", ok, "com.lorvex.apple.mobile"), [])
        wrong = {"application-identifier": "ABCDE12345.com.other"}
        failures = entitlements_failures("host app", wrong, "com.lorvex.apple.mobile")
        self.assertEqual(len(failures), 1)
        self.assertIn("does not authorize bundle id", failures[0])

    def test_embedded_profile_failures(self) -> None:
        self.assertEqual(
            len(embedded_profile_failures("widget", False, None, "com.lorvex.apple.mobile.widget.focus")),
            1,
        )
        good = {
            "Entitlements": {
                "application-identifier": "ABCDE12345.com.lorvex.apple.mobile"
            },
            "ApplicationIdentifierPrefix": ["ABCDE12345"],
        }
        self.assertEqual(embedded_profile_failures("host app", True, good, "com.lorvex.apple.mobile"), [])
        mismatch = {
            "Entitlements": {"application-identifier": "ABCDE12345.com.other"},
            "ApplicationIdentifierPrefix": ["ABCDE12345"],
        }
        failures = embedded_profile_failures("host app", True, mismatch, "com.lorvex.apple.mobile")
        self.assertEqual(len(failures), 1)
        self.assertIn("does not authorize bundle id", failures[0])

    def test_version_metadata_failures(self) -> None:
        info = {"CFBundleShortVersionString": "1.0.0", "CFBundleVersion": "1"}
        self.assertEqual(version_metadata_failures("host app", info, "1.0.0", "1"), [])
        drift = {"CFBundleShortVersionString": "1.0.1", "CFBundleVersion": "2"}
        self.assertEqual(len(version_metadata_failures("host app", drift, "1.0.0", "1")), 2)

    def test_team_consistency_failures(self) -> None:
        self.assertEqual(team_consistency_failures({"host app": TEAM, "widget": TEAM}), [])
        failures = team_consistency_failures({"host app": TEAM, "widget": "ZZZZZ99999"})
        self.assertEqual(len(failures), 1)
        self.assertIn("disagree on team identifier", failures[0])

    def test_bundle_set_failures(self) -> None:
        expected = {"a", "b"}
        self.assertEqual(bundle_set_failures({"a", "b"}, expected), [])
        missing = bundle_set_failures({"a"}, expected)
        self.assertEqual(len(missing), 1)
        self.assertIn("missing ['b']", missing[0])
        extra = bundle_set_failures({"a", "b", "c"}, expected)
        self.assertIn("unexpected ['c']", extra[0])


class DiscoveryAndShapeTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.metadata = load_metadata()
        self.fixture = IpaFixture(Path(self._tmp.name), self.metadata)
        self.fixture.build_full()

    def test_discovers_all_five_bundles_in_nesting_order(self) -> None:
        bundles = discover_payload_bundles(
            self.fixture.payload_app,
            root_plugin_roles_by_bundle_id={
                self.metadata["FOCUS_FILTER_BUNDLE_ID"]: FOCUS_FILTER_ROLE,
                self.metadata["WIDGET_BUNDLE_ID"]: WIDGET_ROLE,
            },
        )
        self.assertEqual(
            [(b.role, b.path.name) for b in bundles],
            [
                (HOST_ROLE, "LorvexMobileApp.app"),
                (FOCUS_FILTER_ROLE, "LorvexFocusFilterExtension.appex"),
                (WIDGET_ROLE, "LorvexFocusWidget.appex"),
                (WATCH_ROLE, "LorvexWatchApp.app"),
                (COMPLICATION_ROLE, "LorvexWatchComplication.appex"),
            ],
        )

    def test_read_info_plist_and_shape_helpers(self) -> None:
        info = read_info_plist(self.fixture.payload_app)
        self.assertIsNotNone(info)
        self.assertEqual(info["CFBundleIdentifier"], self.metadata["MOBILE_BUNDLE_ID"])
        self.assertIsNotNone(embedded_profile_path(self.fixture.payload_app))
        self.assertTrue(privacy_manifest_present(self.fixture.payload_app))


class VerifyPayloadAppTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.metadata = load_metadata()
        self.fixture = IpaFixture(Path(self._tmp.name), self.metadata)

    def test_wellformed_payload_passes(self) -> None:
        self.fixture.build_full()
        self.assertEqual(self.fixture.run(), [])

    def test_wellformed_payload_matches_expected_team(self) -> None:
        self.fixture.build_full()
        self.assertEqual(self.fixture.run(expected_team=TEAM), [])

    def test_legacy_app_id_prefix_distinct_from_team_id_is_accepted(self) -> None:
        self.fixture.build_full()
        legacy_prefix = "LEGACY6789"
        for bundle_path, entitlements in self.fixture.entitlements.items():
            bundle_id = entitlements["application-identifier"].partition(".")[2]
            entitlements["application-identifier"] = f"{legacy_prefix}.{bundle_id}"
        for profile in self.fixture.profiles.values():
            app_id = profile["Entitlements"]["application-identifier"]
            bundle_id = app_id.partition(".")[2]
            profile["Entitlements"][
                "application-identifier"
            ] = f"{legacy_prefix}.{bundle_id}"
            profile["ApplicationIdentifierPrefix"] = [legacy_prefix]

        self.assertEqual(
            self.fixture.run(
                expected_team=TEAM,
                require_app_store_profile=True,
            ),
            [],
        )

    def test_missing_privacy_manifest_is_flagged(self) -> None:
        m = self.metadata
        self.fixture.add_bundle(self.fixture.payload_app, m["MOBILE_BUNDLE_ID"])
        self.fixture.add_bundle(
            self.fixture.payload_app / "PlugIns" / "LorvexFocusWidget.appex",
            m["WIDGET_BUNDLE_ID"],
            privacy=False,
        )
        self.fixture.add_focus_filter()
        watch_app = self.fixture.payload_app / "Watch" / "LorvexWatchApp.app"
        self.fixture.add_bundle(watch_app, m["WATCH_BUNDLE_ID"])
        self.fixture.add_bundle(
            watch_app / "PlugIns" / "LorvexWatchComplication.appex",
            m["WATCH_COMPLICATION_BUNDLE_ID"],
        )
        failures = self.fixture.run()
        self.assertEqual(len(failures), 1)
        self.assertIn("PrivacyInfo.xcprivacy", failures[0])

    def test_invalid_signature_is_flagged(self) -> None:
        self.fixture.build_full()
        watch_app = self.fixture.payload_app / "Watch" / "LorvexWatchApp.app"
        self.fixture.signatures[watch_app.resolve()] = (False, "code object is not signed at all")
        failures = self.fixture.run()
        self.assertEqual(len(failures), 1)
        self.assertIn("code signature is invalid", failures[0])
        self.assertIn("Watch app", failures[0])

    def test_missing_embedded_profile_is_flagged(self) -> None:
        m = self.metadata
        self.fixture.add_bundle(self.fixture.payload_app, m["MOBILE_BUNDLE_ID"])
        self.fixture.add_bundle(
            self.fixture.payload_app / "PlugIns" / "LorvexFocusWidget.appex",
            m["WIDGET_BUNDLE_ID"],
        )
        self.fixture.add_focus_filter()
        watch_app = self.fixture.payload_app / "Watch" / "LorvexWatchApp.app"
        self.fixture.add_bundle(watch_app, m["WATCH_BUNDLE_ID"])
        self.fixture.add_bundle(
            watch_app / "PlugIns" / "LorvexWatchComplication.appex",
            m["WATCH_COMPLICATION_BUNDLE_ID"],
            profile=False,
        )
        failures = self.fixture.run()
        self.assertEqual(len(failures), 1)
        self.assertIn("no embedded embedded.mobileprovision", failures[0])
        self.assertIn("Watch complication", failures[0])

    def test_empty_entitlements_is_flagged(self) -> None:
        self.fixture.build_full()
        self.fixture.entitlements[self.fixture.payload_app.resolve()] = {}
        failures = self.fixture.run()
        self.assertEqual(len(failures), 1)
        self.assertIn("signed entitlements are empty", failures[0])
        self.assertIn("host app", failures[0])

    def test_version_drift_is_flagged(self) -> None:
        m = self.metadata
        self.fixture.add_bundle(self.fixture.payload_app, m["MOBILE_BUNDLE_ID"], build="99")
        self.fixture.add_bundle(
            self.fixture.payload_app / "PlugIns" / "LorvexFocusWidget.appex",
            m["WIDGET_BUNDLE_ID"],
        )
        self.fixture.add_focus_filter()
        watch_app = self.fixture.payload_app / "Watch" / "LorvexWatchApp.app"
        self.fixture.add_bundle(watch_app, m["WATCH_BUNDLE_ID"])
        self.fixture.add_bundle(
            watch_app / "PlugIns" / "LorvexWatchComplication.appex",
            m["WATCH_COMPLICATION_BUNDLE_ID"],
        )
        failures = self.fixture.run()
        self.assertEqual(len(failures), 1)
        self.assertIn("CFBundleVersion", failures[0])

    def test_profile_bundle_mismatch_is_flagged(self) -> None:
        m = self.metadata
        self.fixture.add_bundle(self.fixture.payload_app, m["MOBILE_BUNDLE_ID"])
        self.fixture.add_bundle(
            self.fixture.payload_app / "PlugIns" / "LorvexFocusWidget.appex",
            m["WIDGET_BUNDLE_ID"],
            profile_app_id=f"{TEAM}.com.lorvex.apple.widget.WRONG",
        )
        self.fixture.add_focus_filter()
        watch_app = self.fixture.payload_app / "Watch" / "LorvexWatchApp.app"
        self.fixture.add_bundle(watch_app, m["WATCH_BUNDLE_ID"])
        self.fixture.add_bundle(
            watch_app / "PlugIns" / "LorvexWatchComplication.appex",
            m["WATCH_COMPLICATION_BUNDLE_ID"],
        )
        failures = self.fixture.run()
        self.assertEqual(len(failures), 1)
        self.assertIn("embedded profile provisions", failures[0])
        self.assertIn("widget extension", failures[0])

    def test_team_disagreement_is_flagged(self) -> None:
        m = self.metadata
        self.fixture.add_bundle(self.fixture.payload_app, m["MOBILE_BUNDLE_ID"])
        self.fixture.add_bundle(
            self.fixture.payload_app / "PlugIns" / "LorvexFocusWidget.appex",
            m["WIDGET_BUNDLE_ID"],
        )
        self.fixture.add_focus_filter()
        watch_app = self.fixture.payload_app / "Watch" / "LorvexWatchApp.app"
        self.fixture.add_bundle(watch_app, m["WATCH_BUNDLE_ID"])
        # A complication signed under a different team than the rest.
        self.fixture.add_bundle(
            watch_app / "PlugIns" / "LorvexWatchComplication.appex",
            m["WATCH_COMPLICATION_BUNDLE_ID"],
            team="ZZZZZ99999",
            profile_team="ZZZZZ99999",
        )
        failures = self.fixture.run()
        self.assertEqual(len(failures), 1)
        self.assertIn("disagree on team identifier", failures[0])

    def test_missing_bundle_from_release_set_is_flagged(self) -> None:
        m = self.metadata
        # Drop the complication entirely: it is never discovered, so no
        # per-bundle failure fires — the release-set check must catch it.
        self.fixture.add_bundle(self.fixture.payload_app, m["MOBILE_BUNDLE_ID"])
        self.fixture.add_bundle(
            self.fixture.payload_app / "PlugIns" / "LorvexFocusWidget.appex",
            m["WIDGET_BUNDLE_ID"],
        )
        self.fixture.add_focus_filter()
        self.fixture.add_bundle(
            self.fixture.payload_app / "Watch" / "LorvexWatchApp.app",
            m["WATCH_BUNDLE_ID"],
        )
        failures = self.fixture.run()
        self.assertEqual(len(failures), 1)
        self.assertIn("bundle set does not match release metadata", failures[0])
        self.assertIn("missing", failures[0])

    def test_expected_team_mismatch_is_flagged(self) -> None:
        self.fixture.build_full()
        failures = self.fixture.run(expected_team="OTHER00000")
        self.assertEqual(len(failures), 5)
        for failure in failures:
            self.assertIn("does not match expected APPLE_TEAM_ID", failure)

    def test_focus_filter_requires_its_own_profile_app_group_authorization(self) -> None:
        self.fixture.build_full()
        focus_filter = (
            self.fixture.payload_app
            / "PlugIns"
            / self.metadata["FOCUS_FILTER_APPEX_NAME"]
        )
        profile_path = (focus_filter / "embedded.mobileprovision").resolve()
        self.fixture.profiles[profile_path]["Entitlements"].pop(
            "com.apple.security.application-groups"
        )

        failures = self.fixture.run()

        self.assertEqual(len(failures), 1)
        self.assertIn("Focus filter extension", failures[0])
        self.assertIn("profile is missing App Group", failures[0])

    def test_app_store_focus_filter_profile_must_be_exact_not_reused_wildcard(self) -> None:
        self.fixture.build_full()
        focus_filter = (
            self.fixture.payload_app
            / "PlugIns"
            / self.metadata["FOCUS_FILTER_APPEX_NAME"]
        )
        profile_path = (focus_filter / "embedded.mobileprovision").resolve()
        self.fixture.profiles[profile_path]["Entitlements"][
            "application-identifier"
        ] = f"{TEAM}.com.lorvex.apple.*"

        self.assertEqual(self.fixture.run(), [])
        failures = self.fixture.run(require_app_store_profile=True)

        self.assertEqual(len(failures), 2)
        self.assertIn("Focus filter extension", failures[0])
        self.assertTrue(
            any("must explicitly provision bundle id" in failure for failure in failures)
        )
        self.assertTrue(
            any("does not exactly match profile" in failure for failure in failures)
        )


class PlatformDetectionTests(unittest.TestCase):
    def test_override_wins_over_info_plist(self) -> None:
        self.assertIs(
            platform_for_payload({"DTPlatformName": "iphoneos"}, "visionos"),
            VISIONOS_PLATFORM,
        )

    def test_dt_platform_name_selects_platform(self) -> None:
        self.assertIs(platform_for_payload({"DTPlatformName": "iphoneos"}), IPHONE_PLATFORM)
        self.assertIs(platform_for_payload({"DTPlatformName": "xros"}), VISIONOS_PLATFORM)
        self.assertIs(platform_for_payload({"DTPlatformName": "watchos"}), WATCHOS_PLATFORM)

    def test_absent_or_unknown_platform_falls_back_to_iphone(self) -> None:
        self.assertIs(platform_for_payload({}), IPHONE_PLATFORM)
        self.assertIs(platform_for_payload(None), IPHONE_PLATFORM)
        self.assertIs(platform_for_payload({"DTPlatformName": "tvos"}), IPHONE_PLATFORM)

    def test_unknown_override_raises(self) -> None:
        with self.assertRaises(ValueError):
            platform_for_payload({}, "androidtv")


class PlatformBundleShapeTests(unittest.TestCase):
    """The expected bundle set is the target platform's own shape (#11): a
    visionOS export (host app alone) passes under the visionOS expectation and
    is rejected by the iPhone one, and vice-versa, so a produced artifact is
    never rejected by a verifier that assumed a different platform."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.metadata = load_metadata()
        self.fixture = IpaFixture(Path(self._tmp.name), self.metadata)

    def test_visionos_payload_passes_under_visionos_platform(self) -> None:
        self.fixture.build_vision()
        self.assertEqual(self.fixture.run(platform=VISIONOS_PLATFORM), [])
        self.assertEqual(self.fixture.run(platform=VISIONOS_PLATFORM, expected_team=TEAM), [])

    def test_visionos_payload_rejected_by_iphone_platform(self) -> None:
        self.fixture.build_vision()
        failures = self.fixture.run(platform=IPHONE_PLATFORM)
        self.assertTrue(
            any("bundle set does not match release metadata" in f for f in failures)
        )

    def test_iphone_payload_rejected_by_visionos_platform(self) -> None:
        self.fixture.build_full()
        failures = self.fixture.run(platform=VISIONOS_PLATFORM)
        self.assertTrue(
            any("bundle set does not match release metadata" in f for f in failures)
        )

    def test_iphone_payload_passes_under_iphone_platform(self) -> None:
        self.fixture.build_full()
        self.assertEqual(self.fixture.run(platform=IPHONE_PLATFORM), [])

    def test_watchos_standalone_payload_passes_under_watchos_platform(self) -> None:
        # Exercises the root-PlugIns role mapping: on a standalone watch export
        # the appex directly under the payload app is the complication.
        self.fixture.build_watch_standalone()
        self.assertEqual(self.fixture.run(platform=WATCHOS_PLATFORM), [])
        bundles = discover_payload_bundles(
            self.fixture.payload_app, WATCHOS_PLATFORM.root_plugin_role
        )
        self.assertEqual(
            [(b.role, b.path.name) for b in bundles],
            [
                (HOST_ROLE, "LorvexWatchApp.app"),
                (COMPLICATION_ROLE, "LorvexWatchComplication.appex"),
            ],
        )


class MainSkipTests(unittest.TestCase):
    def test_absent_artifact_skips_cleanly(self) -> None:
        buffer = io.StringIO()
        with redirect_stdout(buffer):
            status = verify_ios_ipa.main(["/nonexistent/Lorvex.ipa"])
        self.assertEqual(status, 0)
        self.assertIn("skipping iOS IPA recursive verification", buffer.getvalue())


if __name__ == "__main__":
    unittest.main()
