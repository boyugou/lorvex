#!/usr/bin/env python3
from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
DEPLOY_SCHEMA = REPO_ROOT / "cloudkit" / "deploy-schema.sh"
SCHEMA_FILE = REPO_ROOT / "cloudkit" / "schema.ckdb"


class CloudKitDeploySchemaScriptTests(unittest.TestCase):
    def setUp(self) -> None:
        self._temporary_directory = tempfile.TemporaryDirectory()
        self.temporary_directory = Path(self._temporary_directory.name)
        self.fake_bin = self.temporary_directory / "bin"
        self.fake_bin.mkdir()
        self.xcrun_log = self.temporary_directory / "xcrun.log"
        fake_xcrun = self.fake_bin / "xcrun"
        fake_xcrun.write_text(
            """#!/usr/bin/env bash
set -euo pipefail
{
  printf '%s' "${1:-}"
  shift || true
  printf '\\t%s' "$@"
  printf '\\n'
} >> "$MOCK_XCRUN_LOG"
""",
            encoding="utf-8",
        )
        fake_xcrun.chmod(0o755)

    def tearDown(self) -> None:
        self._temporary_directory.cleanup()

    def _environment(self, **overrides: str) -> dict[str, str]:
        environment = os.environ.copy()
        environment.update(
            {
                "PATH": f"{self.fake_bin}:{environment['PATH']}",
                "LORVEX_CLOUDKIT_TEAM_ID": "TESTTEAM123",
                "LORVEX_CLOUDKIT_CONTAINER_ID": "iCloud.test.lorvex",
                "LORVEX_CLOUDKIT_ENVIRONMENT": "development",
                "MOCK_XCRUN_LOG": str(self.xcrun_log),
            }
        )
        environment.update(overrides)
        return environment

    def _run(
        self,
        *arguments: str,
        **environment_overrides: str,
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["/bin/bash", str(DEPLOY_SCHEMA), *arguments],
            env=self._environment(**environment_overrides),
            text=True,
            capture_output=True,
            check=False,
        )

    def _calls(self) -> list[list[str]]:
        if not self.xcrun_log.exists():
            return []
        return [
            line.split("\t")
            for line in self.xcrun_log.read_text(encoding="utf-8").splitlines()
        ]

    def _schema_arguments(self, command: str) -> list[str]:
        return [
            "cktool",
            command,
            "--team-id",
            "TESTTEAM123",
            "--container-id",
            "iCloud.test.lorvex",
            "--environment",
            "development",
            "--file",
            str(SCHEMA_FILE),
        ]

    def test_no_arguments_validates_then_imports_development_schema(self) -> None:
        result = self._run()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self._calls(),
            [
                self._schema_arguments("validate-schema"),
                self._schema_arguments("import-schema"),
            ],
        )

    def test_reset_uses_development_only_reset_contract_then_imports(self) -> None:
        result = self._run("--reset")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self._calls(),
            [
                [
                    "cktool",
                    "reset-schema",
                    "--team-id",
                    "TESTTEAM123",
                    "--container-id",
                    "iCloud.test.lorvex",
                ],
                self._schema_arguments("validate-schema"),
                self._schema_arguments("import-schema"),
            ],
        )

    def test_help_exits_without_contacting_cloudkit(self) -> None:
        result = self._run("--help")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Usage:", result.stdout)
        self.assertEqual(self._calls(), [])

    def test_unknown_argument_fails_before_contacting_cloudkit(self) -> None:
        result = self._run("--production")

        self.assertEqual(result.returncode, 2)
        self.assertIn("unknown argument '--production'", result.stderr)
        self.assertEqual(self._calls(), [])

    def test_extra_argument_fails_before_contacting_cloudkit(self) -> None:
        result = self._run("--reset", "unexpected")

        self.assertEqual(result.returncode, 2)
        self.assertIn("expected no arguments, --reset, or --help", result.stderr)
        self.assertEqual(self._calls(), [])

    def test_non_development_environment_fails_before_contacting_cloudkit(self) -> None:
        result = self._run(LORVEX_CLOUDKIT_ENVIRONMENT="production")

        self.assertEqual(result.returncode, 1)
        self.assertIn("only supports the development environment", result.stderr)
        self.assertEqual(self._calls(), [])


if __name__ == "__main__":
    unittest.main()
