#!/usr/bin/env python3
"""Generate a machine-readable release manifest for Lorvex Apple artifacts."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from expected_mcp_tools import EXPECTED_MCP_TOOLS
from metadata_env import load_metadata
from quality_gates import quality_gate_manifest
from release_strategy import (
    APPLE_RELEASE_STRATEGY,
    CLOUDKIT_PRODUCTION_RELEASE_READINESS,
    CLOUDKIT_SYNC_READINESS,
    SYSTEM_INTENTS_ACTIONS,
    SYSTEM_INTENTS_CAPABILITIES,
    SYSTEM_INTENTS_PRODUCT,
)


ROOT = Path(__file__).resolve().parents[1]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_args() -> argparse.Namespace:
    metadata = load_metadata()
    default_archive = (
        ROOT
        / "dist"
        / f"{metadata['APP_NAME']}-{metadata['MARKETING_VERSION']}+{metadata['BUILD_VERSION']}.zip"
    )
    default_app = ROOT / "dist" / f"{metadata['APP_NAME']}.app"
    default_mcp_config = ROOT / "dist" / "lorvex-apple-mcp-client.json"
    default_platform_manifest = ROOT / "dist" / "lorvex-apple-platform-manifest.json"
    default_output = ROOT / "dist" / "lorvex-apple-release-manifest.json"

    parser = argparse.ArgumentParser(description="Generate Lorvex Apple release manifest.")
    parser.add_argument("--archive", type=Path, default=default_archive)
    parser.add_argument("--app-bundle", type=Path, default=default_app)
    parser.add_argument("--mcp-config", type=Path, default=default_mcp_config)
    parser.add_argument("--platform-manifest", type=Path, default=default_platform_manifest)
    parser.add_argument("--output", type=Path, default=default_output)
    return parser.parse_args()


def main() -> int:
    metadata = load_metadata()
    args = parse_args()
    helper_bundle = args.app_bundle / "Contents" / "Helpers" / f"{metadata['MCP_HOST_PRODUCT']}.app"
    helper = helper_bundle / "Contents" / "MacOS" / metadata["MCP_HOST_PRODUCT"]
    widget = args.app_bundle / "Contents" / "PlugIns" / metadata["WIDGET_APPEX_NAME"]
    privacy_manifest = args.app_bundle / "Contents" / "Resources" / "PrivacyInfo.xcprivacy"
    widget_privacy_manifest = widget / "Contents" / "Resources" / "PrivacyInfo.xcprivacy"

    required_paths = [
        args.archive,
        args.app_bundle,
        helper,
        widget,
        privacy_manifest,
        widget_privacy_manifest,
        args.mcp_config,
        args.platform_manifest,
    ]
    missing = [str(path) for path in required_paths if not path.exists()]
    if missing:
        raise SystemExit(f"missing release artifact(s): {missing}")

    manifest = {
        "app": {
            "name": metadata["APP_NAME"],
            "display_name": metadata["APP_DISPLAY_NAME"],
            "bundle_id": metadata["BUNDLE_ID"],
            "version": metadata["MARKETING_VERSION"],
            "build": metadata["BUILD_VERSION"],
            "minimum_macos": metadata["MIN_SYSTEM_VERSION"],
            "url_scheme": metadata["URL_SCHEME"],
        },
        "archive": {
            "path": str(args.archive),
            "size_bytes": args.archive.stat().st_size,
            "sha256": sha256(args.archive),
        },
        "bundle": {
            "path": str(args.app_bundle),
            "helper": str(helper),
            "widget_extension": str(widget),
            "privacy_manifest": str(privacy_manifest),
            "widget_privacy_manifest": str(widget_privacy_manifest),
        },
        "mcp": {
            "server_name": metadata["MCP_SERVER_NAME"],
            "host_product": metadata["MCP_HOST_PRODUCT"],
            "client_config": str(args.mcp_config),
            "tool_count": len(EXPECTED_MCP_TOOLS),
            "expected_tools_source": str(ROOT / "script" / "expected_mcp_tools.py"),
            "catalog_verifier": str(ROOT / "script" / "verify_mcp_tool_catalog.py"),
            "client_config_generator": str(ROOT / "script" / "generate_mcp_client_config.py"),
            "client_config_verifier": str(ROOT / "script" / "verify_mcp_client_config.py"),
            "client_config_test_glob": "script/test_*.py",
            "database_environment_keys": [
                "LORVEX_APPLE_DB_PATH",
            ],
        },
        "integrations": {
            "app_group": metadata["APP_GROUP_ID"],
            "cloudkit_container": metadata["CLOUDKIT_CONTAINER_ID"],
            "cloudkit_sync_readiness": CLOUDKIT_SYNC_READINESS,
            "cloudkit_production_release_readiness": CLOUDKIT_PRODUCTION_RELEASE_READINESS,
            "system_intents_product": SYSTEM_INTENTS_PRODUCT,
            "system_intents_actions": SYSTEM_INTENTS_ACTIONS,
            "system_intents_capabilities": SYSTEM_INTENTS_CAPABILITIES,
            "widget_bundle_id": metadata["WIDGET_BUNDLE_ID"],
            "widget_kind": metadata["WIDGET_KIND"],
            "control_widget_kind": metadata["CONTROL_WIDGET_KIND"],
            "control_widget_display_name": metadata["CONTROL_WIDGET_DISPLAY_NAME"],
            "control_widget_description": metadata["CONTROL_WIDGET_DESCRIPTION"],
        },
        "apple_platforms": {
            "manifest": str(args.platform_manifest),
            "manifest_verifier": str(ROOT / "script" / "verify_apple_platform_manifest.py"),
            "xcodegen_project_verifier": str(ROOT / "script" / "verify_xcodegen_project.sh"),
        },
        "quality_gates": quality_gate_manifest(ROOT),
        "strategy": APPLE_RELEASE_STRATEGY,
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(f"Release manifest written: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
