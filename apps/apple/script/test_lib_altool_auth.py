#!/usr/bin/env python3
from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

LIB = Path(__file__).resolve().parent / "lib_altool_auth.sh"
AUTH_NAMES = (
    "ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH", "APPLE_ID",
    "APPLE_PASSWORD", "APPLE_APP_PASSWORD",
)
FAKE_PASSWORD = "-".join(("abcd", "efgh", "ijkl", "mnop"))
FAKE_ACCOUNT = "tester" + "@" + "example.com"


class AltoolAuthTests(unittest.TestCase):
    def run_auth(self, values: dict[str, str], *, password: bool = False) -> subprocess.CompletedProcess[str]:
        env = {k: v for k, v in os.environ.items() if k not in AUTH_NAMES}
        env.update(values, AUTH_LIB=str(LIB))
        command = 'source "$AUTH_LIB"; configure_altool_auth || exit $?; '
        command += 'printf "%s\\n" "$APPLE_APP_PASSWORD"' if password else 'printf "%s\\n" "${ALTOOL_AUTH_ARGS[@]}"'
        return subprocess.run(["bash", "-eu", "-c", command], env=env, capture_output=True, text=True)

    def test_api_key_uses_an_explicit_path_without_splitting_spaces(self) -> None:
        with tempfile.TemporaryDirectory(prefix="altool auth ") as directory:
            path = Path(directory) / "AuthKey_TEST.p8"
            path.write_text("test fixture")
            result = self.run_auth({"ASC_KEY_ID": "TEST", "ASC_ISSUER_ID": "issuer", "ASC_KEY_PATH": str(path)})
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.splitlines(), ["--api-key", "TEST", "--api-issuer", "issuer", "--p8-file-path", str(path)])

    def test_api_credentials_take_precedence_over_legacy_credentials(self) -> None:
        result = self.run_auth({"ASC_KEY_ID": "TEST", "ASC_ISSUER_ID": "issuer", "APPLE_ID": FAKE_ACCOUNT, "APPLE_PASSWORD": FAKE_PASSWORD})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ["--api-key", "TEST", "--api-issuer", "issuer"])
        self.assertNotIn(FAKE_PASSWORD, result.stdout + result.stderr)

    def test_partial_api_configuration_never_falls_back_to_another_account(self) -> None:
        for partial in ({"ASC_KEY_ID": "TEST"}, {"ASC_ISSUER_ID": "issuer"}):
            result = self.run_auth({**partial, "APPLE_ID": FAKE_ACCOUNT, "APPLE_PASSWORD": FAKE_PASSWORD})
            self.assertEqual(result.returncode, 2)
            self.assertIn("both ASC_KEY_ID and ASC_ISSUER_ID", result.stderr)
            self.assertNotIn(FAKE_PASSWORD, result.stdout + result.stderr)

    def test_an_explicit_missing_key_file_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            result = self.run_auth({"ASC_KEY_ID": "TEST", "ASC_ISSUER_ID": "issuer", "ASC_KEY_PATH": str(Path(directory) / "missing.p8")})
            self.assertEqual(result.returncode, 2)
            self.assertIn("ASC_KEY_PATH", result.stderr)

    def test_legacy_password_is_referenced_through_the_environment(self) -> None:
        values = {"APPLE_ID": FAKE_ACCOUNT, "APPLE_PASSWORD": FAKE_PASSWORD}
        result = self.run_auth(values)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ["--username", FAKE_ACCOUNT, "--password", "@env:APPLE_APP_PASSWORD"])
        self.assertNotIn(FAKE_PASSWORD, result.stdout + result.stderr)
        self.assertEqual(self.run_auth(values, password=True).stdout.strip(), FAKE_PASSWORD)

    def test_a_preexported_legacy_password_is_supported(self) -> None:
        values = {"APPLE_ID": FAKE_ACCOUNT, "APPLE_APP_PASSWORD": FAKE_PASSWORD}
        result = self.run_auth(values)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.run_auth(values, password=True).stdout.strip(), FAKE_PASSWORD)

    def test_missing_credentials_fail_without_exposing_environment_values(self) -> None:
        result = self.run_auth({})
        self.assertEqual(result.returncode, 2)
        self.assertIn("Configure ASC_KEY_ID/ASC_ISSUER_ID", result.stderr)


if __name__ == "__main__":
    unittest.main()
