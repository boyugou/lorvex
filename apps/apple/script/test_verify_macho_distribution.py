#!/usr/bin/env python3
from __future__ import annotations

import unittest

from verify_macho_distribution import has_distribution_safe_path


class VerifyMachODistributionTests(unittest.TestCase):
    def test_distribution_safe_paths_accept_system_and_relative_loader_paths(self) -> None:
        for load_path in [
            "/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit",
            "/usr/lib/libSystem.B.dylib",
            "@rpath/libswiftCore.dylib",
            "@loader_path/../Frameworks/libhelper.dylib",
            "@executable_path/../Frameworks/libhelper.dylib",
        ]:
            self.assertTrue(has_distribution_safe_path(load_path))

    def test_distribution_safe_paths_reject_absolute_build_machine_paths(self) -> None:
        for load_path in [
            "/Users/example/Library/Developer/Xcode/DerivedData/libdebug.dylib",
            "/opt/homebrew/lib/libsqlite3.dylib",
            "/tmp/libswiftCore.dylib",
        ]:
            self.assertFalse(has_distribution_safe_path(load_path))


if __name__ == "__main__":
    unittest.main()
