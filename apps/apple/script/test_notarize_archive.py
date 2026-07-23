#!/usr/bin/env python3
from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
NOTARIZE_ARCHIVE = ROOT / "script" / "notarize_archive.sh"


class NotarizeArchiveScriptTests(unittest.TestCase):
    def setUp(self) -> None:
        self._temporary_directory = tempfile.TemporaryDirectory()
        self.temporary_directory = Path(self._temporary_directory.name)
        self.app_bundle = self.temporary_directory / "Lorvex.app"
        self.archive_path = self.temporary_directory / "Lorvex.zip"
        self.xcrun_log = self.temporary_directory / "xcrun.log"
        self.fake_bin = self.temporary_directory / "bin"
        self.fake_bin.mkdir()
        self._create_app_bundle()
        self._archive_app_bundle()
        self._create_fake_tools()

    def tearDown(self) -> None:
        self._temporary_directory.cleanup()

    def _create_executable(self, relative_path: str) -> None:
        path = self.app_bundle / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        path.chmod(0o755)

    def _create_app_bundle(self) -> None:
        contents = self.app_bundle / "Contents"
        contents.mkdir(parents=True)
        (contents / "Info.plist").write_text("fixture\n", encoding="utf-8")
        self._create_executable("Contents/MacOS/Lorvex")
        self._create_executable(
            "Contents/Helpers/LorvexMCPHost.app/Contents/MacOS/LorvexMCPHost"
        )
        self._create_executable(
            "Contents/PlugIns/LorvexFocusWidget.appex/Contents/MacOS/LorvexFocusWidget"
        )

    def _archive_app_bundle(self) -> None:
        subprocess.run(
            [
                "ditto",
                "-c",
                "-k",
                "--norsrc",
                "--keepParent",
                str(self.app_bundle),
                str(self.archive_path),
            ],
            check=True,
        )

    def _write_fake_tool(self, name: str, source: str) -> None:
        path = self.fake_bin / name
        path.write_text(source, encoding="utf-8")
        path.chmod(0o755)

    def _create_fake_tools(self) -> None:
        self._write_fake_tool(
            "codesign",
            """#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--verify" ]]; then
  exit 0
fi
if [[ "${1:-}" != "-dvvv" ]]; then
  echo "unexpected codesign arguments: $*" >&2
  exit 97
fi
item="${!#}"
authority="${MOCK_CODESIGN_AUTHORITY:-Developer ID Application: Test (ABCDE12345)}"
team="${MOCK_CODESIGN_TEAM:-ABCDE12345}"
timestamp="${MOCK_CODESIGN_TIMESTAMP-Jul 15, 2026 at 12:00:00}"
adhoc="${MOCK_CODESIGN_ADHOC:-0}"
runtime="${MOCK_CODESIGN_RUNTIME:-1}"
if [[ -n "${MOCK_CODESIGN_OVERRIDE_PATTERN:-}" && "$item" == *"$MOCK_CODESIGN_OVERRIDE_PATTERN"* ]]; then
  authority="${MOCK_CODESIGN_OVERRIDE_AUTHORITY-$authority}"
  team="${MOCK_CODESIGN_OVERRIDE_TEAM-$team}"
  timestamp="${MOCK_CODESIGN_OVERRIDE_TIMESTAMP-$timestamp}"
  adhoc="${MOCK_CODESIGN_OVERRIDE_ADHOC-$adhoc}"
fi
if [[ "$runtime" == "1" ]]; then
  printf 'flags=0x10000(runtime)\n'
else
  printf 'flags=0x0(none)\n'
fi
if [[ "$adhoc" == "1" ]]; then
  printf 'Signature=adhoc\n'
fi
if [[ -n "$authority" ]]; then
  printf 'Authority=%s\n' "$authority"
fi
if [[ -n "$team" ]]; then
  printf 'TeamIdentifier=%s\n' "$team"
fi
if [[ -n "$timestamp" ]]; then
  printf 'Timestamp=%s\n' "$timestamp"
fi
""",
        )
        self._write_fake_tool(
            "xcrun",
            """#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$MOCK_XCRUN_LOG"
if [[ "${1:-}" == "--find" ]]; then
  printf '/mock/%s\n' "${2:-unknown}"
  exit 0
fi
if [[ "${1:-}" == "notarytool" && "${2:-}" == "submit" ]]; then
  exit 0
fi
if [[ "${1:-}" == "stapler" && "${2:-}" == "staple" ]]; then
  touch "$3/Contents/.mock-notarization-ticket"
  exit 0
fi
if [[ "${1:-}" == "stapler" && "${2:-}" == "validate" ]]; then
  exit 0
fi
echo "unexpected xcrun arguments: $*" >&2
exit 98
""",
        )
        self._write_fake_tool(
            "spctl",
            """#!/usr/bin/env bash
set -euo pipefail
exit 0
""",
        )

    def _environment(self, **overrides: str | None) -> dict[str, str]:
        environment = os.environ.copy()
        environment.update(
            {
                "PATH": f"{self.fake_bin}:/usr/bin:/bin:/usr/sbin:/sbin",
                "APP_BUNDLE": str(self.app_bundle),
                "ARCHIVE_PATH": str(self.archive_path),
                "MOCK_XCRUN_LOG": str(self.xcrun_log),
            }
        )
        for key, value in overrides.items():
            if value is None:
                environment.pop(key, None)
            else:
                environment[key] = value
        return environment

    def _run(
        self,
        mode: str = "--preflight",
        **environment_overrides: str | None,
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(NOTARIZE_ARCHIVE), mode],
            env=self._environment(**environment_overrides),
            text=True,
            capture_output=True,
            check=False,
        )

    def test_preflight_validates_archive_offline_and_derives_team(self) -> None:
        result = self._run(APPLE_TEAM_ID=None)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(
            "Notarization preflight passed for Developer ID team ABCDE12345",
            result.stdout,
        )
        calls = self.xcrun_log.read_text(encoding="utf-8").splitlines()
        self.assertEqual(calls, ["--find notarytool", "--find stapler"])

    def test_preflight_rejects_explicit_team_mismatch(self) -> None:
        result = self._run(APPLE_TEAM_ID="ZZZZZ99999")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not match expected team ZZZZZ99999", result.stderr)

    def test_preflight_rejects_ad_hoc_signature(self) -> None:
        result = self._run(MOCK_CODESIGN_ADHOC="1")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("code is ad-hoc signed", result.stderr)

    def test_preflight_rejects_non_developer_id_authority(self) -> None:
        result = self._run(MOCK_CODESIGN_AUTHORITY="Apple Development: Test")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requires a Developer ID Application signature", result.stderr)

    def test_preflight_rejects_app_without_hardened_runtime(self) -> None:
        result = self._run(MOCK_CODESIGN_RUNTIME="0")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not signed with the hardened runtime", result.stderr)

    def test_preflight_rejects_missing_secure_timestamp(self) -> None:
        result = self._run(MOCK_CODESIGN_TIMESTAMP="")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requires a secure timestamp", result.stderr)

    def test_preflight_rejects_explicitly_disabled_timestamp(self) -> None:
        result = self._run(MOCK_CODESIGN_TIMESTAMP="none")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requires a secure timestamp", result.stderr)

    def test_preflight_rejects_nested_code_from_another_team(self) -> None:
        result = self._run(
            MOCK_CODESIGN_OVERRIDE_PATTERN="LorvexMCPHost",
            MOCK_CODESIGN_OVERRIDE_TEAM="ZZZZZ99999",
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not match expected team ABCDE12345", result.stderr)
        self.assertIn("LorvexMCPHost", result.stderr)

    def test_preflight_rejects_archive_that_drifted_from_app_bundle(self) -> None:
        (self.app_bundle / "Contents" / "Info.plist").write_text(
            "changed after archive\n", encoding="utf-8"
        )

        result = self._run()

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("archived app does not match APP_BUNDLE", result.stderr)

    def test_submit_keeps_preflight_before_notary_and_final_validation(self) -> None:
        result = self._run(
            "--submit",
            APPLE_TEAM_ID="ABCDE12345",
            NOTARY_KEYCHAIN_PROFILE="lorvex-notary",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.xcrun_log.read_text(encoding="utf-8").splitlines()
        self.assertEqual(calls[:2], ["--find notarytool", "--find stapler"])
        self.assertEqual(
            calls[2],
            f"notarytool submit {self.archive_path} --keychain-profile lorvex-notary --wait",
        )
        self.assertEqual(calls[3], f"stapler staple {self.app_bundle}")
        self.assertEqual(calls[4], f"stapler validate {self.app_bundle}")
        self.assertTrue(calls[5].startswith("stapler validate "))
        self.assertIn("lorvex-notarize-verify.", calls[5])
        self.assertIn("Distribution archive rebuilt", result.stdout)

    def test_appledouble_archive_check_uses_extended_regex(self) -> None:
        source = NOTARIZE_ARCHIVE.read_text(encoding="utf-8")

        self.assertIn("grep -Eq '(^|/)\\._'", source)
        self.assertNotIn("grep -q '(^|/)\\._'", source)

    def test_signature_checks_use_literal_matching(self) -> None:
        source = NOTARIZE_ARCHIVE.read_text(encoding="utf-8")

        self.assertIn('grep -Fq "Signature=adhoc"', source)
        self.assertIn('grep -Fq "Authority=Developer ID Application:"', source)
        self.assertIn('grep -Fxq "TeamIdentifier=$expected_team_id"', source)
        self.assertNotIn('grep -q "Signature=adhoc"', source)


if __name__ == "__main__":
    unittest.main()
