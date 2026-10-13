#!/usr/bin/env python3
"""Unit tests for lib_real_data_guard.sh: a Mac that holds real Lorvex data is refused."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

LIB = Path(__file__).resolve().parent / "lib_real_data_guard.sh"


def run_guard(probe_paths: str, allow: str | None = None) -> subprocess.CompletedProcess[str]:
    environment = {key: value for key, value in os.environ.items() if not key.startswith("LORVEX_")}
    environment["LORVEX_REAL_DATA_PROBE_PATHS"] = probe_paths
    if allow is not None:
        environment["LORVEX_ALLOW_RUN_WITH_REAL_DATA"] = allow
    return subprocess.run(
        ["bash", "-c", f'source "{LIB}"; refuse_on_machine_with_lorvex_data verify_all.sh'],
        env=environment,
        capture_output=True,
        text=True,
    )


class RealDataGuardTests(unittest.TestCase):
    def test_a_machine_with_none_of_the_paths_passes(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            result = run_guard(f"{root}/Lorvex.app:{root}/Group Containers/group.example")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")

    def test_an_installed_app_or_a_container_is_refused_and_named(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            installed = Path(root) / "Lorvex.app"
            container = Path(root) / "Group Containers" / "group.example"
            installed.mkdir()
            container.mkdir(parents=True)
            result = run_guard(f"{installed}:{root}/Missing.app:{container}")
        self.assertEqual(result.returncode, 78)
        self.assertIn("verify_all.sh: this Mac holds real Lorvex data", result.stderr)
        self.assertIn(str(installed), result.stderr)
        self.assertIn(str(container), result.stderr)
        self.assertNotIn("Missing.app", result.stderr)
        self.assertIn("verify_static_gates.sh", result.stderr)

    def test_the_override_passes_a_machine_that_holds_data(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            result = run_guard(root, allow="1")
        self.assertEqual(result.returncode, 0)

    def test_the_default_paths_include_the_installed_app_and_the_production_container(self) -> None:
        environment = {key: value for key, value in os.environ.items() if not key.startswith("LORVEX_")}
        environment["HOME"] = "/nonexistent-home"
        result = subprocess.run(
            ["bash", "-c", f'source "{LIB}"; lorvex_real_data_probe_paths'],
            env=environment,
            capture_output=True,
            text=True,
        )
        paths = result.stdout.splitlines()
        self.assertIn("/Applications/Lorvex.app", paths)
        self.assertIn("/nonexistent-home/Applications/Lorvex.app", paths)
        self.assertIn("/nonexistent-home/Library/Group Containers/group.com.lorvex.apple", paths)


if __name__ == "__main__":
    unittest.main()
