#!/usr/bin/env python3
from __future__ import annotations

import plistlib
import tempfile
import unittest
from pathlib import Path

from verify_macho_closure import (
    MachOInfo,
    discover_contexts,
    is_system_load,
    parse_load_commands,
    verify_bundle,
)

MACHO_MAGIC = b"\xcf\xfa\xed\xfe" + b"\x00" * 12

OTOOL_OUTPUT = """\
/tmp/Example.app/Frameworks/Example.framework/Example (architecture arm64):
Load command 3
          cmd LC_ID_DYLIB
      cmdsize 64
         name @rpath/Example.framework/Example (offset 24)
Load command 12
          cmd LC_LOAD_DYLIB
      cmdsize 96
         name @rpath/LorvexCore.framework/LorvexCore (offset 24)
   time stamp 2 Wed Dec 31 19:00:02 1969
Load command 13
          cmd LC_LOAD_WEAK_DYLIB
      cmdsize 56
         name /usr/lib/swift/libswiftCompression.dylib (offset 24)
Load command 20
          cmd LC_RPATH
      cmdsize 32
         path @executable_path/Frameworks (offset 12)
/tmp/Example.app/Frameworks/Example.framework/Example (architecture arm64_32):
Load command 12
          cmd LC_LOAD_DYLIB
      cmdsize 96
         name @rpath/LorvexCore.framework/LorvexCore (offset 24)
Load command 20
          cmd LC_RPATH
      cmdsize 32
         path @executable_path/Frameworks (offset 12)
"""


class ParseLoadCommandsTests(unittest.TestCase):
    def test_parses_loads_and_rpaths_excluding_id_dylib(self) -> None:
        info = parse_load_commands(OTOOL_OUTPUT)
        self.assertEqual(
            info.loads,
            [
                "@rpath/LorvexCore.framework/LorvexCore",
                "/usr/lib/swift/libswiftCompression.dylib",
            ],
        )
        self.assertEqual(info.rpaths, ["@executable_path/Frameworks"])

    def test_fat_slices_are_deduplicated(self) -> None:
        info = parse_load_commands(OTOOL_OUTPUT)
        self.assertEqual(info.loads.count("@rpath/LorvexCore.framework/LorvexCore"), 1)
        self.assertEqual(info.rpaths.count("@executable_path/Frameworks"), 1)


class SystemLoadTests(unittest.TestCase):
    def test_system_prefixes_and_swift_runtime_are_system(self) -> None:
        for load in [
            "/System/Library/Frameworks/Foundation.framework/Foundation",
            "/usr/lib/libobjc.A.dylib",
            "@rpath/libswiftCore.dylib",
            "@rpath/libswift_Concurrency.dylib",
        ]:
            self.assertTrue(is_system_load(load), load)

    def test_first_party_loads_are_not_system(self) -> None:
        for load in [
            "@rpath/LorvexDomain.framework/LorvexDomain",
            "@rpath/GRDB_5DC4DB053_PackageProduct.framework/GRDB_5DC4DB053_PackageProduct",
            "@rpath/libLorvexHelper.dylib",
            "@executable_path/Frameworks/LorvexCore.framework/LorvexCore",
        ]:
            self.assertFalse(is_system_load(load), load)


class BundleFixture:
    """Synthetic .app tree with injectable per-image load commands."""

    def __init__(self, root: Path) -> None:
        self.root = root
        self.images: dict[Path, MachOInfo] = {}

    def add_bundle(self, bundle: Path, executable_name: str) -> Path:
        bundle.mkdir(parents=True, exist_ok=True)
        with (bundle / "Info.plist").open("wb") as handle:
            plistlib.dump({"CFBundleExecutable": executable_name}, handle)
        return self.add_image(bundle / executable_name)

    def add_image(self, path: Path, loads: list[str] | None = None, rpaths: list[str] | None = None) -> Path:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(MACHO_MAGIC)
        self.images[path.resolve()] = MachOInfo(loads=loads or [], rpaths=rpaths or [])
        return path

    def set_commands(self, path: Path, loads: list[str] | None = None, rpaths: list[str] | None = None) -> None:
        self.images[path.resolve()] = MachOInfo(loads=loads or [], rpaths=rpaths or [])

    def macho_info(self, path: Path) -> MachOInfo:
        return self.images[Path(path).resolve()]


class VerifyBundleTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.app = Path(self._tmp.name) / "Example.app"
        self.fixture = BundleFixture(self.app)

    def framework(self, name: str, bundle: Path | None = None) -> Path:
        bundle = bundle or self.app
        return self.fixture.add_image(bundle / "Frameworks" / f"{name}.framework" / name)

    def test_complete_closure_passes(self) -> None:
        executable = self.fixture.add_bundle(self.app, "Example")
        core = self.framework("LorvexCore")
        domain = self.framework("LorvexDomain")
        self.fixture.set_commands(
            executable,
            loads=["@rpath/LorvexCore.framework/LorvexCore"],
            rpaths=["/usr/lib/swift", "@executable_path/Frameworks"],
        )
        # The framework's own load resolves through the executable's
        # accumulated run paths (dyld chain semantics), no own LC_RPATH.
        self.fixture.set_commands(core, loads=["@rpath/LorvexDomain.framework/LorvexDomain"])
        self.fixture.set_commands(domain, loads=["/usr/lib/libobjc.A.dylib"])
        self.assertEqual(verify_bundle(self.app, self.fixture.macho_info), [])

    def test_missing_framework_is_reported(self) -> None:
        executable = self.fixture.add_bundle(self.app, "Example")
        core = self.framework("LorvexCore")
        self.fixture.set_commands(
            executable,
            loads=["@rpath/LorvexCore.framework/LorvexCore"],
            rpaths=["@executable_path/Frameworks"],
        )
        self.fixture.set_commands(
            core,
            loads=["@rpath/LorvexDomain.framework/LorvexDomain"],
        )
        failures = verify_bundle(self.app, self.fixture.macho_info)
        self.assertEqual(len(failures), 1)
        self.assertIn("@rpath/LorvexDomain.framework/LorvexDomain", failures[0])
        self.assertIn("LorvexCore", failures[0])

    def test_executable_without_runpath_cannot_resolve_bundled_framework(self) -> None:
        # The H2 shape: the framework file exists, but the executable carries
        # no run path that reaches Frameworks/.
        executable = self.fixture.add_bundle(self.app, "Example")
        core = self.framework("LorvexCore")
        self.fixture.set_commands(
            executable,
            loads=["@rpath/LorvexCore.framework/LorvexCore"],
            rpaths=["/usr/lib/swift"],
        )
        self.fixture.set_commands(core, loads=[])
        failures = verify_bundle(self.app, self.fixture.macho_info)
        # The framework is also unreachable, since the only reference to it
        # cannot resolve.
        self.assertEqual(len(failures), 2)
        self.assertIn("@rpath/LorvexCore.framework/LorvexCore", failures[0])
        self.assertIn("not reachable", failures[1])

    def test_nested_watch_app_and_extension_contexts_are_verified(self) -> None:
        app_executable = self.fixture.add_bundle(self.app, "Example")
        self.fixture.set_commands(app_executable, rpaths=["@executable_path/Frameworks"])

        watch_app = self.app / "Watch" / "WatchApp.app"
        watch_executable = self.fixture.add_bundle(watch_app, "WatchApp")
        watch_core = self.framework("LorvexCore", bundle=watch_app)
        self.fixture.set_commands(
            watch_executable,
            loads=["@rpath/LorvexCore.framework/LorvexCore"],
            rpaths=["@executable_path/Frameworks"],
        )
        self.fixture.set_commands(watch_core, loads=[])

        appex = watch_app / "PlugIns" / "Complication.appex"
        appex_executable = self.fixture.add_bundle(appex, "Complication")
        self.fixture.set_commands(
            appex_executable,
            loads=["@rpath/LorvexCore.framework/LorvexCore"],
            rpaths=["@executable_path/Frameworks", "@executable_path/../../Frameworks"],
        )
        self.assertEqual(verify_bundle(self.app, self.fixture.macho_info), [])

        # Dropping the appex's host-relative run path breaks its closure even
        # though the watch app itself still resolves.
        self.fixture.set_commands(
            appex_executable,
            loads=["@rpath/LorvexCore.framework/LorvexCore"],
            rpaths=["@executable_path/Frameworks"],
        )
        failures = verify_bundle(self.app, self.fixture.macho_info)
        self.assertEqual(len(failures), 1)
        self.assertIn("Complication", failures[0])

    def test_cyclic_load_graph_terminates_and_passes(self) -> None:
        executable = self.fixture.add_bundle(self.app, "Example")
        first = self.framework("LorvexFirst")
        second = self.framework("LorvexSecond")
        self.fixture.set_commands(
            executable,
            loads=["@rpath/LorvexFirst.framework/LorvexFirst"],
            rpaths=["@executable_path/Frameworks"],
        )
        self.fixture.set_commands(
            first,
            loads=["@rpath/LorvexSecond.framework/LorvexSecond"],
            rpaths=["@loader_path/.."],
        )
        self.fixture.set_commands(
            second,
            loads=["@rpath/LorvexFirst.framework/LorvexFirst"],
            rpaths=["@loader_path/.."],
        )
        self.assertEqual(verify_bundle(self.app, self.fixture.macho_info), [])

    def test_unreachable_macho_is_reported(self) -> None:
        executable = self.fixture.add_bundle(self.app, "Example")
        self.fixture.set_commands(executable, loads=[], rpaths=["@executable_path/Frameworks"])
        self.framework("LorvexOrphan")
        failures = verify_bundle(self.app, self.fixture.macho_info)
        self.assertEqual(len(failures), 1)
        self.assertIn("LorvexOrphan", failures[0])
        self.assertIn("not reachable", failures[0])

    def test_macos_layout_contexts_are_discovered(self) -> None:
        contents = self.app / "Contents"
        (contents / "MacOS").mkdir(parents=True)
        with (contents / "Info.plist").open("wb") as handle:
            plistlib.dump({"CFBundleExecutable": "Example"}, handle)
        executable = self.fixture.add_image(contents / "MacOS" / "Example")
        self.fixture.set_commands(executable, loads=["/usr/lib/libSystem.B.dylib"])

        helper = contents / "Helpers" / "Helper.app"
        helper_executable = self.fixture.add_bundle(helper, "Helper")
        self.fixture.set_commands(helper_executable, loads=[])

        contexts = discover_contexts(self.app)
        self.assertEqual(
            [context.executable for context in contexts],
            [executable, helper_executable],
        )
        self.assertEqual(verify_bundle(self.app, self.fixture.macho_info), [])


if __name__ == "__main__":
    unittest.main()
