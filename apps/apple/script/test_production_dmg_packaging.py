#!/usr/bin/env python3
from __future__ import annotations

import ast
import json
import os
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
from datetime import UTC, datetime
from pathlib import Path

from generate_production_dmg_evidence import REQUIRED_EVIDENCE_FILES, sha256_file
from notary_submit_with_evidence import run_notary_submission
from prepare_profile_entitlements import merged_entitlements
from reset_production_app_group import (
    clear_defaults_domain,
    defaults_domain_is_absent,
    reset_installed_app_group,
)
from verify_production_app_runtime import (
    bundle_tree_digest,
    classify_procinfo_result,
    clean_widget_snapshot_failure,
    matching_plugin_path,
    mcp_smoke_row_counts,
    production_launch_command,
)
from verify_developer_id_provisioning import (
    bundle_metadata_failures,
    developer_id_signature_failures,
    profile_contract_failures,
)


ROOT = Path(__file__).resolve().parents[1]
PACKAGE_DMG = ROOT / "script" / "package_dmg.sh"
SIGN_APP_BUNDLE = ROOT / "script" / "sign_app_bundle.sh"
EVIDENCE_GENERATOR = ROOT / "script" / "generate_production_dmg_evidence.py"
RUNTIME_PROBE = ROOT / "script" / "verify_production_app_runtime.py"
RESET_APP_GROUP = ROOT / "script" / "reset_production_app_group.py"
MCP_STDIO_SMOKE = ROOT / "script" / "mcp_stdio_smoke.py"
TEAM_ID = "ABCDE12345"
BUNDLE_ID = "com.lorvex.apple"


def developer_id_profile() -> dict:
    return {
        "Entitlements": {
            "com.apple.application-identifier": f"{TEAM_ID}.{BUNDLE_ID}",
            "com.apple.developer.team-identifier": TEAM_ID,
            "com.apple.developer.aps-environment": "production",
            "com.apple.developer.icloud-container-environment": ["Production"],
            "com.apple.developer.icloud-container-identifiers": [
                "iCloud.com.lorvex.apple"
            ],
            "com.apple.developer.icloud-services": ["CloudKit"],
            "com.apple.security.application-groups": ["group.com.lorvex.apple"],
        },
        "Platform": ["OSX"],
        "ProvisionsAllDevices": True,
        "ApplicationIdentifierPrefix": [TEAM_ID],
        "TeamIdentifier": [TEAM_ID],
        "ExpirationDate": datetime(2036, 1, 1, tzinfo=UTC),
    }


def signed_entitlements() -> dict:
    return {
        "com.apple.application-identifier": f"{TEAM_ID}.{BUNDLE_ID}",
        "com.apple.developer.team-identifier": TEAM_ID,
        "com.apple.developer.aps-environment": "production",
        "com.apple.developer.icloud-container-environment": "Production",
        "com.apple.developer.icloud-container-identifiers": [
            "iCloud.com.lorvex.apple"
        ],
        "com.apple.developer.icloud-services": ["CloudKit"],
        "com.apple.security.application-groups": ["group.com.lorvex.apple"],
        "com.apple.security.app-sandbox": True,
    }


class ProfileAwareEntitlementTests(unittest.TestCase):
    def test_merges_profile_identifiers_into_checked_in_entitlements(self) -> None:
        base = {
            "com.apple.security.app-sandbox": True,
            "com.apple.security.application-groups": ["group.com.lorvex.apple"],
        }

        result = merged_entitlements(base, developer_id_profile(), BUNDLE_ID, TEAM_ID)

        self.assertEqual(
            result["com.apple.application-identifier"], f"{TEAM_ID}.{BUNDLE_ID}"
        )
        self.assertEqual(result["com.apple.developer.team-identifier"], TEAM_ID)
        self.assertEqual(result["com.apple.security.app-sandbox"], True)
        self.assertNotIn("com.apple.application-identifier", base)

    def test_rejects_device_limited_profile(self) -> None:
        profile = developer_id_profile()
        profile["ProvisionsAllDevices"] = False
        profile["ProvisionedDevices"] = ["fixture"]

        with self.assertRaisesRegex(ValueError, "not a Developer ID"):
            merged_entitlements({}, profile, BUNDLE_ID, TEAM_ID)

    def test_accepts_legacy_app_id_prefix_distinct_from_team_id(self) -> None:
        profile = developer_id_profile()
        profile["Entitlements"][
            "com.apple.application-identifier"
        ] = f"LEGACY6789.{BUNDLE_ID}"
        profile["ApplicationIdentifierPrefix"] = ["LEGACY6789"]

        result = merged_entitlements({}, profile, BUNDLE_ID, TEAM_ID)

        self.assertEqual(
            result["com.apple.application-identifier"],
            f"LEGACY6789.{BUNDLE_ID}",
        )
        self.assertEqual(result["com.apple.developer.team-identifier"], TEAM_ID)


class DeveloperIDVerifierDecisionTests(unittest.TestCase):
    def test_bundle_metadata_is_part_of_the_final_profile_gate(self) -> None:
        self.assertEqual(
            bundle_metadata_failures(
                "macOS app",
                {
                    "CFBundleIdentifier": BUNDLE_ID,
                    "CFBundleShortVersionString": "1.0.0",
                    "CFBundleVersion": "1",
                },
                BUNDLE_ID,
                "1.0.0",
                "1",
            ),
            [],
        )
        failures = bundle_metadata_failures(
            "macOS app",
            {
                "CFBundleIdentifier": "com.example.wrong",
                "CFBundleShortVersionString": "1.0.0",
                "CFBundleVersion": "2",
            },
            BUNDLE_ID,
            "1.0.0",
            "1",
        )
        self.assertEqual(len(failures), 2)

    def test_accepts_matching_profile_signature_contract(self) -> None:
        failures = profile_contract_failures(
            "macOS app",
            developer_id_profile(),
            signed_entitlements(),
            BUNDLE_ID,
            TEAM_ID,
            cert_subjects=[
                "subject=UID=ABCDE12345, CN=Developer ID Application: Example (ABCDE12345)"
            ],
        )

        self.assertEqual(failures, [])

    def test_rejects_profile_without_developer_id_certificate(self) -> None:
        failures = profile_contract_failures(
            "macOS app",
            developer_id_profile(),
            signed_entitlements(),
            BUNDLE_ID,
            TEAM_ID,
            cert_subjects=[
                "subject=UID=ABCDE12345, CN=Apple Distribution: Example (ABCDE12345)"
            ],
        )

        self.assertTrue(any("not Developer ID Application" in item for item in failures))

    def test_rejects_missing_signed_application_identifier(self) -> None:
        signed = signed_entitlements()
        del signed["com.apple.application-identifier"]

        failures = profile_contract_failures(
            "macOS app",
            developer_id_profile(),
            signed,
            BUNDLE_ID,
            TEAM_ID,
            cert_subjects=["CN=Developer ID Application: Example (ABCDE12345)"],
        )

        self.assertTrue(any("signed application identifier" in item for item in failures))

    def test_signature_contract_requires_authority_team_runtime_and_timestamp(self) -> None:
        valid = "\n".join(
            [
                "flags=0x10000(runtime)",
                "Authority=Developer ID Application: Example (ABCDE12345)",
                f"TeamIdentifier={TEAM_ID}",
                "Timestamp=Jul 21, 2026 at 12:00:00",
            ]
        )
        self.assertEqual(developer_id_signature_failures("app", valid, TEAM_ID), [])

        invalid = "flags=0x0(none)\nTeamIdentifier=not set\nTimestamp=none\n"
        failures = developer_id_signature_failures("app", invalid, TEAM_ID)
        self.assertEqual(len(failures), 4)


class NotaryEvidenceTests(unittest.TestCase):
    def test_accepted_submission_fetches_and_writes_notary_log(self) -> None:
        calls: list[list[str]] = []

        def runner(command: list[str], **_: object) -> subprocess.CompletedProcess[str]:
            calls.append(command)
            if command[2] == "submit":
                return subprocess.CompletedProcess(
                    command,
                    0,
                    stdout=json.dumps({"id": "submission-1", "status": "Accepted"}),
                    stderr="",
                )
            return subprocess.CompletedProcess(
                command,
                0,
                stdout=json.dumps(
                    {"id": "submission-1", "status": "Accepted", "issues": None}
                ),
                stderr="",
            )

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            artifact = root / "Lorvex.dmg"
            artifact.write_bytes(b"fixture")
            prefix = root / "evidence" / "dmg-notary"

            run_notary_submission(
                artifact, "LorvexNotary", prefix, runner=runner
            )

            self.assertEqual(calls[0][2], "submit")
            self.assertEqual(calls[1][2], "log")
            self.assertEqual(
                json.loads((prefix.parent / "dmg-notary-submit.json").read_text())["status"],
                "Accepted",
            )
            self.assertTrue((prefix.parent / "dmg-notary-log.json").is_file())

    def test_nonaccepted_submission_still_fetches_and_retains_log(self) -> None:
        calls: list[list[str]] = []

        def runner(command: list[str], **_: object) -> subprocess.CompletedProcess[str]:
            calls.append(command)
            if command[2] == "log":
                return subprocess.CompletedProcess(
                    command,
                    0,
                    stdout=json.dumps(
                        {
                            "id": "submission-1",
                            "status": "Invalid",
                            "issues": [
                                {
                                    "severity": "error",
                                    "message": "fixture rejection",
                                }
                            ],
                        }
                    ),
                    stderr="",
                )
            return subprocess.CompletedProcess(
                command,
                0,
                stdout=json.dumps({"id": "submission-1", "status": "Invalid"}),
                stderr="",
            )

        with tempfile.TemporaryDirectory() as directory:
            artifact = Path(directory) / "Lorvex.dmg"
            artifact.write_bytes(b"fixture")
            prefix = Path(directory) / "evidence" / "dmg-notary"
            with self.assertRaisesRegex(RuntimeError, "not accepted"):
                run_notary_submission(
                    artifact,
                    "LorvexNotary",
                    prefix,
                    runner=runner,
                )
            self.assertEqual(
                json.loads(
                    (prefix.parent / "dmg-notary-submit.json").read_text()
                )["status"],
                "Invalid",
            )
            self.assertEqual(
                json.loads(
                    (prefix.parent / "dmg-notary-log.json").read_text()
                )["status"],
                "Invalid",
            )
        self.assertEqual(len(calls), 2)

    def test_nonzero_invalid_submission_with_id_still_retains_log(self) -> None:
        calls: list[list[str]] = []

        def runner(command: list[str], **_: object) -> subprocess.CompletedProcess[str]:
            calls.append(command)
            if command[2] == "submit":
                return subprocess.CompletedProcess(
                    command,
                    1,
                    stdout=json.dumps({"id": "submission-2", "status": "Invalid"}),
                    stderr="submission rejected",
                )
            return subprocess.CompletedProcess(
                command,
                0,
                stdout=json.dumps(
                    {
                        "id": "submission-2",
                        "status": "Invalid",
                        "issues": [{"severity": "error", "message": "fixture"}],
                    }
                ),
                stderr="",
            )

        with tempfile.TemporaryDirectory() as directory:
            artifact = Path(directory) / "Lorvex.dmg"
            artifact.write_bytes(b"fixture")
            prefix = Path(directory) / "evidence" / "dmg-notary"
            with self.assertRaisesRegex(RuntimeError, "not accepted"):
                run_notary_submission(
                    artifact,
                    "LorvexNotary",
                    prefix,
                    runner=runner,
                )
            self.assertTrue((prefix.parent / "dmg-notary-submit.json").is_file())
            self.assertTrue((prefix.parent / "dmg-notary-log.json").is_file())
        self.assertEqual(len(calls), 2)


class ProductionDMGScriptContractTests(unittest.TestCase):
    def test_script_is_fail_closed_production_orchestration(self) -> None:
        source = PACKAGE_DMG.read_text(encoding="utf-8")

        for required in (
            "APPLE_TEAM_ID",
            "CODE_SIGN_IDENTITY",
            "NOTARY_KEYCHAIN_PROFILE",
            "DEVELOPER_ID_APP_PROVISIONING_PROFILE",
            "DEVELOPER_ID_MCP_HOST_PROVISIONING_PROFILE",
            "DEVELOPER_ID_WIDGET_PROVISIONING_PROFILE",
            "LORVEX_ALLOW_DESTRUCTIVE_APP_GROUP_RESET",
            "LORVEX_PRODUCTION_INSTALL_PATH",
            '/Applications/$APP_NAME.app',
            "require_schema_freeze_armed",
            "status --porcelain --untracked-files=all",
            "LORVEX_BUILD_CONFIGURATION=release",
            "CODE_SIGN_IDENTITY=- ./script/build_and_run.sh --stage-only",
            "SIGN_TIMESTAMP=secure",
            "LorvexAppleCloudKitAppStore.entitlements",
            "verify_developer_id_provisioning.py",
            "verify_final_dmg_signature",
            "--require-production-aps",
            "--reset-real-app-group",
            "reset_production_app_group.py",
            "hdiutil verify",
            "hdiutil attach",
            "-readonly",
            '-mountpoint "$MOUNT_POINT"',
            'ditto "$MOUNTED_APP" "$INSTALLED_APP"',
            "verify_production_app_runtime.py",
            "reject_ambiguous_dmg_artifacts",
            "reject_existing_release_outputs",
            "advance BUILD_VERSION",
            "spctl -a -t open --context context:primary-signature",
            'ARTIFACT_STEM="$DMG_NAME-macOS-$MARKETING_VERSION+$BUILD_VERSION-arm64"',
            "PACKAGE_STARTED=1",
            "PACKAGE_SUCCEEDED=1",
            "final-app-group-reset.json",
            "--clean-reset-evidence",
        ):
            self.assertIn(required, source)
        self.assertEqual(source.count("notary_submit_with_evidence.py"), 2)
        self.assertIn('xcrun stapler staple "$STAGED_APP"', source)
        self.assertIn('xcrun stapler staple "$DMG_OUT"', source)
        self.assertNotIn("SIGN_TIMESTAMP=none", source)
        self.assertNotIn("Apple Development:", source)
        self.assertIn("Authority=Developer ID Application:", source)
        self.assertIn("TeamIdentifier=$APPLE_TEAM_ID", source)
        self.assertIn("final DMG signature has no secure timestamp", source)
        install_index = source.index('ditto "$MOUNTED_APP" "$INSTALLED_APP"')
        initial_reset_index = source.index("reset_production_app_group.py")
        initial_runtime_index = source.index(
            "verify_production_app_runtime.py", initial_reset_index
        )
        smoke_index = source.index('mcp_stdio_smoke.py" --reset-real-app-group')
        final_reset_index = source.rindex("reset_production_app_group.py")
        final_runtime_index = source.rindex("verify_production_app_runtime.py")
        self.assertLess(install_index, initial_reset_index)
        self.assertLess(
            initial_reset_index,
            initial_runtime_index,
            "the old App Group must be permanently erased before the first cold launch",
        )
        self.assertLess(
            initial_runtime_index,
            smoke_index,
            "the exact installed main app must cold-launch before the helper smoke",
        )
        self.assertLess(smoke_index, final_reset_index)
        self.assertLess(
            final_reset_index,
            final_runtime_index,
            "final runtime evidence must come from the post-smoke clean state",
        )
        self.assertNotIn('rm -rf "$EVIDENCE_DIR"', source)
        self.assertEqual(
            source.count('rm -f "$DMG_OUT" "$DMG_OUT.sha256"'),
            1,
            "only failed outputs created by the current run may be cleaned up",
        )
        self.assertNotIn("-ov \\", source)
        self.assertNotIn("lorvex-production-install.XXXXXX", source)
        self.assertIn(
            'find "$DIST" -maxdepth 1 -name "$DMG_NAME-macOS-*.dmg" -print0',
            source,
        )
        self.assertNotIn(
            '-type f -name "$DMG_NAME-macOS-*.dmg"',
            source,
            "stale-DMG refusal must include symlinks and other ambiguous nodes",
        )

    def test_no_credentials_help_path_is_nonmutating(self) -> None:
        result = subprocess.run(
            [str(PACKAGE_DMG), "--help"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Developer ID Application", result.stdout)

    def test_no_arg_path_fails_before_build_without_production_credentials(self) -> None:
        with tempfile.TemporaryDirectory() as home:
            result = subprocess.run(
                [str(PACKAGE_DMG)],
                capture_output=True,
                text=True,
                check=False,
                env={"HOME": home, "PATH": os.environ.get("PATH", "")},
            )
        self.assertEqual(result.returncode, 2)
        self.assertIn("missing required production environment variable", result.stderr)
        self.assertNotIn("Building Release bundle", result.stdout + result.stderr)

    def test_mac_signing_refuses_to_reuse_widget_profile_for_unknown_appex(self) -> None:
        source = SIGN_APP_BUNDLE.read_text(encoding="utf-8")
        self.assertIn('WIDGET_BUNDLE="$APP_PLUGINS/$WIDGET_APPEX_NAME"', source)
        self.assertIn(
            "unexpected macOS app extension requires explicit signing configuration",
            source,
        )
        self.assertNotIn(
            'codesign_with_timeout "${widget_sign_args[@]}" "$item"',
            source,
        )

    def test_evidence_generator_writes_final_sha_and_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            dmg = root / "Lorvex-macOS-1.0.0+1-arm64.dmg"
            dmg.write_bytes(b"final-dmg-fixture")
            app = root / "Lorvex.app"
            app.mkdir()
            evidence = root / "evidence"
            evidence.mkdir()
            for name in REQUIRED_EVIDENCE_FILES:
                content = "fixture\n"
                if name in {
                    "app-notary-log.json",
                    "app-notary-submit.json",
                    "dmg-notary-log.json",
                    "dmg-notary-submit.json",
                }:
                    content = '{"status":"Accepted"}\n'
                elif name == "installed-app-content-identity.json":
                    content = json.dumps(
                        {
                            "algorithm": "sha256-tree-v1",
                            "installedApp": str(app),
                            "installedDigest": "digest",
                            "mountedApp": "/Volumes/Lorvex/Lorvex.app",
                            "mountedDigest": "digest",
                        }
                    )
                elif name == "installed-app-runtime.json":
                    content = json.dumps(
                        {
                            "app": str(app),
                            "coldLaunchStableSeconds": 3,
                            "entitlementsValidated": False,
                            "executable": str(app / "Contents" / "MacOS" / "Lorvex"),
                            "launchCommand": [
                                "/usr/bin/open",
                                "-F",
                                "-n",
                                str(app),
                            ],
                            "pid": 123,
                            "pluginIdentifier": "com.lorvex.apple.focuswidget",
                            "pluginPath": str(
                                app
                                / "Contents"
                                / "PlugIns"
                                / "LorvexFocusWidget.appex"
                            ),
                            "procinfoSupported": False,
                            "verifiedAt": "2026-07-21T12:01:00Z",
                        }
                    )
                elif name == "installed-app-clean-derived-state.json":
                    snapshot_path = (
                        Path.home()
                        / "Library"
                        / "Group Containers"
                        / "group.com.lorvex.apple"
                        / "Lorvex"
                        / "widget_snapshot_v3.json"
                    )
                    content = json.dumps(
                        {
                            "databaseSmokeRowCounts": {
                                "habits": 0,
                                "lists": 0,
                                "tasks": 0,
                            },
                            "finalResetEvidence": str(
                                evidence / "final-app-group-reset.json"
                            ),
                            "minimumStorageGeneration": 6,
                            "snapshotGeneratedAt": "2026-07-21T12:00:20Z",
                            "snapshotPath": str(snapshot_path),
                            "snapshotStorageGeneration": 6,
                            "smokeRowsPresent": False,
                            "verifiedAt": "2026-07-21T12:00:30Z",
                        }
                    )
                elif name in {
                    "installed-app-group-reset.json",
                    "final-app-group-reset.json",
                }:
                    final_reset = name == "final-app-group-reset.json"
                    content = json.dumps(
                        {
                            "appGroupIdentifier": "group.com.lorvex.apple",
                            "backupCreated": False,
                            "databaseAbsentAfterReset": True,
                            "databasePath": str(
                                Path.home()
                                / "Library"
                                / "Group Containers"
                                / "group.com.lorvex.apple"
                                / "Lorvex"
                                / "db.sqlite"
                            ),
                            "destructive": True,
                            "defaultsDomainsCleared": [
                                "com.lorvex.apple",
                                "group.com.lorvex.apple",
                            ],
                            "generation": 6 if final_reset else 3,
                            "helperBinary": str(
                                app
                                / "Contents"
                                / "Helpers"
                                / "LorvexMCPHost.app"
                                / "Contents"
                                / "MacOS"
                                / "LorvexMCPHost"
                            ),
                            "priorDataRestored": False,
                            "privateStatePathCleared": str(
                                Path.home()
                                / "Library"
                                / "Containers"
                                / "com.lorvex.apple"
                                / "Data"
                                / "Library"
                                / "Application Support"
                                / "LorvexApple"
                            ),
                            "resetAt": (
                                "2026-07-21T12:00:00Z"
                                if final_reset
                                else "2026-07-21T11:00:00Z"
                            ),
                        }
                    )
                elif name == "mcp-production-app-group-smoke.txt":
                    content = "\n".join(
                        (
                            "PASS: smoke database starts with no tasks",
                            "MCP stdio smoke passed (swift core)",
                            "PASS: removed MCP smoke data from the real Lorvex App Group "
                            "(generation 5); prior data was not restored",
                            "",
                        )
                    )
                (evidence / name).write_text(content, encoding="utf-8")

            result = subprocess.run(
                [
                    sys.executable,
                    str(EVIDENCE_GENERATOR),
                    "--dmg",
                    str(dmg),
                    "--app",
                    str(app),
                    "--evidence-dir",
                    str(evidence),
                    "--team-id",
                    TEAM_ID,
                ],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            checksum = dmg.with_name(f"{dmg.name}.sha256").read_text()
            self.assertEqual(checksum, f"{sha256_file(dmg)}  {dmg.name}\n")
            manifest = json.loads((evidence / "release-evidence.json").read_text())
            self.assertEqual(manifest["channel"], "developer-id-notarized-dmg")
            self.assertEqual(manifest["artifact"]["sha256"], sha256_file(dmg))
            self.assertEqual(manifest["build"], "1")
            self.assertEqual(manifest["app"]["installedPath"], str(app))
            self.assertEqual(manifest["app"]["contentTreeSha256"], "digest")
            self.assertEqual(manifest["app"]["coldLaunchStableSeconds"], 3)
            self.assertEqual(
                manifest["app"]["destructiveAppGroupResetGeneration"], 6
            )
            self.assertEqual(manifest["app"]["derivedStateSnapshotGeneration"], 6)

            repeated = subprocess.run(
                [
                    sys.executable,
                    str(EVIDENCE_GENERATOR),
                    "--dmg",
                    str(dmg),
                    "--app",
                    str(app),
                    "--evidence-dir",
                    str(evidence),
                    "--team-id",
                    TEAM_ID,
                ],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertNotEqual(repeated.returncode, 0)
            self.assertIn("File exists", repeated.stderr)


class ProductionInstalledAppRuntimeDecisionTests(unittest.TestCase):
    def test_production_launch_is_fresh_and_cannot_restore_prior_window_state(
        self,
    ) -> None:
        installed = Path("/Applications/Lorvex.app")

        self.assertEqual(
            production_launch_command(installed),
            ["/usr/bin/open", "-F", "-n", str(installed)],
        )

    def test_bundle_tree_digest_ties_installed_bytes_and_symlinks_to_mounted_source(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            mounted = root / "mounted" / "Lorvex.app"
            installed = root / "Applications" / "Lorvex.app"
            for bundle in (mounted, installed):
                executable = bundle / "Contents" / "MacOS" / "Lorvex"
                executable.parent.mkdir(parents=True)
                executable.write_bytes(b"release-binary")
                (bundle / "Contents" / "Resources").mkdir()
                (bundle / "Contents" / "Resources" / "current").symlink_to(
                    "../MacOS/Lorvex"
                )

            self.assertEqual(bundle_tree_digest(mounted), bundle_tree_digest(installed))
            (installed / "Contents" / "MacOS" / "Lorvex").write_bytes(b"changed")
            self.assertNotEqual(bundle_tree_digest(mounted), bundle_tree_digest(installed))

    def test_clean_widget_snapshot_rejects_smoke_or_pre_reset_rows(self) -> None:
        reset_at = datetime(2026, 7, 21, 12, 0, tzinfo=UTC)
        clean = {
            "generated_at": "2026-07-21T12:00:01Z",
            "storage_generation": 6,
            "focus_tasks": [],
            "habits": [],
            "today_tasks": [],
            "lists": [{"id": "inbox", "name": "Inbox"}],
        }
        self.assertIsNone(clean_widget_snapshot_failure(clean, 6, reset_at))

        stale = dict(clean, storage_generation=5)
        self.assertIn(
            "does not match",
            clean_widget_snapshot_failure(stale, 6, reset_at) or "",
        )
        smoke = dict(clean, today_tasks=[{"title": "Smoke-test Swift MCP host"}])
        self.assertIn(
            "today_tasks",
            clean_widget_snapshot_failure(smoke, 6, reset_at) or "",
        )

    def test_final_database_probe_detects_each_mcp_smoke_row(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            database = Path(directory) / "db.sqlite"
            connection = sqlite3.connect(database)
            try:
                connection.executescript(
                    """
                    CREATE TABLE tasks (title TEXT NOT NULL);
                    CREATE TABLE habits (name TEXT NOT NULL);
                    CREATE TABLE lists (name TEXT NOT NULL);
                    """
                )
                connection.commit()
            finally:
                connection.close()
            self.assertEqual(
                mcp_smoke_row_counts(database),
                {"tasks": 0, "habits": 0, "lists": 0},
            )

            connection = sqlite3.connect(database)
            try:
                connection.execute(
                    "INSERT INTO tasks(title) VALUES (?)",
                    ("Smoke-test Swift MCP host",),
                )
                connection.execute(
                    "INSERT INTO habits(name) VALUES (?)", ("Smoke-test habit",)
                )
                connection.execute(
                    "INSERT INTO lists(name) VALUES (?)", ("Smoke-test list",)
                )
                connection.commit()
            finally:
                connection.close()
            self.assertEqual(
                mcp_smoke_row_counts(database),
                {"tasks": 1, "habits": 1, "lists": 1},
            )

    def test_plugin_registration_requires_the_exact_installed_appex_path(self) -> None:
        installed_widget = Path(
            "/Applications/Lorvex.app/Contents/PlugIns/LorvexFocusWidget.appex"
        )
        output = (
            "     com.example.other(1.0)\tUUID\t/date\t/Elsewhere/Other.appex\n"
            "+    com.lorvex.apple.focuswidget(1.0)\tUUID\t/date\t"
            f"{installed_widget}\n"
        )
        self.assertEqual(
            matching_plugin_path(
                output, "com.lorvex.apple.focuswidget", installed_widget
            ),
            installed_widget,
        )
        self.assertIsNone(
            matching_plugin_path(
                output,
                "com.lorvex.apple.focuswidget",
                Path("/tmp/Lorvex.app/Contents/PlugIns/LorvexFocusWidget.appex"),
            )
        )

    def test_procinfo_is_required_when_supported_and_explicit_when_unavailable(
        self,
    ) -> None:
        self.assertEqual(
            classify_procinfo_result(0, "entitlements validated\n", ""),
            (True, True),
        )
        self.assertEqual(
            classify_procinfo_result(
                1, "", "This subcommand requires root privileges: procinfo"
            ),
            (False, False),
        )
        with self.assertRaisesRegex(RuntimeError, "did not validate entitlements"):
            classify_procinfo_result(0, "service state only", "")
        with self.assertRaisesRegex(RuntimeError, "procinfo failed"):
            classify_procinfo_result(1, "", "unexpected launchctl failure")

    def test_release_evidence_requires_real_install_and_runtime_proof(self) -> None:
        self.assertTrue(RUNTIME_PROBE.is_file())
        self.assertTrue(
            {
                "installed-app-content-identity.json",
                "installed-app-clean-derived-state.json",
                "installed-app-launchservices.txt",
                "installed-app-runtime.json",
                "installed-app-runtime-procinfo.txt",
                "installed-widget-pluginkit.txt",
                "installed-app-codesign.txt",
                "installed-app-signed-entitlements.plist",
                "installed-app-provisioning-profile.plist",
                "installed-app-process-paths.txt",
                "installed-app-group-reset.json",
                "final-app-group-reset.json",
            }.issubset(REQUIRED_EVIDENCE_FILES)
        )


class ProductionAppGroupResetDecisionTests(unittest.TestCase):
    def test_reset_harness_never_moves_copies_or_restores_prior_data(self) -> None:
        for source_path in (RESET_APP_GROUP, MCP_STDIO_SMOKE):
            tree = ast.parse(source_path.read_text(encoding="utf-8"))
            forbidden_shutil_calls: list[str] = []
            for node in ast.walk(tree):
                if not isinstance(node, ast.Call) or not isinstance(
                    node.func, ast.Attribute
                ):
                    continue
                if (
                    isinstance(node.func.value, ast.Name)
                    and node.func.value.id == "shutil"
                    and node.func.attr in {"move", "copy", "copy2", "copytree"}
                ):
                    forbidden_shutil_calls.append(node.func.attr)
            self.assertEqual(
                forbidden_shutil_calls,
                [],
                f"{source_path.name} must never preserve prior production data",
            )

        package_source = PACKAGE_DMG.read_text(encoding="utf-8")
        install_region = package_source[
            package_source.index('echo "==> Installing exact final-DMG app') :
            package_source.index('echo "==> Permanently clearing production local state')
        ]
        self.assertIn('rm -rf "$INSTALLED_APP"', install_region)
        self.assertIn('ditto "$MOUNTED_APP" "$INSTALLED_APP"', install_region)
        self.assertNotRegex(install_region, r"\b(?:mv|cp|rsync)\b")
        self.assertNotIn("BACKUP", install_region.upper())
        self.assertNotIn("RESTORE", install_region.upper())

    def test_defaults_absence_accepts_real_macos_delete_and_read_wording(self) -> None:
        self.assertTrue(defaults_domain_is_absent("Domain (fixture) not found."))
        self.assertTrue(defaults_domain_is_absent("Domain fixture does not exist"))
        self.assertFalse(defaults_domain_is_absent("Permission denied"))

    def test_defaults_reset_uses_delete_all_for_sandbox_containers(self) -> None:
        calls: list[list[str]] = []

        def runner(command: list[str], **_: object) -> subprocess.CompletedProcess[str]:
            calls.append(command)
            return subprocess.CompletedProcess(
                command,
                0 if command[1] == "delete-all" else 1,
                stdout="",
                stderr=(
                    "" if command[1] == "delete-all"
                    else "Domain com.lorvex.apple does not exist"
                ),
            )

        with mock.patch(
            "reset_production_app_group.subprocess.run", side_effect=runner
        ):
            clear_defaults_domain("com.lorvex.apple")

        self.assertEqual(
            calls,
            [
                ["/usr/bin/defaults", "delete-all", "com.lorvex.apple"],
                ["/usr/bin/defaults", "read", "com.lorvex.apple"],
            ],
        )

    def test_reset_cli_refuses_missing_destructive_acknowledgement(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            evidence = Path(directory) / "reset.json"
            environment = dict(os.environ)
            environment.pop("LORVEX_ALLOW_DESTRUCTIVE_APP_GROUP_RESET", None)
            result = subprocess.run(
                [
                    str(RESET_APP_GROUP),
                    "--helper-binary",
                    str(Path(directory) / "missing-helper"),
                    "--evidence",
                    str(evidence),
                ],
                capture_output=True,
                text=True,
                check=False,
                env=environment,
            )

            self.assertEqual(result.returncode, 2)
            self.assertIn("explicit destructive acknowledgement", result.stderr)
            self.assertFalse(evidence.exists())

    def test_reset_stops_processes_and_proves_quiescence_before_erasing(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            helper = root / "LorvexMCPHost"
            helper.write_bytes(b"fixture")
            evidence = root / "evidence" / "reset.json"
            calls: list[str] = []

            def stop(_: tuple[str, ...]) -> None:
                calls.append("stop")

            def quiescent(_: Path) -> None:
                calls.append("quiescent")

            def clear_defaults(domain: str) -> None:
                calls.append(f"defaults:{domain}")

            def reset(_: Path) -> int:
                calls.append("reset")
                return 4

            with (
                mock.patch(
                    "reset_production_app_group.signed_entitlements",
                    return_value={"com.apple.security.app-sandbox": True},
                ),
                mock.patch(
                    "reset_production_app_group.verify_sandboxed_release_binary"
                ),
                mock.patch(
                    "reset_production_app_group.stop_lorvex_processes",
                    side_effect=stop,
                ),
                mock.patch(
                    "reset_production_app_group.require_quiescent_app_group",
                    side_effect=quiescent,
                ),
                mock.patch(
                    "reset_production_app_group.clear_defaults_domain",
                    side_effect=clear_defaults,
                ),
                mock.patch(
                    "reset_production_app_group.reset_real_app_group_state",
                    side_effect=reset,
                ),
            ):
                generation = reset_installed_app_group(
                    helper,
                    "group.com.lorvex.apple",
                    "com.lorvex.apple",
                    "LorvexApple",
                    ("Lorvex", "LorvexMCPHost"),
                    home=root,
                    evidence_path=evidence,
                )

            self.assertEqual(generation, 4)
            self.assertEqual(
                calls,
                [
                    "stop",
                    "quiescent",
                    "defaults:com.lorvex.apple",
                    "defaults:group.com.lorvex.apple",
                    "reset",
                ],
            )
            payload = json.loads(evidence.read_text(encoding="utf-8"))
            self.assertEqual(payload["generation"], 4)
            self.assertFalse(payload["backupCreated"])
            self.assertFalse(payload["priorDataRestored"])
            self.assertTrue(payload["databaseAbsentAfterReset"])
            self.assertEqual(
                payload["defaultsDomainsCleared"],
                ["com.lorvex.apple", "group.com.lorvex.apple"],
            )
            self.assertEqual(
                payload["databasePath"],
                str(
                    root
                    / "Library"
                    / "Group Containers"
                    / "group.com.lorvex.apple"
                    / "Lorvex"
                    / "db.sqlite"
                ),
            )

    def test_reset_rejects_invalid_app_group_before_any_process_action(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            helper = Path(directory) / "LorvexMCPHost"
            helper.write_bytes(b"fixture")
            with mock.patch(
                "reset_production_app_group.stop_lorvex_processes"
            ) as stop:
                with self.assertRaisesRegex(ValueError, "invalid App Group"):
                    reset_installed_app_group(
                        helper,
                        "../dangerous",
                        "com.lorvex.apple",
                        "LorvexApple",
                        ("Lorvex",),
                        home=Path(directory),
                    )
            stop.assert_not_called()


if __name__ == "__main__":
    unittest.main()
