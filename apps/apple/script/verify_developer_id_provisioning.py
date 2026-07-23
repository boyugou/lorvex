#!/usr/bin/env python3
"""Verify the final Developer ID app, profiles, and signed identifiers.

The direct-distribution bundle uses restricted App Group, CloudKit, and push
entitlements.  Each participating process therefore carries its own embedded
Developer ID provisioning profile.  This verifier treats the final signature
and decoded profile as the authority; checked-in entitlement plists are not
release evidence.
"""

from __future__ import annotations

import argparse
import os
import plistlib
import re
import subprocess
import sys
from pathlib import Path

from metadata_env import load_metadata
from prepare_profile_entitlements import (
    APPLICATION_IDENTIFIER_KEY,
    TEAM_IDENTIFIER_KEY,
    decode_profile,
    profile_application_identifier,
    profile_identity_failures,
    profile_team_identifier,
)
from verify_codesign_entitlements import codesign_details, signed_entitlements
from verify_mas_provisioning import (
    EMBEDDED_PROFILE_NAME,
    MACOS_PROFILE_PLATFORMS,
    certificate_subjects,
    embeddable_targets,
    profile_app_group_failures,
    profile_aps_environment_failures,
    profile_bundle_identifier_failures,
    profile_expiry_failures,
    profile_icloud_container_failures,
    profile_icloud_environment_failures,
    profile_type_failures,
    structural_failures,
)


def developer_id_code_paths(app_bundle: Path) -> list[Path]:
    """Every bundle or nested executable whose signature ships in the DMG."""
    paths: set[Path] = {app_bundle}
    macos = app_bundle / "Contents" / "MacOS"
    if macos.is_dir():
        paths.update(path for path in macos.rglob("*") if path.is_file())

    frameworks = app_bundle / "Contents" / "Frameworks"
    if frameworks.is_dir():
        paths.update(
            path
            for path in frameworks.rglob("*")
            if path.is_file() and (path.suffix == ".dylib" or os.access(path, os.X_OK))
        )

    for container, suffix in (("Helpers", ".app"), ("PlugIns", ".appex")):
        root = app_bundle / "Contents" / container
        if not root.is_dir():
            continue
        for bundle in root.glob(f"*{suffix}"):
            if not bundle.is_dir():
                continue
            paths.add(bundle)
            contents_macos = bundle / "Contents" / "MacOS"
            if contents_macos.is_dir():
                paths.update(
                    path for path in contents_macos.rglob("*") if path.is_file()
                )
    return sorted(paths, key=str)


def developer_id_certificate_failures(label: str, subjects: list[str]) -> list[str]:
    if not subjects:
        return [
            f"{label} profile has no decodable signing certificate; "
            "Developer ID Application authorization is unproven"
        ]
    failures: list[str] = []
    for subject in subjects:
        if "Developer ID Application:" not in subject:
            failures.append(
                f"{label} profile certificate is not Developer ID Application: "
                f"{subject!r}"
            )
    return failures


def signed_identifier_failures(
    label: str,
    signed: dict,
    profile: dict,
    expected_bundle_id: str,
    expected_team_id: str,
) -> list[str]:
    failures: list[str] = []
    signed_app_id = signed.get(APPLICATION_IDENTIFIER_KEY)
    profile_app_id = profile_application_identifier(profile)
    if signed_app_id != profile_app_id:
        failures.append(
            f"{label} signed application identifier {signed_app_id!r} does not "
            f"match embedded profile {profile_app_id!r}"
        )

    signed_team = signed.get(TEAM_IDENTIFIER_KEY)
    profile_team = profile_team_identifier(profile)
    if signed_team != expected_team_id:
        failures.append(
            f"{label} signed team identifier {signed_team!r} does not match "
            f"{expected_team_id!r}"
        )
    if signed_team != profile_team:
        failures.append(
            f"{label} signed team identifier {signed_team!r} does not match "
            f"embedded profile {profile_team!r}"
        )
    return failures


def developer_id_signature_failures(
    label: str, details: str, expected_team_id: str
) -> list[str]:
    failures: list[str] = []
    if re.search(r"^Signature=adhoc$", details, flags=re.MULTILINE):
        failures.append(f"{label} is ad-hoc signed")
    if not re.search(
        r"^Authority=Developer ID Application:", details, flags=re.MULTILINE
    ):
        failures.append(f"{label} is not signed by Developer ID Application")
    if not re.search(
        rf"^TeamIdentifier={re.escape(expected_team_id)}$",
        details,
        flags=re.MULTILINE,
    ):
        failures.append(
            f"{label} signature does not carry TeamIdentifier={expected_team_id}"
        )
    timestamp_match = re.search(r"^Timestamp=(.*)$", details, flags=re.MULTILINE)
    if timestamp_match is None or timestamp_match.group(1).strip().lower() in {
        "",
        "none",
    }:
        failures.append(f"{label} signature has no secure timestamp")
    flags_match = re.search(r"(?:^|\s)flags=([^\s]+)", details, flags=re.MULTILINE)
    if flags_match is None or "runtime" not in flags_match.group(1):
        failures.append(f"{label} signature does not enable hardened runtime")
    return failures


def profile_contract_failures(
    label: str,
    profile: dict,
    signed: dict,
    expected_bundle_id: str,
    expected_team_id: str,
    *,
    cert_subjects: list[str] | None = None,
) -> list[str]:
    failures: list[str] = []
    failures.extend(
        profile_identity_failures(profile, expected_bundle_id, expected_team_id)
    )
    failures.extend(
        profile_bundle_identifier_failures(label, profile, expected_bundle_id)
    )
    failures.extend(profile_app_group_failures(label, profile, signed))
    failures.extend(profile_icloud_container_failures(label, profile, signed))
    failures.extend(profile_aps_environment_failures(label, profile, signed))
    failures.extend(profile_icloud_environment_failures(label, profile, signed))
    failures.extend(profile_type_failures(label, profile))
    platforms = profile.get("Platform")
    if not isinstance(platforms, list) or not MACOS_PROFILE_PLATFORMS.intersection(
        platforms
    ):
        failures.append(
            f"{label} profile does not explicitly identify the macOS platform"
        )
    if "ExpirationDate" not in profile:
        failures.append(f"{label} profile has no ExpirationDate")
    failures.extend(profile_expiry_failures(label, profile))
    required_services = signed.get("com.apple.developer.icloud-services", [])
    profile_entitlements = profile.get("Entitlements", {})
    if not isinstance(profile_entitlements, dict):
        profile_entitlements = {}
    profile_services = profile_entitlements.get(
        "com.apple.developer.icloud-services", []
    )
    missing_services = [
        service for service in required_services if service not in profile_services
    ]
    if missing_services:
        failures.append(
            f"{label} profile is missing iCloud service(s) {missing_services!r}: "
            f"profile authorizes {profile_services!r}"
        )
    failures.extend(
        developer_id_certificate_failures(
            label,
            certificate_subjects(profile) if cert_subjects is None else cert_subjects,
        )
    )
    failures.extend(
        signed_identifier_failures(
            label, signed, profile, expected_bundle_id, expected_team_id
        )
    )
    return failures


def bundle_metadata_failures(
    label: str,
    info: dict,
    expected_bundle_id: str,
    expected_version: str,
    expected_build: str,
) -> list[str]:
    failures: list[str] = []
    expected = {
        "CFBundleIdentifier": expected_bundle_id,
        "CFBundleShortVersionString": expected_version,
        "CFBundleVersion": expected_build,
    }
    for key, expected_value in expected.items():
        actual = info.get(key)
        if str(actual) != str(expected_value):
            failures.append(
                f"{label} {key} {actual!r} does not match {expected_value!r}"
            )
    return failures


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Verify final Developer ID profiles and signed entitlements."
    )
    parser.add_argument("app_bundle", type=Path)
    parser.add_argument("--expected-team-id", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.app_bundle.is_dir():
        print(f"app bundle not found: {args.app_bundle}", file=sys.stderr)
        return 2

    metadata = load_metadata()
    failures = structural_failures(args.app_bundle, metadata)
    profile_teams: dict[str, str] = {}

    for code_path in developer_id_code_paths(args.app_bundle):
        verification = subprocess.run(
            ["codesign", "--verify", "--strict", "--verbose=2", str(code_path)],
            capture_output=True,
            text=True,
        )
        if verification.returncode != 0:
            failures.append(
                f"signature verification failed for {code_path}: "
                f"{verification.stderr.strip()}"
            )
        failures.extend(
            developer_id_signature_failures(
                str(code_path), codesign_details(code_path), args.expected_team_id
            )
        )

    for label, bundle_path, bundle_id_key in embeddable_targets(
        args.app_bundle, metadata
    ):
        if not bundle_path.is_dir():
            failures.append(f"{label} bundle is missing: {bundle_path}")
            continue
        expected_bundle_id = metadata.get(bundle_id_key, "")
        info_path = bundle_path / "Contents" / "Info.plist"
        try:
            with info_path.open("rb") as stream:
                info = plistlib.load(stream)
        except (OSError, plistlib.InvalidFileException) as error:
            failures.append(f"{label} Info.plist could not be read: {error}")
        else:
            if not isinstance(info, dict):
                failures.append(f"{label} Info.plist is not a dictionary")
            else:
                failures.extend(
                    bundle_metadata_failures(
                        label,
                        info,
                        expected_bundle_id,
                        metadata.get("MARKETING_VERSION", ""),
                        metadata.get("BUILD_VERSION", ""),
                    )
                )
        profile_path = bundle_path / "Contents" / EMBEDDED_PROFILE_NAME
        if not profile_path.is_file():
            failures.append(
                f"{label} is missing required Developer ID provisioning profile: "
                f"{profile_path}"
            )
            continue
        try:
            profile = decode_profile(profile_path)
            signed = signed_entitlements(bundle_path)
        except (OSError, ValueError, subprocess.CalledProcessError) as error:
            failures.append(f"{label} profile/signature could not be decoded: {error}")
            continue

        failures.extend(
            profile_contract_failures(
                label,
                profile,
                signed,
                expected_bundle_id,
                args.expected_team_id,
            )
        )
        team = profile_team_identifier(profile)
        if team:
            profile_teams[label] = team

    if set(profile_teams.values()) not in ({args.expected_team_id}, set()):
        failures.append(
            "Developer ID provisioning profiles disagree on team: "
            f"{dict(sorted(profile_teams.items()))!r}"
        )

    if failures:
        for failure in failures:
            print(failure, file=sys.stderr)
        return 1

    print(
        "Developer ID provisioning/signature verification passed: "
        f"{args.app_bundle} (team {args.expected_team_id})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
