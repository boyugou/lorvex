#!/usr/bin/env python3
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from quality_gates import (
    QUALITY_GATE_VERIFIERS,
    quality_gate_failures,
    quality_gate_manifest,
    verifier_path_failures,
)


class QualityGateTests(unittest.TestCase):
    def test_quality_gate_manifest_uses_absolute_paths(self) -> None:
        root = Path("/tmp/example-root")

        manifest = quality_gate_manifest(root)

        self.assertEqual(set(manifest), set(QUALITY_GATE_VERIFIERS))
        for key, relative_path in QUALITY_GATE_VERIFIERS.items():
            self.assertEqual(manifest[key], str(root / relative_path))

    def test_verifier_path_accepts_existing_relative_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script_dir = root / "script"
            script_dir.mkdir()
            verifier = script_dir / "verify_example.py"
            verifier.write_text("#!/usr/bin/env python3\n", encoding="utf-8")
            verifier.chmod(0o755)

            self.assertEqual(
                verifier_path_failures(
                    root,
                    "script/verify_example.py",
                    "script/verify_example.py",
                    "example verifier",
                ),
                [],
            )

    def test_verifier_path_accepts_existing_absolute_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script_dir = root / "script"
            script_dir.mkdir()
            verifier = script_dir / "verify_example.py"
            verifier.write_text("#!/usr/bin/env python3\n", encoding="utf-8")
            verifier.chmod(0o755)

            self.assertEqual(
                verifier_path_failures(
                    root,
                    str(verifier),
                    "script/verify_example.py",
                    "example verifier",
                ),
                [],
            )

    def test_verifier_path_rejects_wrong_manifest_value(self) -> None:
        self.assertEqual(
            verifier_path_failures(
                Path("/tmp"),
                "script/wrong.py",
                "script/verify_example.py",
                "example verifier",
            ),
            ["example verifier path mismatch: 'script/wrong.py'"],
        )

    def test_verifier_path_rejects_missing_expected_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)

            self.assertEqual(
                verifier_path_failures(
                    root,
                    "script/verify_example.py",
                    "script/verify_example.py",
                    "example verifier",
                ),
                [f"example verifier missing: {root / 'script/verify_example.py'}"],
            )

    def test_verifier_path_rejects_non_executable_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script_dir = root / "script"
            script_dir.mkdir()
            verifier = script_dir / "verify_example.py"
            verifier.write_text("#!/usr/bin/env python3\n", encoding="utf-8")
            verifier.chmod(0o644)

            self.assertEqual(
                verifier_path_failures(
                    root,
                    "script/verify_example.py",
                    "script/verify_example.py",
                    "example verifier",
                ),
                [f"example verifier is not executable: {verifier}"],
            )

    def test_quality_gate_failures_rejects_non_object_manifest_value(self) -> None:
        self.assertEqual(
            quality_gate_failures(Path("/tmp"), None),
            ["quality_gates mismatch: None"],
        )

    def test_quality_gate_failures_rejects_missing_gate_key(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script_dir = root / "script"
            script_dir.mkdir()
            verifier = script_dir / "verify_apple_strategy.py"
            verifier.write_text("#!/usr/bin/env python3\n", encoding="utf-8")
            verifier.chmod(0o755)

            self.assertEqual(
                quality_gate_failures(
                    root,
                    {"apple_strategy_verifier": "script/verify_apple_strategy.py"},
                ),
                [
                    "app metadata verifier missing from quality_gates",
                    "build matrix verifier missing from quality_gates",
                    "codesign entitlements verifier missing from quality_gates",
                    "cloudkit sync readiness verifier missing from quality_gates",
                    "core service coverage verifier missing from quality_gates",
                    "hotspot verifier missing from quality_gates",
                    "localization catalog verifier missing from quality_gates",
                    "macho distribution verifier missing from quality_gates",
                    "mcp client config verifier missing from quality_gates",
                    "mcp stdio smoke verifier missing from quality_gates",
                    "mcp tool catalog verifier missing from quality_gates",
                    "mcp tool manifest verifier missing from quality_gates",
                    "release manifest verifier missing from quality_gates",
                    "repo hygiene verifier missing from quality_gates",
                    "system entrypoint verifier missing from quality_gates",
                    "user docs verifier missing from quality_gates",
                ],
            )

    def test_quality_gate_failures_rejects_unexpected_gate_key(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = quality_gate_manifest(root)
            manifest["legacy_theme_verifier"] = str(root / "script/verify_theme.py")
            script_dir = root / "script"
            script_dir.mkdir()
            for relative_path in QUALITY_GATE_VERIFIERS.values():
                verifier = root / relative_path
                verifier.write_text("#!/usr/bin/env python3\n", encoding="utf-8")
                verifier.chmod(0o755)

            self.assertEqual(
                quality_gate_failures(root, manifest),
                ["quality_gates contains unexpected key(s): ['legacy_theme_verifier']"],
            )


if __name__ == "__main__":
    unittest.main()
