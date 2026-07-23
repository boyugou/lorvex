#!/usr/bin/env python3
"""Verify generated Lorvex MCP client configuration."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

from metadata_env import load_metadata
from release_strategy import APPLE_RELEASE_STRATEGY


ROOT = Path(__file__).resolve().parents[1]


def expected_lorvex_client_metadata(metadata: dict[str, str]) -> dict[str, object]:
    return {
        "app": metadata["APP_NAME"],
        "server_name": metadata["MCP_SERVER_NAME"],
        "host_product": metadata["MCP_HOST_PRODUCT"],
        "strategy": {
            "platform_scope": APPLE_RELEASE_STRATEGY["platform_scope"],
            "mcp_host": APPLE_RELEASE_STRATEGY["mcp_host"],
            "mcp_sdk": APPLE_RELEASE_STRATEGY["mcp_sdk"],
        },
    }


def mcp_client_config_failures(
    *,
    config: dict,
    app_bundle: Path,
    metadata: dict[str, str],
) -> list[str]:
    server_name = metadata["MCP_SERVER_NAME"]
    helper = (
        app_bundle
        / "Contents"
        / "Helpers"
        / f"{metadata['MCP_HOST_PRODUCT']}.app"
        / "Contents"
        / "MacOS"
        / metadata["MCP_HOST_PRODUCT"]
    )
    failures: list[str] = []

    expected_metadata = expected_lorvex_client_metadata(metadata)
    if config.get("lorvex") != expected_metadata:
        failures.append(f"lorvex metadata mismatch: {config.get('lorvex')!r}")

    servers = config.get("mcpServers")
    if not isinstance(servers, dict) or server_name not in servers:
        return [f"missing mcpServers.{server_name}"]

    server = servers[server_name]
    if not isinstance(server, dict):
        return [f"mcpServers.{server_name} must be an object, got {type(server).__name__}"]

    command = server.get("command")
    if not isinstance(command, str):
        failures.append(f"command must be a string, got {command!r}")
    elif command != str(helper) and Path(command).resolve() != helper.resolve():
        failures.append(f"wrong command: expected {helper}, got {command!r}")

    if server.get("args") != []:
        failures.append(f"expected empty args, got {server.get('args')!r}")
    if not helper.is_file():
        failures.append(f"missing helper binary: {helper}")
    elif not os.access(helper, os.X_OK):
        failures.append(f"helper binary is not executable: {helper}")

    env = server.get("env", {})
    if not isinstance(env, dict):
        failures.append(f"env must be an object when present, got {type(env).__name__}")
        return failures

    allowed_env = {"LORVEX_APPLE_DB_PATH"}
    unexpected = sorted(set(env) - allowed_env)
    if unexpected:
        failures.append(f"unexpected env keys: {unexpected}")

    return failures


def main() -> int:
    if len(sys.argv) != 3:
        print(
            f"usage: {Path(sys.argv[0]).name} /path/to/config.json /path/to/LorvexApple.app",
            file=sys.stderr,
        )
        return 2

    config_path = Path(sys.argv[1])
    app_bundle = Path(sys.argv[2])
    metadata = load_metadata()
    config = json.loads(config_path.read_text())
    failures = mcp_client_config_failures(
        config=config,
        app_bundle=app_bundle,
        metadata=metadata,
    )
    if failures:
        for failure in failures:
            print(failure, file=sys.stderr)
        return 1

    print(f"MCP client config verification passed: {config_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
