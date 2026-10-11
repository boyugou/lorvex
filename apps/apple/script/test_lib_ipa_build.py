#!/usr/bin/env python3
from __future__ import annotations

import plistlib
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path

LIB = Path(__file__).resolve().parent / "lib_ipa_build.sh"


def info_plist(build: str) -> bytes:
    return plistlib.dumps({"CFBundleVersion": build}, fmt=plistlib.FMT_BINARY)


class IpaBuildNumberTests(unittest.TestCase):
    def setUp(self) -> None:
        self._temporary_directory = tempfile.TemporaryDirectory()
        self.directory = Path(self._temporary_directory.name)

    def tearDown(self) -> None:
        self._temporary_directory.cleanup()

    def ipa(self, entries: dict[str, bytes]) -> Path:
        path = self.directory / "app.ipa"
        with zipfile.ZipFile(path, "w") as archive:
            for name, data in entries.items():
                archive.writestr(name, data)
        return path

    def build_number(self, ipa: Path) -> str:
        result = subprocess.run(
            ["bash", "-c", f'source "{LIB}"; ipa_build_number "{ipa}"'],
            capture_output=True,
            text=True,
        )
        return result.stdout.strip()

    def test_the_iphone_app_is_read_not_the_embedded_watch_app(self) -> None:
        ipa = self.ipa(
            {
                "Payload/Phone.app/Watch/Watch.app/Info.plist": info_plist("watch-1"),
                "Payload/Phone.app/Info.plist": info_plist("117"),
            }
        )
        self.assertEqual(self.build_number(ipa), "117")

    def test_the_order_of_the_entries_does_not_matter(self) -> None:
        ipa = self.ipa(
            {
                "Payload/Phone.app/Info.plist": info_plist("117"),
                "Payload/Phone.app/Watch/Watch.app/Info.plist": info_plist("watch-1"),
            }
        )
        self.assertEqual(self.build_number(ipa), "117")

    def test_a_missing_package_prints_nothing(self) -> None:
        self.assertEqual(self.build_number(self.directory / "absent.ipa"), "")

    def test_a_package_without_an_app_plist_prints_nothing(self) -> None:
        ipa = self.ipa({"Payload/Phone.app/Other.txt": b"x"})
        self.assertEqual(self.build_number(ipa), "")


if __name__ == "__main__":
    unittest.main()
