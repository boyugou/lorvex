#!/usr/bin/env python3
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from verify_swiftpm_resource_bundles import resource_bundle_failures


CORE_RESOURCE_PAYLOADS = {
    "schema.sql": b"CREATE TABLE example(id TEXT PRIMARY KEY);\n",
    "checksums.lock": b'{"001":{"name":"001_schema.sql"}}\n',
}


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
                / "LorvexFocusWidget.appex"
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
            core_bundle = root / "LorvexApple_LorvexCore.bundle"
            core_bundle.mkdir(parents=True)
            for name, payload in CORE_RESOURCE_PAYLOADS.items():
                (core_bundle / name).write_bytes(payload)
            contract_dir = (
                root / "LorvexAppleCore_LorvexSync.bundle" / "SyncPayloadContracts"
            )
            contract_dir.mkdir(parents=True)
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
            (app / "LorvexApple_LorvexApple.bundle").mkdir()

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
            for name in (
                "LorvexApple_LorvexCore.bundle",
                "LorvexAppleCore_LorvexSync.bundle",
            ):
                (resources / name).mkdir(parents=True)
            (helper_resources / "LorvexApple_LorvexCore.bundle").mkdir(parents=True)

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
                / "LorvexFocusWidget.appex"
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
                    resource = resources / "LorvexApple_LorvexCore.bundle" / name
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
                    resource = resources / "LorvexApple_LorvexCore.bundle" / name
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
