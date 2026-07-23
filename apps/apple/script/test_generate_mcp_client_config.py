#!/usr/bin/env python3
from __future__ import annotations

import contextlib
import io
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate_mcp_client_config
from generate_mcp_client_config import (
    helper_bundle_path,
    helper_is_sandboxed,
    lorvex_client_metadata,
)


TEST_METADATA = {
    "APP_NAME": "LorvexApple",
    "MCP_SERVER_NAME": "lorvex-apple",
    "MCP_HOST_PRODUCT": "LorvexMCPHost",
}


def _make_app_bundle(root: Path) -> Path:
    """A synthetic --app-bundle with a present, executable MCP helper."""
    app_bundle = root / "LorvexApple.app"
    helper_macos_dir = helper_bundle_path(app_bundle, TEST_METADATA) / "Contents" / "MacOS"
    helper_macos_dir.mkdir(parents=True)
    helper = helper_macos_dir / TEST_METADATA["MCP_HOST_PRODUCT"]
    helper.write_text("#!/bin/sh\nexit 0\n")
    helper.chmod(0o755)
    return app_bundle


class GenerateMCPClientConfigTests(unittest.TestCase):
    def test_lorvex_client_metadata_declares_swift_native_host_strategy(self) -> None:
        self.assertEqual(
            lorvex_client_metadata(TEST_METADATA),
            {
                "app": "LorvexApple",
                "server_name": "lorvex-apple",
                "host_product": "LorvexMCPHost",
                "strategy": {
                    "platform_scope": "apple-only",
                    "mcp_host": "swift-native",
                    "mcp_sdk": "modelcontextprotocol/swift-sdk",
                },
            },
        )

    def test_help_describes_pure_swift_mcp_database_path(self) -> None:
        with mock.patch.object(
            generate_mcp_client_config,
            "load_metadata",
            return_value=TEST_METADATA,
        ), mock.patch.object(sys, "argv", ["generate_mcp_client_config.py", "--help"]):
            output = io.StringIO()
            with self.assertRaises(SystemExit) as raised, contextlib.redirect_stdout(output):
                generate_mcp_client_config.parse_args()

        self.assertEqual(raised.exception.code, 0)
        text = output.getvalue()
        self.assertIn("pure-Swift core service", text)
        self.assertNotIn("Rust core bridge", text)
        self.assertNotIn("bridge dylib", text)

    def test_helper_is_sandboxed_true_when_entitlement_present(self) -> None:
        with mock.patch.object(
            generate_mcp_client_config,
            "signed_entitlements",
            return_value={"com.apple.security.app-sandbox": True},
        ):
            self.assertTrue(helper_is_sandboxed(Path("/unused")))

    def test_helper_is_sandboxed_false_when_entitlement_absent(self) -> None:
        with mock.patch.object(
            generate_mcp_client_config,
            "signed_entitlements",
            return_value={"com.apple.security.application-groups": ["group.x"]},
        ):
            self.assertFalse(helper_is_sandboxed(Path("/unused")))

    def test_helper_is_sandboxed_false_when_unsigned(self) -> None:
        # An unsigned/ad-hoc helper (a plain dev build) has no entitlements at
        # all; codesign exits non-zero rather than returning an empty plist.
        with mock.patch.object(
            generate_mcp_client_config,
            "signed_entitlements",
            side_effect=subprocess.CalledProcessError(1, ["codesign"]),
        ):
            self.assertFalse(helper_is_sandboxed(Path("/unused")))

    def test_main_refuses_external_database_path_for_sandboxed_helper(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            app_bundle = _make_app_bundle(Path(root))
            with mock.patch.object(
                generate_mcp_client_config, "load_metadata", return_value=TEST_METADATA
            ), mock.patch.object(
                generate_mcp_client_config, "helper_is_sandboxed", return_value=True
            ), mock.patch.object(
                sys,
                "argv",
                [
                    "generate_mcp_client_config.py",
                    "--app-bundle",
                    str(app_bundle),
                    "--database-path",
                    "/external/lorvex.db",
                ],
            ):
                with self.assertRaises(SystemExit) as raised:
                    generate_mcp_client_config.main()

            self.assertNotEqual(raised.exception.code, 0)
            message = str(raised.exception.code)
            self.assertIn("sandboxed", message)
            self.assertIn("Lorvex-managed App Group store", message)

    def test_main_allows_external_database_path_for_unsandboxed_helper(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            app_bundle = _make_app_bundle(Path(root))
            output_path = Path(root) / "config.json"
            with mock.patch.object(
                generate_mcp_client_config, "load_metadata", return_value=TEST_METADATA
            ), mock.patch.object(
                generate_mcp_client_config, "helper_is_sandboxed", return_value=False
            ), mock.patch.object(
                sys,
                "argv",
                [
                    "generate_mcp_client_config.py",
                    "--app-bundle",
                    str(app_bundle),
                    "--database-path",
                    "/external/lorvex.db",
                    "--output",
                    str(output_path),
                ],
            ):
                exit_code = generate_mcp_client_config.main()

            self.assertEqual(exit_code, 0)
            payload = output_path.read_text()
            self.assertIn("LORVEX_APPLE_DB_PATH", payload)
            self.assertIn("/external/lorvex.db", payload)

    def test_main_generates_config_without_database_args_regardless_of_sandbox(self) -> None:
        # package_local.sh never passes --database-path, so the refusal must
        # never trigger for the plain packaging call even against a sandboxed
        # helper.
        with tempfile.TemporaryDirectory() as root:
            app_bundle = _make_app_bundle(Path(root))
            output_path = Path(root) / "config.json"
            with mock.patch.object(
                generate_mcp_client_config, "load_metadata", return_value=TEST_METADATA
            ), mock.patch.object(
                generate_mcp_client_config, "helper_is_sandboxed", return_value=True
            ), mock.patch.object(
                sys,
                "argv",
                [
                    "generate_mcp_client_config.py",
                    "--app-bundle",
                    str(app_bundle),
                    "--output",
                    str(output_path),
                ],
            ):
                exit_code = generate_mcp_client_config.main()

            self.assertEqual(exit_code, 0)
            payload = output_path.read_text()
            self.assertNotIn("LORVEX_APPLE_DB_PATH", payload)


if __name__ == "__main__":
    unittest.main()
