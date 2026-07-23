#!/usr/bin/env python3
"""Create profile-aware macOS entitlements for manual codesigning.

Xcode normally synthesizes the application and team identifiers from the
selected provisioning profile.  Lorvex's direct-distribution path assembles a
SwiftPM bundle manually, so it must add those identifiers explicitly before
calling ``codesign``.  The final signed bundle and embedded profile are still
verified independently by ``verify_developer_id_provisioning.py``.
"""

from __future__ import annotations

import argparse
import os
import plistlib
import subprocess
import sys
import tempfile
from pathlib import Path


APPLICATION_IDENTIFIER_KEY = "com.apple.application-identifier"
TEAM_IDENTIFIER_KEY = "com.apple.developer.team-identifier"


def decode_profile(profile_path: Path) -> dict:
    output = subprocess.check_output(
        ["security", "cms", "-D", "-i", str(profile_path)],
        stderr=subprocess.DEVNULL,
    )
    payload = plistlib.loads(output)
    if not isinstance(payload, dict):
        raise ValueError("decoded provisioning profile is not a dictionary")
    return payload


def profile_application_identifier(profile: dict) -> str:
    entitlements = profile.get("Entitlements", {})
    if not isinstance(entitlements, dict):
        return ""
    value = entitlements.get(APPLICATION_IDENTIFIER_KEY, "")
    return value if isinstance(value, str) else ""


def profile_team_identifier(profile: dict) -> str:
    entitlements = profile.get("Entitlements", {})
    if isinstance(entitlements, dict):
        value = entitlements.get(TEAM_IDENTIFIER_KEY, "")
        if isinstance(value, str) and value:
            return value
    teams = profile.get("TeamIdentifier", [])
    if isinstance(teams, list) and len(teams) == 1 and isinstance(teams[0], str):
        return teams[0]
    return ""


def profile_identity_failures(
    profile: dict, expected_bundle_id: str, expected_team_id: str
) -> list[str]:
    failures: list[str] = []
    entitlements = profile.get("Entitlements", {})
    if not isinstance(entitlements, dict):
        entitlements = {}
    app_id = profile_application_identifier(profile)
    prefix, separator, suffix = app_id.partition(".")
    if not separator or not prefix or suffix != expected_bundle_id:
        failures.append(
            f"profile application identifier {app_id!r} does not authorize "
            f"bundle id {expected_bundle_id!r}"
        )

    prefixes = profile.get("ApplicationIdentifierPrefix")
    if not isinstance(prefixes, list) or prefix not in prefixes:
        failures.append(
            f"profile ApplicationIdentifierPrefix {prefixes!r} does not "
            f"authorize application identifier prefix {prefix!r}"
        )

    team_id = profile_team_identifier(profile)
    if team_id != expected_team_id:
        failures.append(
            f"profile team identifier {team_id!r} does not match "
            f"{expected_team_id!r}"
        )
    entitlement_team = entitlements.get(TEAM_IDENTIFIER_KEY)
    if entitlement_team != expected_team_id:
        failures.append(
            f"profile entitlement team identifier {entitlement_team!r} does not "
            f"match {expected_team_id!r}"
        )
    top_level_teams = profile.get("TeamIdentifier")
    if top_level_teams != [expected_team_id]:
        failures.append(
            f"profile TeamIdentifier {top_level_teams!r} does not match "
            f"[{expected_team_id!r}]"
        )

    if profile.get("ProvisionsAllDevices") is not True:
        failures.append(
            "profile is not a Developer ID distribution profile "
            "(ProvisionsAllDevices is not true)"
        )
    if "ProvisionedDevices" in profile:
        failures.append(
            "profile is device-limited (declares ProvisionedDevices), not "
            "Developer ID distribution"
        )
    if entitlements.get("get-task-allow") is True:
        failures.append("profile enables get-task-allow")
    return failures


def merged_entitlements(
    base: dict, profile: dict, expected_bundle_id: str, expected_team_id: str
) -> dict:
    failures = profile_identity_failures(
        profile, expected_bundle_id, expected_team_id
    )
    if failures:
        raise ValueError("; ".join(failures))
    if not isinstance(base, dict):
        raise ValueError("base entitlements plist is not a dictionary")

    result = dict(base)
    result[APPLICATION_IDENTIFIER_KEY] = profile_application_identifier(profile)
    result[TEAM_IDENTIFIER_KEY] = profile_team_identifier(profile)
    return result


def write_plist_atomically(payload: dict, output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{output_path.name}.", dir=output_path.parent
    )
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            plistlib.dump(payload, stream, fmt=plistlib.FMT_XML, sort_keys=True)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary_path, output_path)
    finally:
        temporary_path.unlink(missing_ok=True)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Merge profile-derived identifiers into macOS entitlements."
    )
    parser.add_argument("--base", required=True, type=Path)
    parser.add_argument("--profile", required=True, type=Path)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--team-id", required=True)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        with args.base.open("rb") as stream:
            base = plistlib.load(stream)
        profile = decode_profile(args.profile)
        payload = merged_entitlements(
            base, profile, args.bundle_id, args.team_id
        )
        write_plist_atomically(payload, args.output)
    except (OSError, ValueError, plistlib.InvalidFileException, subprocess.CalledProcessError) as error:
        print(f"profile-aware entitlement preparation failed: {error}", file=sys.stderr)
        return 1
    print(f"Profile-aware entitlements written: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
