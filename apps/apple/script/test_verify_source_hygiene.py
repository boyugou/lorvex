#!/usr/bin/env python3
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import verify_source_hygiene as vsh


class SourceHygieneVerifierTests(unittest.TestCase):
    def test_real_tree_passes(self) -> None:
        # The gate is green on the committed tree: every extracted source-shape
        # invariant holds against the real Apple sources.
        self.assertEqual(vsh.source_hygiene_failures(), [])

    def test_contains_violation_flagged(self) -> None:
        failures = vsh.source_hygiene_failures(
            [("contains", ("file", "Package.swift"), "NO_SUCH_FRAGMENT_ZZZ")]
        )
        self.assertEqual(len(failures), 1)
        self.assertIn("missing required fragment", failures[0])

    def test_absent_violation_flagged(self) -> None:
        # Package.swift certainly contains "swift".
        failures = vsh.source_hygiene_failures(
            [("absent", ("file", "Package.swift"), "swift")]
        )
        self.assertEqual(len(failures), 1)
        self.assertIn("forbidden fragment present", failures[0])

    def test_file_missing_violation_flagged(self) -> None:
        failures = vsh.source_hygiene_failures([("file_missing", "Package.swift")])
        self.assertEqual(len(failures), 1)
        self.assertIn("must not exist", failures[0])

    def test_count_and_order_violations_flagged(self) -> None:
        self.assertTrue(
            vsh.source_hygiene_failures([("count_ge", ("file", "Package.swift"), "swift", 10**6)])
        )
        self.assertTrue(
            vsh.source_hygiene_failures([("count_eq", ("file", "Package.swift"), "swift", 0)])
        )
        self.assertTrue(
            vsh.source_hygiene_failures([("order", ("file", "Package.swift"), "ZZZ_B", "ZZZ_A")])
        )

    def test_missing_required_file_flagged(self) -> None:
        failures = vsh.source_hygiene_failures(
            [("contains", ("file", "Sources/NoSuchFile.swift"), "x")]
        )
        self.assertEqual(len(failures), 1)
        self.assertIn("required source file missing", failures[0])

    def test_token_scan_flags_planted_token_and_tolerates_missing_roots(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            root = repo / "apps/apple/Sources"
            root.mkdir(parents=True)
            (root / "Clean.swift").write_text("let ok = 1\n", encoding="utf-8")
            (root / "Bad.swift").write_text(
                'let v = "' + vsh.FORBIDDEN_TOKEN + '"\n', encoding="utf-8"
            )
            original = vsh.REPO
            try:
                vsh.REPO = repo
                failures = vsh.token_scan_failures()
            finally:
                vsh.REPO = original
        # The other scan roots (schema, apps/tauri/*, core) are absent in this
        # temp repo: they are skipped, not failures. Only the planted token flags.
        self.assertEqual(len(failures), 1)
        self.assertIn("Bad.swift", failures[0])


if __name__ == "__main__":
    unittest.main()
