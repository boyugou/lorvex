#!/usr/bin/env python3
from __future__ import annotations

import contextlib
import hashlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import verify_backup_v1_contract as gate

FROZEN_SOURCE = "enum Frozen {}\n"
DIGESTS = {
    "expectedSHA256": "a" * 64,
    "expectedProductionJSONSHA256": "b" * 64,
    "expectedProductionZipSHA256": "c" * 64,
}
FIXTURE_SOURCE = (
    f'  static let expectedSHA256 = "{DIGESTS["expectedSHA256"]}"\n'
    f'  static let expectedProductionJSONSHA256 =\n    "{DIGESTS["expectedProductionJSONSHA256"]}"\n'
    f'  static let expectedProductionZipSHA256 =\n    "{DIGESTS["expectedProductionZipSHA256"]}"\n'
)


class SeedPolicyTests(unittest.TestCase):
    """``--seed`` against a throwaway tree: the launch sentinel decides who may re-seal."""

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        (self.root / "script").mkdir()
        (self.root / "Sources").mkdir()
        (self.root / "Sources" / "Frozen.swift").write_text(FROZEN_SOURCE, encoding="utf-8")
        self.fixture = self.root / "Fixture.swift"
        self.fixture.write_text(FIXTURE_SOURCE, encoding="utf-8")
        self.lock = self.root / "script" / "backup_v1_contract.lock"

    def _patched(self, *, launched: bool):
        return mock.patch.multiple(
            gate,
            APPLE_ROOT=self.root,
            LOCK_PATH=self.lock,
            FIXTURE_PATH=self.fixture,
            REQUIRED_FROZEN_FILES={"Sources/Frozen.swift"},
            is_launched=lambda: launched,
            verify=lambda: 0,
        )

    def test_launched_seed_refuses_without_additive(self) -> None:
        stderr = io.StringIO()
        with self._patched(launched=True), contextlib.redirect_stderr(stderr):
            result = gate.seed()

        self.assertEqual(result, 1)
        self.assertFalse(self.lock.exists())
        self.assertIn("--seed --additive", stderr.getvalue())

    def test_launched_additive_seed_regenerates_the_lock(self) -> None:
        stdout = io.StringIO()
        with self._patched(launched=True), contextlib.redirect_stdout(stdout):
            result = gate.seed(additive=True)

        self.assertEqual(result, 0)
        self.assertIn("3 golden digests adopted", stdout.getvalue())
        lock = json.loads(self.lock.read_text(encoding="utf-8"))
        self.assertEqual(lock["format_version"], "1")
        self.assertEqual(
            lock["files"],
            {"Sources/Frozen.swift": hashlib.sha256(FROZEN_SOURCE.encode()).hexdigest()},
        )
        self.assertEqual(lock["golden_payload_sha256"], DIGESTS["expectedSHA256"])
        self.assertEqual(
            lock["golden_production_json_sha256"], DIGESTS["expectedProductionJSONSHA256"]
        )
        self.assertEqual(
            lock["golden_production_zip_sha256"], DIGESTS["expectedProductionZipSHA256"]
        )

    def test_prelaunch_seed_needs_no_flag(self) -> None:
        with self._patched(launched=False), contextlib.redirect_stdout(io.StringIO()):
            result = gate.seed()

        self.assertEqual(result, 0)
        self.assertTrue(self.lock.exists())

    def test_additive_seed_still_requires_a_pinned_digest(self) -> None:
        self.fixture.write_text("  static let expectedSHA256 = \"nope\"\n", encoding="utf-8")
        stderr = io.StringIO()
        with self._patched(launched=True), contextlib.redirect_stderr(stderr):
            result = gate.seed(additive=True)

        self.assertEqual(result, 1)
        self.assertFalse(self.lock.exists())
        self.assertIn("expectedSHA256", stderr.getvalue())

    def test_additive_flag_without_seed_is_rejected(self) -> None:
        stderr = io.StringIO()
        with (
            mock.patch.object(sys, "argv", ["verify_backup_v1_contract.py", "--additive"]),
            contextlib.redirect_stderr(stderr),
        ):
            result = gate.main()

        self.assertEqual(result, 2)
        self.assertIn("--additive only applies to --seed", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
