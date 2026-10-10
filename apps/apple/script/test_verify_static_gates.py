#!/usr/bin/env python3
from __future__ import annotations

import os
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
VERIFY_ALL = SCRIPT_DIR / "verify_all.sh"
STATIC_RUNNER = SCRIPT_DIR / "verify_static_gates.sh"
BEGIN = "# --- static tier: begin ---"
END = "# --- static tier: end ---"

# Commands that build, test, launch, or package the app. None may run inside the static tier,
# which promises to be safe on a machine that holds real Lorvex data.
HEAVY_COMMANDS = (
    "swift build",
    "swift test",
    "xcodebuild",
    "build_and_run",
    "package_local",
    "archive_",
    "notarize",
    "mcp_stdio_smoke",
)

# The localization-arguments gate runs an incremental macOS build, so the tier may name its file
# (the py_compile list does) but must never run it.
LOCALIZATION_ARGUMENTS_RUN = "./script/verify_localization_arguments.py"

# Gates whose silent absence from the tier let a gate drift red unnoticed.
REQUIRED_IN_TIER = (
    "python3 -m unittest discover -s script -p 'test_*.py'",
    "./script/verify_schema_embed.sh",
    "./script/verify_backup_v1_contract.py",
    "./script/verify_cloudkit_sync_readiness.py",
    "./script/verify_sync_payload_contract.py",
    "./script/verify_schema_freeze.py",
)


def static_tier_commands() -> list[str]:
    """The non-comment lines of verify_all.sh between the tier markers."""
    lines = VERIFY_ALL.read_text(encoding="utf-8").splitlines()
    begin, end = lines.index(BEGIN), lines.index(END)
    return [line for line in lines[begin + 1 : end] if line.strip() and not line.startswith("#")]


class StaticTierTests(unittest.TestCase):
    def test_markers_bound_exactly_one_region(self) -> None:
        lines = VERIFY_ALL.read_text(encoding="utf-8").splitlines()

        self.assertEqual(lines.count(BEGIN), 1)
        self.assertEqual(lines.count(END), 1)
        self.assertLess(lines.index(BEGIN), lines.index(END))

    def test_tier_runs_the_gates_that_have_drifted_before(self) -> None:
        tier = "\n".join(static_tier_commands())

        for required in REQUIRED_IN_TIER:
            self.assertIn(required, tier)

    def test_tier_starts_no_build_launch_or_packaging(self) -> None:
        tier = "\n".join(static_tier_commands())

        for heavy in HEAVY_COMMANDS:
            self.assertNotIn(heavy, tier)

    def test_tier_never_runs_the_localization_arguments_gate(self) -> None:
        commands = [line.strip().rstrip("\\").strip() for line in static_tier_commands()]

        self.assertNotIn(LOCALIZATION_ARGUMENTS_RUN, commands)

    def test_standalone_runner_is_executable_and_reads_the_same_markers(self) -> None:
        source = STATIC_RUNNER.read_text(encoding="utf-8")

        self.assertTrue(os.access(STATIC_RUNNER, os.X_OK))
        self.assertIn(BEGIN, source)
        self.assertIn(END, source)
        self.assertIn("script/verify_all.sh", source)


if __name__ == "__main__":
    unittest.main()
