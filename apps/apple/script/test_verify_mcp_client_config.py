#!/usr/bin/env python3
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from verify_mcp_client_config import mcp_client_config_failures


TEST_METADATA = {
    "APP_NAME": "LorvexApple",
    "MCP_SERVER_NAME": "lorvex-apple",
    "MCP_HOST_PRODUCT": "LorvexMCPHost",
}


def lorvex_metadata(*, mcp_host: str = "swift-native") -> dict[str, object]:
    return {
        "app": "LorvexApple",
        "server_name": "lorvex-apple",
        "host_product": "LorvexMCPHost",
        "strategy": {
            "platform_scope": "apple-only",
            "mcp_host": mcp_host,
            "mcp_sdk": "modelcontextprotocol/swift-sdk",
        },
    }


def make_helper(root: Path, *, executable: bool = True) -> Path:
    helper = (
        root
        / "LorvexApple.app"
        / "Contents"
        / "Helpers"
        / "LorvexMCPHost.app"
        / "Contents"
        / "MacOS"
        / "LorvexMCPHost"
    )
    helper.parent.mkdir(parents=True)
    helper.write_text("#!/usr/bin/env sh\n", encoding="utf-8")
    helper.chmod(0o755 if executable else 0o644)
    return helper


class VerifyMCPClientConfigTests(unittest.TestCase):
    def test_mcp_client_config_accepts_bundled_executable_helper(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            helper = make_helper(root)
            config = {
                "lorvex": lorvex_metadata(),
                "mcpServers": {
                    "lorvex-apple": {
                        "command": str(helper),
                        "args": [],
                        "env": {
                            "LORVEX_APPLE_DB_PATH": "/tmp/lorvex.db",
                        },
                    }
                }
            }

            self.assertEqual(
                mcp_client_config_failures(
                    config=config,
                    app_bundle=root / "LorvexApple.app",
                    metadata=TEST_METADATA,
                ),
                [],
            )

    def test_mcp_client_config_rejects_non_executable_helper(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            helper = make_helper(root, executable=False)
            config = {
                "lorvex": lorvex_metadata(),
                "mcpServers": {
                    "lorvex-apple": {
                        "command": str(helper),
                        "args": [],
                    }
                }
            }

            self.assertEqual(
                mcp_client_config_failures(
                    config=config,
                    app_bundle=root / "LorvexApple.app",
                    metadata=TEST_METADATA,
                ),
                [f"helper binary is not executable: {helper}"],
            )

    def test_mcp_client_config_rejects_wrong_command_and_env(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            helper = make_helper(root)
            config = {
                "lorvex": lorvex_metadata(mcp_host="rust"),
                "mcpServers": {
                    "lorvex-apple": {
                        "command": "/tmp/wrong-helper",
                        "args": ["--bad"],
                        "env": {
                            # The bookmark env is no longer an allowed key, so it
                            # is now flagged as unexpected alongside UNEXPECTED.
                            "LORVEX_APPLE_DB_BOOKMARK_BASE64": "YWJjMTIz",
                            "UNEXPECTED": "1",
                        },
                    }
                }
            }

            self.assertEqual(
                mcp_client_config_failures(
                    config=config,
                    app_bundle=root / "LorvexApple.app",
                    metadata=TEST_METADATA,
                ),
                [
                    "lorvex metadata mismatch: "
                    f"{lorvex_metadata(mcp_host="rust")!r}",
                    f"wrong command: expected {helper}, got '/tmp/wrong-helper'",
                    "expected empty args, got ['--bad']",
                    "unexpected env keys: "
                    "['LORVEX_APPLE_DB_BOOKMARK_BASE64', 'UNEXPECTED']",
                ],
            )

    def test_mcp_client_config_rejects_missing_server(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            make_helper(root)

            self.assertEqual(
                mcp_client_config_failures(
                    config={"mcpServers": {}},
                    app_bundle=root / "LorvexApple.app",
                    metadata=TEST_METADATA,
                ),
                ["missing mcpServers.lorvex-apple"],
            )

    def test_mcp_client_config_rejects_missing_lorvex_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            helper = make_helper(root)

            self.assertEqual(
                mcp_client_config_failures(
                    config={
                        "mcpServers": {
                            "lorvex-apple": {
                                "command": str(helper),
                                "args": [],
                            }
                        }
                    },
                    app_bundle=root / "LorvexApple.app",
                    metadata=TEST_METADATA,
                ),
                ["lorvex metadata mismatch: None"],
            )


if __name__ == "__main__":
    unittest.main()
