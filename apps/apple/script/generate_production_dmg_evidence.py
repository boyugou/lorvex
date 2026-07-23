#!/usr/bin/env python3
"""Write the digest and machine-readable evidence for the final DMG."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
from datetime import UTC, datetime
from pathlib import Path

from metadata_env import load_metadata


REQUIRED_EVIDENCE_FILES = {
    "app-codesign.txt",
    "app-gatekeeper.txt",
    "app-notary-log.json",
    "app-notary-submit.json",
    "app-provisioning-profile.plist",
    "app-signed-entitlements.plist",
    "architectures.txt",
    "dmg-codesign.txt",
    "dmg-attach.plist",
    "dmg-gatekeeper.txt",
    "dmg-imageinfo.plist",
    "dmg-notary-log.json",
    "dmg-notary-submit.json",
    "final-app-group-reset.json",
    "helper-codesign.txt",
    "hdiutil-verify.txt",
    "helper-provisioning-profile.plist",
    "helper-signed-entitlements.plist",
    "installed-app-codesign.txt",
    "installed-app-clean-derived-state.json",
    "installed-app-content-identity.json",
    "installed-app-gatekeeper.txt",
    "installed-app-group-reset.json",
    "installed-app-launchservices.txt",
    "installed-app-provisioning-profile.plist",
    "installed-app-process-paths.txt",
    "installed-app-runtime-procinfo.txt",
    "installed-app-runtime.json",
    "installed-app-signed-entitlements.plist",
    "installed-app-verification.txt",
    "installed-widget-pluginkit.txt",
    "mcp-production-app-group-smoke.txt",
    "mounted-app-gatekeeper.txt",
    "mounted-app-verification.txt",
    "pre-notary-app-verification.txt",
    "schema-freeze.txt",
    "stapled-app-verification.txt",
    "widget-codesign.txt",
    "widget-provisioning-profile.plist",
    "widget-signed-entitlements.plist",
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def exclusive_text(path: Path, text: str) -> None:
    """Create one immutable release output without replacing an existing file."""
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
    with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
        stream.write(text)
        stream.flush()
        os.fsync(stream.fileno())
    directory_descriptor = os.open(path.parent, os.O_RDONLY)
    try:
        os.fsync(directory_descriptor)
    finally:
        os.close(directory_descriptor)


def git_commit(root: Path) -> str:
    result = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=root,
        capture_output=True,
        text=True,
        check=False,
    )
    return result.stdout.strip() if result.returncode == 0 else "unknown"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dmg", required=True, type=Path)
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--evidence-dir", required=True, type=Path)
    parser.add_argument("--team-id", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.dmg.is_file():
        raise SystemExit(f"DMG not found: {args.dmg}")
    if not args.app.is_dir():
        raise SystemExit(f"app bundle not found: {args.app}")

    metadata = load_metadata()
    expected_dmg_name = (
        f"{metadata['APP_NAME']}-macOS-{metadata['MARKETING_VERSION']}+"
        f"{metadata['BUILD_VERSION']}-arm64.dmg"
    )
    if args.dmg.name != expected_dmg_name:
        raise SystemExit(
            f"production DMG filename mismatch: {args.dmg.name!r} != "
            f"{expected_dmg_name!r}"
        )
    expected_app_name = f"{metadata['APP_NAME']}.app"
    if args.app.name != expected_app_name:
        raise SystemExit(
            f"production app bundle name mismatch: {args.app.name!r} != "
            f"{expected_app_name!r}"
        )
    missing_evidence = sorted(
        name
        for name in REQUIRED_EVIDENCE_FILES
        if not (args.evidence_dir / name).is_file()
    )
    if missing_evidence:
        raise SystemExit(f"required release evidence is missing: {missing_evidence!r}")

    content_identity = json.loads(
        (args.evidence_dir / "installed-app-content-identity.json").read_text(
            encoding="utf-8"
        )
    )
    if (
        content_identity.get("algorithm") != "sha256-tree-v1"
        or content_identity.get("mountedDigest")
        != content_identity.get("installedDigest")
        or not content_identity.get("installedDigest")
        or content_identity.get("installedApp") != str(args.app)
        or not content_identity.get("mountedApp")
    ):
        raise SystemExit("installed-app content identity does not prove exact equality")

    runtime = json.loads(
        (args.evidence_dir / "installed-app-runtime.json").read_text(encoding="utf-8")
    )
    initial_reset = json.loads(
        (args.evidence_dir / "installed-app-group-reset.json").read_text(
            encoding="utf-8"
        )
    )
    final_reset = json.loads(
        (args.evidence_dir / "final-app-group-reset.json").read_text(encoding="utf-8")
    )
    mcp_host_product = metadata["MCP_HOST_PRODUCT"]
    expected_helper = (
        args.app
        / "Contents"
        / "Helpers"
        / f"{mcp_host_product}.app"
        / "Contents"
        / "MacOS"
        / mcp_host_product
    )
    expected_database = (
        Path.home()
        / "Library"
        / "Group Containers"
        / metadata["APP_GROUP_ID"]
        / "Lorvex"
        / "db.sqlite"
    )
    expected_private_state = (
        Path.home()
        / "Library"
        / "Containers"
        / metadata["BUNDLE_ID"]
        / "Data"
        / "Library"
        / "Application Support"
        / metadata["APP_PRODUCT_NAME"]
    )
    reset_times: list[datetime] = []
    for label, reset in (
        ("initial", initial_reset),
        ("final", final_reset),
    ):
        if (
            reset.get("appGroupIdentifier") != metadata["APP_GROUP_ID"]
            or reset.get("backupCreated") is not False
            or reset.get("priorDataRestored") is not False
            or reset.get("destructive") is not True
            or reset.get("databaseAbsentAfterReset") is not True
            or reset.get("defaultsDomainsCleared")
            != [metadata["BUNDLE_ID"], metadata["APP_GROUP_ID"]]
            or not isinstance(reset.get("generation"), int)
            or isinstance(reset.get("generation"), bool)
            or reset["generation"] <= 0
        ):
            raise SystemExit(f"{label} production App Group reset evidence is invalid")
        if reset.get("helperBinary") != str(expected_helper):
            raise SystemExit(
                f"{label} production App Group reset used the wrong installed helper"
            )
        reset_at = reset.get("resetAt")
        if reset.get("databasePath") != str(expected_database) or not isinstance(
            reset_at, str
        ):
            raise SystemExit(
                f"{label} production App Group reset evidence names the wrong store"
            )
        if reset.get("privateStatePathCleared") != str(expected_private_state):
            raise SystemExit(
                f"{label} production reset did not clear the app's private sync state"
            )
        try:
            parsed_reset_at = datetime.fromisoformat(reset_at.replace("Z", "+00:00"))
        except ValueError as error:
            raise SystemExit(
                f"{label} production App Group reset timestamp is invalid"
            ) from error
        if parsed_reset_at.tzinfo is None:
            raise SystemExit(f"{label} production App Group reset timestamp has no zone")
        reset_times.append(parsed_reset_at)
    if final_reset["generation"] <= initial_reset["generation"]:
        raise SystemExit("final production reset did not advance the storage generation")

    smoke_output = (
        args.evidence_dir / "mcp-production-app-group-smoke.txt"
    ).read_text(encoding="utf-8")
    for required_line in (
        "PASS: smoke database starts with no tasks",
        "PASS: removed MCP smoke data from the real Lorvex App Group",
        "prior data was not restored",
        "MCP stdio smoke passed (swift core)",
    ):
        if required_line not in smoke_output:
            raise SystemExit(
                f"production MCP smoke evidence is missing: {required_line!r}"
            )
    if runtime.get("app") != str(args.app):
        raise SystemExit(
            "installed-app runtime evidence names a different app: "
            f"{runtime.get('app')!r} != {str(args.app)!r}"
        )
    if not isinstance(runtime.get("pid"), int) or runtime["pid"] <= 0:
        raise SystemExit("installed-app runtime evidence has no valid launch PID")
    stable_seconds = runtime.get("coldLaunchStableSeconds")
    if not isinstance(stable_seconds, (int, float)) or stable_seconds < 3:
        raise SystemExit("installed-app runtime evidence has no cold-launch stability proof")
    expected_executable = args.app / "Contents" / "MacOS" / metadata["APP_NAME"]
    if runtime.get("executable") != str(expected_executable):
        raise SystemExit("installed-app runtime evidence names the wrong executable")
    expected_launch_command = ["/usr/bin/open", "-F", "-n", str(args.app)]
    if runtime.get("launchCommand") != expected_launch_command:
        raise SystemExit(
            "installed-app runtime evidence did not use a fresh production launch"
        )
    if runtime.get("pluginIdentifier") != metadata["WIDGET_BUNDLE_ID"]:
        raise SystemExit("installed-app runtime evidence names the wrong widget identifier")
    expected_plugin = args.app / "Contents" / "PlugIns" / metadata["WIDGET_APPEX_NAME"]
    if runtime.get("pluginPath") != str(expected_plugin):
        raise SystemExit("installed-app runtime evidence names the wrong widget path")
    if not isinstance(runtime.get("procinfoSupported"), bool) or not isinstance(
        runtime.get("entitlementsValidated"), bool
    ):
        raise SystemExit("installed-app runtime evidence has invalid procinfo state")
    if runtime["procinfoSupported"] and not runtime["entitlementsValidated"]:
        raise SystemExit("supported procinfo evidence did not validate entitlements")
    if not runtime["procinfoSupported"] and runtime["entitlementsValidated"]:
        raise SystemExit("unsupported procinfo evidence cannot claim validated entitlements")
    runtime_verified_at = runtime.get("verifiedAt")
    if not isinstance(runtime_verified_at, str):
        raise SystemExit("installed-app runtime evidence has no verification timestamp")
    try:
        parsed_runtime_verified_at = datetime.fromisoformat(
            runtime_verified_at.replace("Z", "+00:00")
        )
    except ValueError as error:
        raise SystemExit("installed-app runtime verification timestamp is invalid") from error
    if parsed_runtime_verified_at.tzinfo is None:
        raise SystemExit("installed-app runtime verification timestamp has no zone")
    if not (reset_times[0] < reset_times[1] <= parsed_runtime_verified_at):
        raise SystemExit(
            "final installed-app runtime evidence was not captured after the final clean reset"
        )
    clean_derived = json.loads(
        (args.evidence_dir / "installed-app-clean-derived-state.json").read_text(
            encoding="utf-8"
        )
    )
    expected_snapshot = expected_database.parent / "widget_snapshot_v3.json"
    if (
        clean_derived.get("finalResetEvidence")
        != str(args.evidence_dir / "final-app-group-reset.json")
        or clean_derived.get("minimumStorageGeneration") != final_reset["generation"]
        or not isinstance(clean_derived.get("snapshotStorageGeneration"), int)
        or isinstance(clean_derived.get("snapshotStorageGeneration"), bool)
        or clean_derived["snapshotStorageGeneration"] != final_reset["generation"]
        or clean_derived.get("snapshotPath") != str(expected_snapshot)
        or clean_derived.get("smokeRowsPresent") is not False
        or clean_derived.get("databaseSmokeRowCounts")
        != {"habits": 0, "lists": 0, "tasks": 0}
    ):
        raise SystemExit("final clean-derived-state evidence is invalid")
    clean_verified_at = clean_derived.get("verifiedAt")
    if not isinstance(clean_verified_at, str):
        raise SystemExit("final clean-derived-state evidence has no timestamp")
    try:
        parsed_clean_verified_at = datetime.fromisoformat(
            clean_verified_at.replace("Z", "+00:00")
        )
    except ValueError as error:
        raise SystemExit("final clean-derived-state timestamp is invalid") from error
    if parsed_clean_verified_at.tzinfo is None or not (
        reset_times[1] <= parsed_clean_verified_at <= parsed_runtime_verified_at
    ):
        raise SystemExit("final clean-derived-state evidence has invalid chronology")
    for name in (
        "app-notary-submit.json",
        "app-notary-log.json",
        "dmg-notary-submit.json",
        "dmg-notary-log.json",
    ):
        payload = json.loads((args.evidence_dir / name).read_text(encoding="utf-8"))
        if payload.get("status") != "Accepted":
            raise SystemExit(f"release evidence {name} is not Accepted")

    digest = sha256_file(args.dmg)
    checksum_path = args.dmg.with_name(f"{args.dmg.name}.sha256")
    exclusive_text(checksum_path, f"{digest}  {args.dmg.name}\n")

    root = Path(__file__).resolve().parents[3]
    evidence_files = sorted(
        path.name for path in args.evidence_dir.iterdir() if path.is_file()
    )
    payload = {
        "artifact": {
            "filename": args.dmg.name,
            "sizeBytes": args.dmg.stat().st_size,
            "sha256": digest,
        },
        "app": {
            "bundleId": metadata["BUNDLE_ID"],
            "bundlePath": args.app.name,
            "coldLaunchStableSeconds": stable_seconds,
            "contentTreeSha256": content_identity["installedDigest"],
            "derivedStateSnapshotGeneration": clean_derived[
                "snapshotStorageGeneration"
            ],
            "destructiveAppGroupResetGeneration": final_reset["generation"],
            "installedPath": str(args.app),
            "minimumSystemVersion": metadata["MIN_SYSTEM_VERSION"],
            "procinfoSupported": runtime["procinfoSupported"],
        },
        "architecture": "arm64",
        "build": metadata["BUILD_VERSION"],
        "channel": "developer-id-notarized-dmg",
        "createdAt": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
        "evidenceFiles": evidence_files,
        "gitCommit": git_commit(root),
        "schemaFreezeRequired": True,
        "teamId": args.team_id,
        "version": metadata["MARKETING_VERSION"],
    }
    manifest_path = args.evidence_dir / "release-evidence.json"
    exclusive_text(
        manifest_path,
        json.dumps(payload, indent=2, sort_keys=True) + "\n",
    )
    print(f"Final DMG SHA-256: {digest}")
    print(f"Checksum: {checksum_path}")
    print(f"Release evidence: {manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
