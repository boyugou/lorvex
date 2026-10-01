#!/usr/bin/env python3
from __future__ import annotations

import plistlib
import tempfile
import unittest
from pathlib import Path

from verify_swiftpm_resource_bundles import resource_bundle_failures


CORE_RESOURCE_PAYLOADS = {
    "schema.sql": b"CREATE TABLE example(id TEXT PRIMARY KEY);\n",
    "checksums.lock": b'{"001":{"name":"001_schema.sql"}}\n',
}


def _wrapped_bundle(root: Path, name: str) -> Path:
    """Create a bundle in the wrapped macOS layout and return its payload root."""
    bundle = root / name
    payload = bundle / "Contents" / "Resources"
    payload.mkdir(parents=True)
    _write_bundle_plist(bundle)
    return payload


def _write_bundle_plist(bundle: Path, **overrides: object) -> Path:
    """Stamp the identity the staging gives every embedded resource bundle."""
    info: dict[str, object] = {
        "CFBundleIdentifier": f"com.lorvex.apple.resource.{bundle.stem.lower()}",
        "CFBundleName": bundle.stem,
        "CFBundlePackageType": "BNDL",
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleDevelopmentRegion": "en",
        "CFBundleSupportedPlatforms": ["MacOSX"],
        "LSMinimumSystemVersion": "15.0",
    }
    info.update(overrides)
    plist_path = bundle / "Contents" / "Info.plist"
    plist_path.parent.mkdir(parents=True, exist_ok=True)
    plist_path.write_bytes(
        plistlib.dumps({key: value for key, value in info.items() if value is not None})
    )
    return plist_path


class VerifySwiftPMResourceBundlesTests(unittest.TestCase):
    @staticmethod
    def _source_contracts(
        directory: Path,
        manifests: dict[str, bytes] | None = None,
    ) -> tuple[Path, Path, dict[str, bytes]]:
        authority = directory / "authority"
        embedded = directory / "embedded"
        authority.mkdir()
        embedded.mkdir()
        payloads = manifests or {"001.json": b'{"payload_schema_version":1}\n'}
        for name, payload in payloads.items():
            (authority / name).write_bytes(payload)
            (embedded / name).write_bytes(payload)
        for name, payload in CORE_RESOURCE_PAYLOADS.items():
            (directory / name).write_bytes(payload)
        return authority, embedded, payloads

    @staticmethod
    def _surface_resources(app: Path) -> dict[str, Path]:
        return {
            "app": app / "Contents" / "Resources",
            "MCP helper": (
                app
                / "Contents"
                / "Helpers"
                / "LorvexMCPHost.app"
                / "Contents"
                / "Resources"
            ),
            "widget extension": (
                app
                / "Contents"
                / "PlugIns"
                / "LorvexWidgets.appex"
                / "Contents"
                / "Resources"
            ),
        }

    @staticmethod
    def _verification_failures(
        app: Path,
        root: Path,
        authority: Path,
        embedded: Path,
    ) -> list[str]:
        return resource_bundle_failures(
            app,
            authority_dir=authority,
            embedded_dir=embedded,
            schema_authority_path=root / "schema.sql",
            checksums_authority_path=root / "checksums.lock",
        )

    @staticmethod
    def _install_resource_bundles(
        app: Path,
        manifests: dict[str, bytes],
    ) -> None:
        for root in VerifySwiftPMResourceBundlesTests._surface_resources(app).values():
            root.mkdir(parents=True, exist_ok=True)
            core_payload = _wrapped_bundle(root, "LorvexApple_LorvexCore.bundle")
            for name, payload in CORE_RESOURCE_PAYLOADS.items():
                (core_payload / name).write_bytes(payload)
            sync_payload = _wrapped_bundle(root, "LorvexAppleCore_LorvexSync.bundle")
            contract_dir = sync_payload / "SyncPayloadContracts"
            contract_dir.mkdir()
            for name, payload in manifests.items():
                (contract_dir / name).write_bytes(payload)

    def test_accepts_resources_bundle_layout(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / "Lorvex.app"
            authority, embedded, manifests = self._source_contracts(
                root, {"001.json": b"one\n", "002.json": b"two\n"}
            )
            self._install_resource_bundles(app, manifests)

            self.assertEqual(
                self._verification_failures(app, root, authority, embedded),
                [],
            )

    def test_rejects_missing_resource_bundles(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "Lorvex.app"
            (app / "Contents" / "Resources").mkdir(parents=True)

            self.assertEqual(
                resource_bundle_failures(app),
                [f"no SwiftPM resource bundles found in {app / 'Contents' / 'Resources'}"],
            )

    def test_rejects_root_bundle_entries(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / "Lorvex.app"
            authority, embedded, manifests = self._source_contracts(root)
            self._install_resource_bundles(app, manifests)
            _wrapped_bundle(app, "LorvexApple_LorvexApple.bundle")

            self.assertEqual(
                self._verification_failures(app, root, authority, embedded),
                [
                    "SwiftPM resource bundles must live in Contents/Resources, "
                    "not the .app root: ['LorvexApple_LorvexApple.bundle']"
                ],
            )

    def test_rejects_missing_sync_bundle_from_mcp_helper(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / "Lorvex.app"
            authority, embedded, _ = self._source_contracts(root)
            resources = app / "Contents" / "Resources"
            helper_resources = (
                app
                / "Contents"
                / "Helpers"
                / "LorvexMCPHost.app"
                / "Contents"
                / "Resources"
            )
            resources.mkdir(parents=True)
            helper_resources.mkdir(parents=True)
            for name in (
                "LorvexApple_LorvexCore.bundle",
                "LorvexAppleCore_LorvexSync.bundle",
            ):
                _wrapped_bundle(resources, name)
            _wrapped_bundle(helper_resources, "LorvexApple_LorvexCore.bundle")

            self.assertIn(
                "required SwiftPM resource bundle missing from MCP helper: "
                "LorvexAppleCore_LorvexSync.bundle",
                self._verification_failures(app, root, authority, embedded),
            )

    def test_rejects_missing_sync_bundle_from_widget_extension(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / "Lorvex.app"
            authority, embedded, manifests = self._source_contracts(root)
            self._install_resource_bundles(app, manifests)
            (
                app
                / "Contents"
                / "PlugIns"
                / "LorvexWidgets.appex"
                / "Contents"
                / "Resources"
                / "LorvexAppleCore_LorvexSync.bundle"
            ).rename(root / "removed-sync-bundle")

            self.assertIn(
                "required SwiftPM resource bundle missing from widget extension: "
                "LorvexAppleCore_LorvexSync.bundle",
                self._verification_failures(app, root, authority, embedded),
            )

    def test_rejects_missing_numbered_manifest_from_every_surface(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / "Lorvex.app"
            authority, embedded, manifests = self._source_contracts(root)
            self._install_resource_bundles(app, manifests)
            for surface, resources in self._surface_resources(app).items():
                manifest = (
                    resources
                    / "LorvexAppleCore_LorvexSync.bundle"
                    / "Contents"
                    / "Resources"
                    / "SyncPayloadContracts"
                    / "001.json"
                )
                with self.subTest(surface=surface):
                    manifest.unlink()
                    self.assertIn(
                        f"payload contract manifest missing from {surface}: 001.json",
                        self._verification_failures(app, root, authority, embedded),
                    )
                    manifest.write_bytes(manifests["001.json"])

    def test_rejects_extra_numbered_manifest_from_every_surface(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / "Lorvex.app"
            authority, embedded, manifests = self._source_contracts(root)
            self._install_resource_bundles(app, manifests)
            for surface, resources in self._surface_resources(app).items():
                manifest = (
                    resources
                    / "LorvexAppleCore_LorvexSync.bundle"
                    / "Contents"
                    / "Resources"
                    / "SyncPayloadContracts"
                    / "999.json"
                )
                with self.subTest(surface=surface):
                    manifest.write_bytes(b"extra\n")
                    self.assertIn(
                        "payload contract manifest in "
                        f"{surface} has no authority manifest: 999.json",
                        self._verification_failures(app, root, authority, embedded),
                    )
                    manifest.unlink()

    def test_rejects_drifted_numbered_manifest_from_every_surface(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / "Lorvex.app"
            authority, embedded, manifests = self._source_contracts(root)
            self._install_resource_bundles(app, manifests)
            for surface, resources in self._surface_resources(app).items():
                manifest = (
                    resources
                    / "LorvexAppleCore_LorvexSync.bundle"
                    / "Contents"
                    / "Resources"
                    / "SyncPayloadContracts"
                    / "001.json"
                )
                with self.subTest(surface=surface):
                    manifest.write_bytes(b"drift\n")
                    self.assertIn(
                        "payload contract manifest in "
                        f"{surface} differs from authority: 001.json",
                        self._verification_failures(app, root, authority, embedded),
                    )
                    manifest.write_bytes(manifests["001.json"])

    def test_rejects_missing_core_resource_from_every_surface(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / "Lorvex.app"
            authority, embedded, manifests = self._source_contracts(root)
            self._install_resource_bundles(app, manifests)
            for surface, resources in self._surface_resources(app).items():
                for name, payload in CORE_RESOURCE_PAYLOADS.items():
                    resource = (
                        resources
                        / "LorvexApple_LorvexCore.bundle"
                        / "Contents"
                        / "Resources"
                        / name
                    )
                    with self.subTest(surface=surface, resource=name):
                        resource.unlink()
                        self.assertIn(
                            f"LorvexCore resource missing from {surface}: {name}",
                            self._verification_failures(
                                app, root, authority, embedded
                            ),
                        )
                        resource.write_bytes(payload)

    def test_rejects_drifted_core_resource_from_every_surface(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / "Lorvex.app"
            authority, embedded, manifests = self._source_contracts(root)
            self._install_resource_bundles(app, manifests)
            for surface, resources in self._surface_resources(app).items():
                for name, payload in CORE_RESOURCE_PAYLOADS.items():
                    resource = (
                        resources
                        / "LorvexApple_LorvexCore.bundle"
                        / "Contents"
                        / "Resources"
                        / name
                    )
                    with self.subTest(surface=surface, resource=name):
                        resource.write_bytes(b"drift\n")
                        self.assertIn(
                            "LorvexCore resource in "
                            f"{surface} differs from authority: {name}",
                            self._verification_failures(
                                app, root, authority, embedded
                            ),
                        )
                        resource.write_bytes(payload)

    def test_rejects_bundle_without_info_plist_on_every_surface(self) -> None:
        """A package that omits `defaultLocalization` stages a bundle with no plist."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / "Lorvex.app"
            authority, embedded, manifests = self._source_contracts(root)
            self._install_resource_bundles(app, manifests)
            for surface, resources in self._surface_resources(app).items():
                bundle = resources / "LorvexAppleCore_LorvexSync.bundle"
                plist_path = bundle / "Contents" / "Info.plist"
                payload = plist_path.read_bytes()
                with self.subTest(surface=surface):
                    plist_path.unlink()
                    relative = bundle.relative_to(app)
                    self.assertIn(
                        f"staged bundle has no Info.plist: {relative}",
                        self._verification_failures(app, root, authority, embedded),
                    )
                    plist_path.write_bytes(payload)

    def test_rejects_bundle_missing_a_required_plist_key(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / "Lorvex.app"
            authority, embedded, manifests = self._source_contracts(root)
            self._install_resource_bundles(app, manifests)
            bundle = app / "Contents" / "Resources" / "LorvexApple_LorvexCore.bundle"
            for key in (
                "CFBundleIdentifier",
                "CFBundleName",
                "CFBundleDevelopmentRegion",
            ):
                with self.subTest(key=key):
                    _write_bundle_plist(bundle, **{key: None})
                    self.assertIn(
                        f"staged bundle Info.plist is missing {key}: "
                        f"{bundle.relative_to(app)}",
                        self._verification_failures(app, root, authority, embedded),
                    )
            _write_bundle_plist(bundle)

    def test_rejects_bundle_with_wrong_package_type(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / "Lorvex.app"
            authority, embedded, manifests = self._source_contracts(root)
            self._install_resource_bundles(app, manifests)
            bundle = app / "Contents" / "Resources" / "LorvexApple_LorvexCore.bundle"
            _write_bundle_plist(bundle, CFBundlePackageType="APPL")

            self.assertIn(
                "staged bundle Info.plist CFBundlePackageType is 'APPL', expected "
                f"'BNDL': {bundle.relative_to(app)}",
                self._verification_failures(app, root, authority, embedded),
            )

    def test_rejects_flat_bundle_layout(self) -> None:
        """`swift build` emits the flat iOS shape; the macOS payload must be wrapped."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / "Lorvex.app"
            authority, embedded, manifests = self._source_contracts(root)
            self._install_resource_bundles(app, manifests)
            flat = app / "Contents" / "Resources" / "Flat_Bundle.bundle"
            flat.mkdir(parents=True)
            (flat / "payload.json").write_bytes(b"{}\n")

            self.assertIn(
                "staged bundle uses the flat iOS layout, expected a wrapped "
                f"Contents/ directory: {flat.relative_to(app)}",
                self._verification_failures(app, root, authority, embedded),
            )

    def test_rejects_payload_left_outside_contents(self) -> None:
        """A half-wrapped bundle keeps resources the loader will not find."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / "Lorvex.app"
            authority, embedded, manifests = self._source_contracts(root)
            self._install_resource_bundles(app, manifests)
            bundle = app / "Contents" / "Resources" / "LorvexApple_LorvexCore.bundle"
            (bundle / "stray.json").write_bytes(b"{}\n")

            self.assertIn(
                "staged bundle keeps payload outside Contents/, so it was "
                f"wrapped incompletely: {bundle.relative_to(app)}: ['stray.json']",
                self._verification_failures(app, root, authority, embedded),
            )

    def test_rejects_embedded_source_drift_before_packaging(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / "Lorvex.app"
            authority, embedded, manifests = self._source_contracts(root)
            self._install_resource_bundles(app, manifests)
            (embedded / "001.json").write_bytes(b"drift\n")

            self.assertIn(
                "embedded payload contract differs from authority: 001.json",
                self._verification_failures(app, root, authority, embedded),
            )


if __name__ == "__main__":
    unittest.main()
