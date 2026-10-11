#!/usr/bin/env python3
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import bump_build

PLIST = """<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
\t<key>CFBundleShortVersionString</key>
\t<string>1.0.0</string>
\t<key>CFBundleVersion</key>
\t<string>{build}</string>
</dict>
</plist>
"""

FILES = {
    "script/app_metadata.sh": 'MARKETING_VERSION="1.0.0"\nBUILD_VERSION="{build}"\n',
    "Sources/LorvexCore/Models/ProductMetadata.swift": (
        '  public static let marketingVersion = "1.0.0"\n'
        '  public static let buildVersion = "{build}"\n'
    ),
    "Config/XcodeGen/project.yml": '    CURRENT_PROJECT_VERSION: "{build}"\n    MARKETING_VERSION: "1.0.0"\n',
    "Config/LorvexMobileApp-Info.plist": PLIST,
    "Config/LorvexWatchComplication-Info.plist": PLIST,
    "Config/LorvexWidgets-Info.plist": PLIST,
    "Config/LorvexMCPHost-Info.plist": PLIST,
    "Tests/LorvexAppleTests/AppMetadataTests.swift": '  #expect(AppMetadata.buildVersion == "{build}")\n',
}


class BumpBuildTests(unittest.TestCase):
    def setUp(self) -> None:
        self._temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self._temporary_directory.name)
        for relative, template in FILES.items():
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(template.format(build="116"), encoding="utf-8")

    def tearDown(self) -> None:
        self._temporary_directory.cleanup()

    def read(self, relative: str) -> str:
        return (self.root / relative).read_text(encoding="utf-8")

    def test_bumps_every_file_by_one_and_leaves_the_rest_alone(self) -> None:
        self.assertEqual(bump_build.bump(self.root), 117)
        for relative, template in FILES.items():
            self.assertEqual(self.read(relative), template.format(build="117"), relative)

    def test_an_explicit_number_above_the_current_one_is_used(self) -> None:
        self.assertEqual(bump_build.bump(self.root, 120), 120)
        self.assertEqual(self.read("script/app_metadata.sh"), FILES["script/app_metadata.sh"].format(build="120"))

    def test_a_number_not_above_the_current_one_is_refused(self) -> None:
        for number in (116, 115):
            with self.assertRaises(SystemExit):
                bump_build.bump(self.root, number)
        self.assertEqual(self.read("script/app_metadata.sh"), FILES["script/app_metadata.sh"].format(build="116"))

    def test_a_file_that_drifted_from_the_expected_shape_changes_nothing(self) -> None:
        drifted = self.root / "Config/LorvexWidgets-Info.plist"
        drifted.write_text(PLIST.format(build="$(CURRENT_PROJECT_VERSION)"), encoding="utf-8")
        with self.assertRaises(SystemExit):
            bump_build.bump(self.root)
        for relative, template in FILES.items():
            if relative == "Config/LorvexWidgets-Info.plist":
                continue
            self.assertEqual(self.read(relative), template.format(build="116"), relative)

    def test_a_file_with_two_matches_is_refused(self) -> None:
        path = self.root / "Config/LorvexMobileApp-Info.plist"
        path.write_text(PLIST.format(build="116") + PLIST.format(build="116"), encoding="utf-8")
        with self.assertRaises(SystemExit):
            bump_build.bump(self.root)

    def test_the_marketing_version_is_never_touched(self) -> None:
        bump_build.bump(self.root)
        self.assertIn('MARKETING_VERSION="1.0.0"', self.read("script/app_metadata.sh"))
        self.assertIn('marketingVersion = "1.0.0"', self.read("Sources/LorvexCore/Models/ProductMetadata.swift"))


if __name__ == "__main__":
    unittest.main()
