#!/usr/bin/env python3
"""Verify embedded distribution provisioning profiles on a MAS-staged app bundle.

Run against the bundle produced by ``script/archive_mas.sh --package`` (or any
signed ``.app`` — the checks are inert when a target has no profile). For each
of the three embeddable targets — the macOS app, the MCP helper bundled app,
and the Focus widget ``.appex`` — this script looks for
``Contents/embedded.provisionprofile``:

* Present: decode it with ``security cms -D -i`` (no network, no Apple
  account — this only parses the already-signed local blob) and cross-check
  its ``Entitlements`` against the target's own signed entitlements and
  ``CFBundleIdentifier``. Any mismatch (bundle id, missing App Group, missing
  iCloud container, wrong ``com.apple.developer.aps-environment``, or an
  ``com.apple.developer.icloud-container-environment`` that does not authorize
  the target's required environment) is a hard failure. The profile must also
  be an App Store distribution profile, not a development, ad-hoc, enterprise,
  or Developer ID one: a ``ProvisionedDevices`` list or a truthy
  ``get-task-allow`` marks a development profile, and a truthy
  ``ProvisionsAllDevices`` marks a Developer ID / enterprise ("provisions all
  devices") profile — either one hard-fails. Where the profile's
  ``DeveloperCertificates`` can be decoded, the signing certificate class is
  cross-checked as well: a ``Developer ID`` application/installer certificate
  hard-fails, since an App Store distribution profile is signed with an
  ``Apple Distribution`` / ``3rd Party Mac Developer Application`` certificate.
  All three embeddable targets are native
  macOS bundles, so the bundle identifier is read from the profile's
  ``com.apple.application-identifier`` entitlement (macOS profiles), falling
  back to the bare ``application-identifier`` key used by iOS-family profiles
  for robustness against a profile downloaded for the wrong platform. Where the
  decoded profile carries the data, this script also checks the profile is a
  macOS (``Platform`` includes ``OSX``) distribution profile, is not expired,
  and — across all embedded profiles in the same package — declares a
  consistent ``TeamIdentifier``. Any of these fields absent from a given
  profile is soft-skipped, matching the absent-profile convention below.
* Absent: printed as a NOTE and skipped — this is the normal state for a
  local/dev build, since profile embedding is optional (see
  ``sign_app_bundle.sh``). ``script/archive_mas.sh --package`` layers its own
  hard requirement that the app and MCP helper profiles are embedded before
  this script ever runs; that check exists there, not here, so this script
  stays usable to lint an already-packaged bundle from a dev build where the
  soft-skip is expected.

Independent of profile presence, this script always asserts the MAS
structural invariants that need no Apple credentials: the MCP helper is a
bundled ``.app`` with its own ``Info.plist`` (not a bare Mach-O), every
Mach-O executable in the bundle carries a non-empty entitlements plan, and
none of them lack the app-sandbox entitlement.
"""

from __future__ import annotations

import argparse
import plistlib
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

from metadata_env import load_metadata
from verify_codesign_entitlements import (
    macho_executable_files,
    non_sandboxed_executable_failures,
    signed_entitlements,
)


ROOT = Path(__file__).resolve().parents[1]
EMBEDDED_PROFILE_NAME = "embedded.provisionprofile"
MACOS_PROFILE_PLATFORMS = {"OSX", "macOS"}


def decode_provisioning_profile(profile_path: Path) -> dict:
    """Decode a signed ``.provisionprofile`` CMS blob into its plist payload.

    Uses the system ``security`` tool, which only parses the profile's own
    signature locally — no network access or Apple account is involved."""
    output = subprocess.check_output(["security", "cms", "-D", "-i", str(profile_path)])
    return plistlib.loads(output)


def profile_application_identifier(profile_plist: dict) -> str:
    """The provisioned app id, preferring the native macOS entitlement key.

    Native macOS provisioning profiles carry the app id under
    ``com.apple.application-identifier``; the bare ``application-identifier``
    key is the iOS-family convention. Every embeddable target this script
    checks (the macOS app, the MCP helper app bundle, and the WidgetKit
    ``.appex``) is a macOS bundle, so the native key is checked first — the
    bare key is only a fallback for a profile mistakenly downloaded for the
    wrong platform, so that case still reports a clear mismatch instead of
    always failing with an empty app id."""
    entitlements = profile_plist.get("Entitlements", {})
    return entitlements.get("com.apple.application-identifier") or entitlements.get(
        "application-identifier", ""
    )


def profile_bundle_identifier_failures(
    label: str, profile_plist: dict, expected_bundle_id: str
) -> list[str]:
    app_id = profile_application_identifier(profile_plist)
    if "." not in app_id:
        return [f"{label} profile application-identifier is malformed: {app_id!r}"]
    _, _, suffix = app_id.partition(".")
    if suffix != expected_bundle_id:
        return [
            f"{label} profile provisions bundle id {suffix!r}, "
            f"expected {expected_bundle_id!r}"
        ]
    return []


def profile_app_group_failures(
    label: str, profile_plist: dict, target_entitlements: dict
) -> list[str]:
    required_groups = target_entitlements.get("com.apple.security.application-groups", [])
    if not required_groups:
        return []
    profile_groups = profile_plist.get("Entitlements", {}).get(
        "com.apple.security.application-groups", []
    )
    missing = [group for group in required_groups if group not in profile_groups]
    if missing:
        return [
            f"{label} profile is missing App Group(s) {missing!r}: "
            f"profile authorizes {profile_groups!r}"
        ]
    return []


def profile_icloud_container_failures(
    label: str, profile_plist: dict, target_entitlements: dict
) -> list[str]:
    required_containers = target_entitlements.get(
        "com.apple.developer.icloud-container-identifiers", []
    )
    if not required_containers:
        return []
    profile_containers = profile_plist.get("Entitlements", {}).get(
        "com.apple.developer.icloud-container-identifiers", []
    )
    missing = [container for container in required_containers if container not in profile_containers]
    if missing:
        return [
            f"{label} profile is missing iCloud container(s) {missing!r}: "
            f"profile authorizes {profile_containers!r}"
        ]
    return []


def profile_aps_environment_failures(
    label: str, profile_plist: dict, target_entitlements: dict
) -> list[str]:
    required_aps = target_entitlements.get("com.apple.developer.aps-environment")
    if not required_aps:
        return []
    profile_aps = profile_plist.get("Entitlements", {}).get(
        "com.apple.developer.aps-environment"
    )
    if profile_aps != required_aps:
        return [
            f"{label} profile aps-environment {profile_aps!r} does not match "
            f"required {required_aps!r}"
        ]
    return []


def profile_icloud_environment_failures(
    label: str, profile_plist: dict, target_entitlements: dict
) -> list[str]:
    """A distribution profile bound for the App Store must authorize the same
    iCloud container environment the target's signed entitlement declares. The
    signed app entitlement is a scalar string (``Production``); a provisioning
    profile carries the environment as an array (``["Production"]`` for a
    distribution profile, ``["Development"]`` for a development one), so a
    development profile that would otherwise pass the platform check is caught
    here. When the target declares no environment there is nothing to
    cross-check."""
    required = target_entitlements.get("com.apple.developer.icloud-container-environment")
    if not required:
        return []
    profile_environments = profile_plist.get("Entitlements", {}).get(
        "com.apple.developer.icloud-container-environment", []
    )
    if isinstance(profile_environments, str):
        profile_environments = [profile_environments]
    if required not in profile_environments:
        return [
            f"{label} profile icloud-container-environment {profile_environments!r} "
            f"does not authorize required {required!r}"
        ]
    return []


def profile_distribution_type_failures(label: str, profile_plist: dict) -> list[str]:
    """Discriminate an App Store distribution profile from every other class.

    An App Store distribution profile carries none of the following markers;
    each identifies a distribution channel App Store Connect rejects for a MAS
    submission:

    * ``ProvisionedDevices`` — a development or ad-hoc profile limited to an
      enumerated UDID list.
    * ``get-task-allow`` true — a development profile that lets a debugger
      attach.
    * ``ProvisionsAllDevices`` true — a Developer ID or enterprise ("in-house")
      profile that provisions every device rather than an explicit App Store
      identity. This flag never appears on an App Store distribution profile,
      so its presence means a Developer ID / enterprise profile was packaged
      for submission."""
    failures: list[str] = []
    if "ProvisionedDevices" in profile_plist:
        failures.append(
            f"{label} profile is a development profile (declares ProvisionedDevices), "
            "not an App Store distribution profile"
        )
    if profile_plist.get("Entitlements", {}).get("get-task-allow"):
        failures.append(
            f"{label} profile is a development profile (get-task-allow is true), "
            "not an App Store distribution profile"
        )
    if profile_plist.get("ProvisionsAllDevices"):
        failures.append(
            f"{label} profile is a Developer ID / enterprise profile "
            "(ProvisionsAllDevices is true), not an App Store distribution profile"
        )
    return failures


DEVELOPER_ID_CERTIFICATE_MARKERS = (
    "Developer ID Application",
    "Developer ID Installer",
)


def certificate_subjects(profile_plist: dict) -> list[str]:
    """Subject lines of the profile's embedded ``DeveloperCertificates``.

    Each entry is a DER-encoded X.509 leaf certificate (the signing identity
    the profile authorizes). ``openssl x509`` parses it locally — no network,
    no Apple account. A certificate that cannot be parsed (or ``openssl``
    absent) is dropped, so the caller soft-skips when the class is
    indeterminable, matching the absent-field convention elsewhere in this
    module."""
    subjects: list[str] = []
    for der in profile_plist.get("DeveloperCertificates", []):
        if not isinstance(der, (bytes, bytearray)):
            continue
        try:
            output = subprocess.check_output(
                ["openssl", "x509", "-inform", "DER", "-noout", "-subject"],
                input=bytes(der),
                stderr=subprocess.DEVNULL,
            )
        except (subprocess.CalledProcessError, FileNotFoundError, OSError):
            continue
        subjects.append(output.decode("utf-8", "replace").strip())
    return subjects


def profile_certificate_class_failures(label: str, subjects: list[str]) -> list[str]:
    """Reject a profile whose signing certificate is a Developer ID identity.

    An App Store distribution profile is signed with an ``Apple Distribution``
    (or the legacy ``3rd Party Mac Developer Application``) certificate; a
    ``Developer ID Application`` / ``Developer ID Installer`` certificate belongs
    to direct/notarized distribution outside the store, which App Store Connect
    rejects. ``subjects`` empty (certificates absent or unparseable) is
    soft-skipped."""
    failures: list[str] = []
    for subject in subjects:
        if any(marker in subject for marker in DEVELOPER_ID_CERTIFICATE_MARKERS):
            failures.append(
                f"{label} profile is signed with a Developer ID certificate "
                f"({subject!r}), not an App Store distribution certificate"
            )
    return failures


def profile_type_failures(label: str, profile_plist: dict) -> list[str]:
    """Every embeddable target here is a native macOS bundle (the app, the
    MCP helper `.app`, the WidgetKit `.appex`), so a decoded profile's
    top-level ``Platform`` array — when present — must include an OS X
    identifier. Profiles from ``security cms -D -i`` omit ``Platform`` on
    some older exports, so its absence is soft-skipped rather than treated
    as a mismatch."""
    platforms = profile_plist.get("Platform")
    if not platforms:
        return []
    if not MACOS_PROFILE_PLATFORMS.intersection(platforms):
        return [f"{label} profile is not a macOS distribution profile: Platform={platforms!r}"]
    return []


def profile_expiry_failures(
    label: str, profile_plist: dict, *, now: datetime | None = None
) -> list[str]:
    """A provisioning profile past its ``ExpirationDate`` cannot produce an
    installable MAS package even though codesign accepts the signature at
    build time — App Store Connect rejects the upload. ``ExpirationDate``
    absent from the decoded plist is soft-skipped."""
    expiration = profile_plist.get("ExpirationDate")
    if expiration is None:
        return []
    now = now or datetime.now(timezone.utc)
    if expiration.tzinfo is None:
        expiration = expiration.replace(tzinfo=timezone.utc)
    if expiration <= now:
        return [f"{label} provisioning profile expired on {expiration.isoformat()}"]
    return []


def profile_team_identifier(profile_plist: dict) -> str | None:
    teams = profile_plist.get("TeamIdentifier")
    if not teams:
        return None
    return teams[0]


def profile_team_consistency_failures(team_by_label: dict[str, str]) -> list[str]:
    """The app, MCP helper, and widget extension are always packaged and
    submitted together, so every embedded profile that declares a
    ``TeamIdentifier`` must name the same Apple Developer team — a profile
    from a different team is a packaging mistake (e.g. a stale profile left
    over from another project), not a supported configuration. Targets with
    no profile, or a profile with no ``TeamIdentifier``, are absent from
    ``team_by_label`` and excluded from this check."""
    distinct_teams = sorted(set(team_by_label.values()))
    if len(distinct_teams) <= 1:
        return []
    return [
        "embedded provisioning profiles disagree on TeamIdentifier: "
        f"{dict(sorted(team_by_label.items()))!r}"
    ]


def profile_cross_check_failures(
    label: str,
    profile_plist: dict,
    target_entitlements: dict,
    expected_bundle_id: str,
    *,
    cert_subjects: list[str] | None = None,
) -> list[str]:
    """All profile↔entitlement cross-checks for one embeddable target.

    ``cert_subjects`` overrides the profile's decoded certificate subject lines
    (default: extract them from ``DeveloperCertificates`` via ``openssl``); a
    profile with no embedded certificates yields an empty list and soft-skips
    the certificate-class check, so this stays a pure function for callers that
    pass a synthetic profile."""
    failures: list[str] = []
    failures.extend(profile_bundle_identifier_failures(label, profile_plist, expected_bundle_id))
    failures.extend(profile_app_group_failures(label, profile_plist, target_entitlements))
    failures.extend(profile_icloud_container_failures(label, profile_plist, target_entitlements))
    failures.extend(profile_aps_environment_failures(label, profile_plist, target_entitlements))
    failures.extend(profile_icloud_environment_failures(label, profile_plist, target_entitlements))
    failures.extend(profile_type_failures(label, profile_plist))
    failures.extend(profile_distribution_type_failures(label, profile_plist))
    if cert_subjects is None:
        cert_subjects = certificate_subjects(profile_plist)
    failures.extend(profile_certificate_class_failures(label, cert_subjects))
    failures.extend(profile_expiry_failures(label, profile_plist))
    return failures


def entitlements_plan_coverage_failures(
    executables: list[Path],
    entitlements_by_path: dict[Path, dict],
) -> list[str]:
    """Every executable in a MAS staging must carry a non-empty entitlements
    plan (readable via ``codesign -d --entitlements``). An empty/unreadable
    entitlements dict is a distinct failure mode from "signed but not
    sandboxed" (see ``non_sandboxed_executable_failures``): it means the
    executable was never signed with any entitlements file at all, which can
    indicate it was skipped by the signing pipeline entirely."""
    failures: list[str] = []
    for path in executables:
        if not entitlements_by_path.get(path):
            failures.append(f"executable has no entitlements plan (unsigned or unreadable): {path}")
    return failures


def helper_bundle_structure_failures(app_bundle: Path, mcp_host_product: str) -> list[str]:
    """The MCP helper must ship as a bundled ``.app`` with its own
    ``Info.plist`` — a bare Mach-O has no Info.plist, so the sandbox cannot
    initialize a container for it."""
    if not mcp_host_product:
        return []
    helper_bundle = app_bundle / "Contents" / "Helpers" / f"{mcp_host_product}.app"
    if not helper_bundle.is_dir():
        return [f"MCP helper bundle is missing or not a directory: {helper_bundle}"]
    helper_info_plist = helper_bundle / "Contents" / "Info.plist"
    if not helper_info_plist.is_file():
        return [f"MCP helper bundle is missing Info.plist: {helper_info_plist}"]
    return []


def structural_failures(app_bundle: Path, metadata: dict[str, str]) -> list[str]:
    """MAS structural invariants that need no Apple credentials to check."""
    failures: list[str] = []
    failures.extend(
        helper_bundle_structure_failures(app_bundle, metadata.get("MCP_HOST_PRODUCT", ""))
    )

    executables = macho_executable_files(app_bundle)
    entitlements_by_path: dict[Path, dict] = {}
    for executable in executables:
        try:
            entitlements_by_path[executable] = signed_entitlements(executable)
        except subprocess.CalledProcessError:
            entitlements_by_path[executable] = {}

    failures.extend(entitlements_plan_coverage_failures(executables, entitlements_by_path))
    failures.extend(non_sandboxed_executable_failures(executables, entitlements_by_path))
    return failures


def embeddable_targets(
    app_bundle: Path, metadata: dict[str, str]
) -> list[tuple[str, Path, str]]:
    """(label, bundle path, app_metadata.sh bundle-id key) for every target
    that can carry its own embedded provisioning profile."""
    targets = [("macOS app", app_bundle, "BUNDLE_ID")]

    mcp_host_product = metadata.get("MCP_HOST_PRODUCT", "")
    if mcp_host_product:
        targets.append(
            (
                "MCP helper",
                app_bundle / "Contents" / "Helpers" / f"{mcp_host_product}.app",
                "MCP_HOST_BUNDLE_ID",
            )
        )

    widget_appex_name = metadata.get("WIDGET_APPEX_NAME", "")
    if widget_appex_name:
        targets.append(
            (
                "widget extension",
                app_bundle / "Contents" / "PlugIns" / widget_appex_name,
                "WIDGET_BUNDLE_ID",
            )
        )

    return targets


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Verify embedded MAS provisioning profiles against signed entitlements."
    )
    parser.add_argument("app_bundle", type=Path)
    args = parser.parse_args()

    app_bundle: Path = args.app_bundle
    if not app_bundle.is_dir():
        print(f"app bundle not found: {app_bundle}", file=sys.stderr)
        return 2

    metadata = load_metadata()
    failures: list[str] = []
    failures.extend(structural_failures(app_bundle, metadata))

    team_by_label: dict[str, str] = {}
    for label, bundle_path, bundle_id_key in embeddable_targets(app_bundle, metadata):
        if not bundle_path.is_dir():
            # Missing-bundle failures are reported by structural_failures /
            # verify_codesign_entitlements.py; nothing to cross-check here.
            continue

        profile_path = bundle_path / "Contents" / EMBEDDED_PROFILE_NAME
        if not profile_path.is_file():
            print(
                f"NOTE: {label} has no embedded provisioning profile (dev build) — "
                "skipping profile↔entitlement cross-check"
            )
            continue

        try:
            profile_plist = decode_provisioning_profile(profile_path)
        except subprocess.CalledProcessError as error:
            failures.append(
                f"{label} embedded provisioning profile could not be decoded: "
                f"{profile_path} ({error})"
            )
            continue

        try:
            target_entitlements = signed_entitlements(bundle_path)
        except subprocess.CalledProcessError as error:
            failures.append(
                f"{label} entitlements could not be read for profile cross-check: "
                f"{bundle_path} ({error})"
            )
            continue

        expected_bundle_id = metadata.get(bundle_id_key, "")
        failures.extend(
            profile_cross_check_failures(label, profile_plist, target_entitlements, expected_bundle_id)
        )

        team = profile_team_identifier(profile_plist)
        if team is not None:
            team_by_label[label] = team

    failures.extend(profile_team_consistency_failures(team_by_label))

    if failures:
        for failure in failures:
            print(failure, file=sys.stderr)
        return 1

    print(f"MAS provisioning-profile verification passed: {app_bundle}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
