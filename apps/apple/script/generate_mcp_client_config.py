#!/usr/bin/env python3
"""Generate MCP client configuration for the bundled Lorvex Swift helper.

Sandboxed/packaged builds (Mac App Store or Developer ID, both signed with
``Config/LorvexMCPHost.entitlements``) ship a helper that only ever opens the
Lorvex-managed App Group store — it ignores ``LORVEX_APPLE_DB_PATH`` under the
sandbox's managed-only guard (see ``CoreBridgeConfiguration``). Only an
unsandboxed dev/source build (ad-hoc signed, e.g. via ``script/package_local.sh``
with the default ``CODE_SIGN_IDENTITY=-``) honors a dev database path override.
This script detects which kind of ``--app-bundle`` it was pointed at by
inspecting the signed helper's entitlements (``signed_entitlements``, shared with
``verify_codesign_entitlements.py``) and refuses to emit a config pairing a
sandboxed helper with a database path override, since that config would silently
fail at runtime instead of connecting.
"""

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path

from metadata_env import load_metadata
from release_strategy import APPLE_RELEASE_STRATEGY
from verify_codesign_entitlements import signed_entitlements


ROOT = Path(__file__).resolve().parents[1]


def lorvex_client_metadata(metadata: dict[str, str]) -> dict[str, object]:
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


def helper_bundle_path(app_bundle: Path, metadata: dict[str, str]) -> Path:
    return app_bundle / "Contents" / "Helpers" / f"{metadata['MCP_HOST_PRODUCT']}.app"


def helper_is_sandboxed(helper_bundle: Path) -> bool:
    """Whether the signed helper at ``helper_bundle`` carries the app-sandbox
    entitlement — the same signal ``verify_codesign_entitlements.py`` asserts
    at packaging time. An unsigned or ad-hoc-signed helper (a plain dev build,
    or one packaged with the default ``CODE_SIGN_IDENTITY=-``) carries no
    entitlements at all and is not sandboxed; ``codesign`` exits non-zero for
    those, which reads as "not sandboxed" here rather than a hard error, since
    generating a config for a dev build is exactly the case this script must
    keep supporting.
    """
    try:
        entitlements = signed_entitlements(helper_bundle)
    except subprocess.CalledProcessError:
        return False
    return entitlements.get("com.apple.security.app-sandbox") is True


def parse_args() -> argparse.Namespace:
    metadata = load_metadata()
    default_app = ROOT / "dist" / f"{metadata['APP_NAME']}.app"
    parser = argparse.ArgumentParser(
        description="Generate Claude/Codex-style MCP stdio config for LorvexApple."
    )
    parser.add_argument(
        "--app-bundle",
        type=Path,
        default=default_app,
        help=f"Path to the Lorvex app bundle. Default: {default_app}",
    )
    parser.add_argument(
        "--database-path",
        help=(
            "Optional Lorvex database path override, for an unsandboxed dev/source "
            "build only: the Apple app's pure-Swift core service opens it directly. "
            "Refused for a sandboxed/packaged --app-bundle (MAS or Developer ID), "
            "which can only open the Lorvex-managed App Group store."
        ),
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="Write JSON to this path instead of stdout.",
    )
    return parser.parse_args()


def main() -> int:
    metadata = load_metadata()
    args = parse_args()
    helper_bundle = helper_bundle_path(args.app_bundle, metadata)
    helper = (
        helper_bundle
        / "Contents"
        / "MacOS"
        / metadata["MCP_HOST_PRODUCT"]
    )

    if not helper.is_file():
        raise SystemExit(f"missing MCP helper: {helper}")

    env: dict[str, str] = {}
    if args.database_path:
        env["LORVEX_APPLE_DB_PATH"] = args.database_path

    if env and helper_is_sandboxed(helper_bundle):
        raise SystemExit(
            "refusing to generate a database-path-override MCP config: the helper at "
            f"{helper_bundle} is sandboxed (com.apple.security.app-sandbox) and can "
            "only open the Lorvex-managed App Group store; "
            "LORVEX_APPLE_DB_PATH would be ignored at runtime. Omit --database-path "
            "for a sandboxed/packaged build, or point --app-bundle at an unsandboxed "
            "dev/source build (ad-hoc signed, e.g. via script/package_local.sh) to "
            "use a database path override."
        )

    server: dict[str, object] = {
        "command": str(helper),
        "args": [],
    }
    if env:
        server["env"] = env

    config = {
        "lorvex": lorvex_client_metadata(metadata),
        "mcpServers": {
            metadata["MCP_SERVER_NAME"]: server
        }
    }
    payload = json.dumps(config, indent=2, sort_keys=True) + "\n"

    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(payload)
    else:
        print(payload, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
