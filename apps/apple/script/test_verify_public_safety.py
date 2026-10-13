#!/usr/bin/env python3
"""Unit tests for the public-safety gate's per-line and per-path rules."""

import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import verify_public_safety as gate  # noqa: E402


class LineFindingsTests(unittest.TestCase):
    def test_a_placeholder_does_not_hide_a_real_address_after_it(self):
        found = gate.line_findings("a@example.com and someone@gmail.com")  # public-safety: allow
        self.assertEqual([name for name, _ in found], ["email address"])
        self.assertEqual(found[0][1], "someone@gmail.com")  # public-safety: allow

    def test_a_placeholder_alone_is_clean(self):
        self.assertEqual(gate.line_findings("write to alice@example.com"), [])

    def test_a_placeholder_home_path_does_not_hide_a_real_one(self):
        found = gate.line_findings("/Users/me/x then /Users/realperson/y")  # public-safety: allow
        self.assertEqual([text for _, text in found], ["/Users/realperson/"])  # public-safety: allow

    def test_machine_temporary_path_is_found(self):
        found = gate.line_findings("see /private/tmp/claude-501/x")  # public-safety: allow
        self.assertEqual([name for name, _ in found], ["machine temporary path"])


class PathRulesTests(unittest.TestCase):
    def matches(self, path: str) -> bool:
        return any(rule.search(path) for _, rule in gate.PATH_RULES)

    def test_credential_files_are_refused(self):
        for path in ["secrets/x.env", "a/AuthKey.p8", "k.pem", "dir/server.key", "id_rsa", ".env"]:
            self.assertTrue(self.matches(path), path)

    def test_ordinary_files_are_not(self):
        for path in ["README.md", "apps/apple/Package.swift", "docs/keyboard.md"]:
            self.assertFalse(self.matches(path), path)


if __name__ == "__main__":
    unittest.main()
