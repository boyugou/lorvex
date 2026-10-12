#!/usr/bin/env python3
import tempfile
import unittest
from pathlib import Path

import clean_test_defaults as ctd

UUID = "0028B861-F7CD-4AE1-97BE-305CDEA2A930"


class CleanTestDefaultsTests(unittest.TestCase):
    def test_prefixes_are_the_literal_text_before_the_uuid(self):
        with tempfile.TemporaryDirectory() as tmp:
            tests = Path(tmp)
            (tests / "A.swift").write_text(
                'let a = "AppStoreTaskEditingTests.\\(UUID().uuidString)"\n'
                'let b = "LorvexAppleTests-\\(UUID().uuidString)"\n'
                'let c = "test.mobile.cloudSyncMode.\\(UUID().uuidString)"\n'
                'let d = "NoUuidHere.suite"\n',
                encoding="utf-8")
            self.assertEqual(
                ctd.test_suite_prefixes(tests),
                {"AppStoreTaskEditingTests", "LorvexAppleTests", "test.mobile.cloudSyncMode"})

    def test_only_files_of_the_named_prefixes_are_found(self):
        with tempfile.TemporaryDirectory() as tmp:
            prefs = Path(tmp)
            mine = [f"AppStoreTaskEditingTests.{UUID}.plist", f"LorvexAppleTests-{UUID}.plist"]
            others = [
                f"HiMarkdownTests-{UUID}.plist",
                "AppStoreTaskEditingTests.plist",
                f"AppStoreTaskEditingTests.{UUID}.plist.bak",
                "com.lorvex.apple.plist",
            ]
            for name in mine + others:
                (prefs / name).write_text("{}", encoding="utf-8")
            found = {p.name for p in ctd.leftover_files({"AppStoreTaskEditingTests", "LorvexAppleTests"}, prefs)}
            self.assertEqual(found, set(mine))

    def test_the_real_tests_name_a_suite_prefix(self):
        self.assertIn("AppStoreTaskEditingTests", ctd.test_suite_prefixes(ctd.ROOT / "Tests"))


if __name__ == "__main__":
    unittest.main()
