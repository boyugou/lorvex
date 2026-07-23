"""Shared quality gate metadata for release and Apple platform manifests."""

from __future__ import annotations

import os
from pathlib import Path


QUALITY_GATE_VERIFIERS = {
    "app_metadata_verifier": "script/verify_app_metadata.py",
    "apple_strategy_verifier": "script/verify_apple_strategy.py",
    "build_matrix_verifier": "script/verify_build_matrix.py",
    "codesign_entitlements_verifier": "script/verify_codesign_entitlements.py",
    "cloudkit_sync_readiness_verifier": "script/verify_cloudkit_sync_readiness.py",
    "core_service_coverage_verifier": "script/verify_core_service_coverage.py",
    "hotspot_verifier": "script/verify_hotspots.py",
    "localization_catalog_verifier": "script/verify_localization_catalog.py",
    "macho_distribution_verifier": "script/verify_macho_distribution.py",
    "mcp_client_config_verifier": "script/verify_mcp_client_config.py",
    "mcp_stdio_smoke_verifier": "script/mcp_stdio_smoke.py",
    "mcp_tool_catalog_verifier": "script/verify_mcp_tool_catalog.py",
    "mcp_tool_manifest_verifier": "script/verify_mcp_tool_manifest.py",
    "release_manifest_verifier": "script/verify_release_manifest.py",
    "repo_hygiene_verifier": "script/verify_repo_hygiene.py",
    "system_entrypoint_verifier": "script/verify_system_entrypoints.py",
    "user_docs_verifier": "script/verify_user_docs.py",
}


def quality_gate_manifest(root: Path) -> dict[str, str]:
    return {
        key: str(root / relative_path)
        for key, relative_path in QUALITY_GATE_VERIFIERS.items()
    }


def verifier_path_failures(
    root: Path,
    value: object,
    expected: str,
    label: str,
) -> list[str]:
    expected_path = root / expected
    try:
        actual_path = Path(str(value))
    except TypeError:
        return [f"{label} path mismatch: {value!r}"]
    if not actual_path.is_absolute():
        actual_path = root / actual_path
    if actual_path.resolve() != expected_path.resolve():
        return [f"{label} path mismatch: {value!r}"]
    if not actual_path.is_file():
        return [f"{label} missing: {actual_path}"]
    if not os.access(actual_path, os.X_OK):
        return [f"{label} is not executable: {actual_path}"]
    return []


def quality_gate_failures(root: Path, manifest_value: object) -> list[str]:
    if not isinstance(manifest_value, dict):
        return [f"quality_gates mismatch: {manifest_value!r}"]

    failures: list[str] = []
    unexpected_keys = sorted(set(manifest_value) - set(QUALITY_GATE_VERIFIERS))
    if unexpected_keys:
        failures.append(f"quality_gates contains unexpected key(s): {unexpected_keys}")
    for key, relative_path in QUALITY_GATE_VERIFIERS.items():
        label = key.replace("_", " ")
        if key not in manifest_value:
            failures.append(f"{label} missing from quality_gates")
            continue
        failures.extend(verifier_path_failures(root, manifest_value.get(key), relative_path, label))
    return failures
