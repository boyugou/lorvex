#!/usr/bin/env python3
"""Recursively verify a re-signed iOS/visionOS/watchOS export (the shipped IPA
payload).

``script/archive_ios.sh --export`` produces an ``.ipa`` for one of the platforms
it archives, and the expected bundle shape depends on that platform:

* iPhone (``LorvexMobileApp``): the host app, and nested inside it the Focus
  widget and Focus Filter extensions (``PlugIns/*.appex``), the embedded Watch app
  (``Watch/*.app``), and the Watch complication
  (``Watch/<app>.app/PlugIns/*.appex``).
* visionOS (``LorvexVisionApp``): the host app alone — it embeds no widget or
  Watch payload.
* watchOS (``LorvexWatchApp``, development export only — the watch app has no
  standalone App Store export): the Watch app host and its complication
  (``PlugIns/*.appex``).

The target platform is taken from ``--platform`` when given (``archive_ios.sh``
passes it), otherwise auto-detected from the payload's ``Info.plist``
``DTPlatformName``; an unrecognized/absent value falls back to the iPhone shape.
The bundle set asserted below is the one that platform actually ships, so a
visionOS export is no longer rejected by an iPhone-shaped expectation.

``verify_macho_closure.py`` proves the dynamic-link closure of that payload; this
proves the *distribution* integrity that closure verification cannot see. For
every executable bundle in the payload it asserts:

* a valid code signature (``codesign --verify --strict``, ``--deep`` so a broken
  nested signature is caught),
* a non-empty signed entitlements plan whose ``application-identifier`` resolves
  to the bundle's own ``CFBundleIdentifier`` (read via ``codesign -d
  --entitlements``),
* an embedded ``embedded.mobileprovision`` whose provisioned
  ``application-identifier`` and ``TeamIdentifier`` match the bundle — and agree
  across every nested bundle (one team, one app-id family); restricted
  capabilities in the signed entitlements (App Groups, iCloud, APNs) must also
  be authorized by that bundle's own profile,
* a ``PrivacyInfo.xcprivacy`` privacy manifest, and
* ``CFBundleShortVersionString`` / ``CFBundleVersion`` equal to the release
  metadata (``MARKETING_VERSION`` / ``BUILD_VERSION`` in ``app_metadata.sh``).

The full set of discovered bundle ids must equal the platform's release set, so a
dropped or stray nested bundle fails too.

The signature/profile/entitlement reads need a real signed artifact, so the
whole check is inert when none exists: pointed at a missing path it prints a
skip note and exits 0 (the runner has no signing credentials), exactly like the
packaging skips in ``verify_all.sh``; if ``codesign`` itself is unavailable it
exits 78, matching the verifier soft-skip convention. Development exports may
use device-limited or wildcard profiles. App Store Connect exports additionally
require a non-development, non-device-limited, unexpired, exact profile for
every bundle, including the independent Focus Filter extension.

Exit codes: 0 = payload verified (or nothing to verify); 1 = one or more
failures (listed on stderr); 2 = usage / malformed artifact; 78 = codesign
unavailable on this host (soft-skip).
"""

from __future__ import annotations

import argparse
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from metadata_env import load_metadata
from verify_codesign_entitlements import signed_entitlements
from verify_mas_provisioning import (
    profile_app_group_failures,
    profile_application_identifier,
    profile_distribution_type_failures,
    profile_expiry_failures,
    profile_icloud_container_failures,
    profile_icloud_environment_failures,
    profile_team_identifier,
)


EMBEDDED_PROFILE_NAME = "embedded.mobileprovision"
PRIVACY_MANIFEST_NAME = "PrivacyInfo.xcprivacy"


@dataclass(frozen=True)
class BundleRole:
    """A nesting slot in the exported IPA payload."""

    label: str


HOST_ROLE = BundleRole("host app")
WIDGET_ROLE = BundleRole("widget extension")
FOCUS_FILTER_ROLE = BundleRole("Focus filter extension")
WATCH_ROLE = BundleRole("Watch app")
COMPLICATION_ROLE = BundleRole("Watch complication")


@dataclass(frozen=True)
class Platform:
    """A target platform whose exported IPA payload has a known bundle shape.

    ``bundle_id_keys`` are the ``app_metadata.sh`` keys whose values form the
    exact set of executable-bundle ids the platform's IPA must contain: the
    iPhone build embeds a widget + Watch app + complication alongside its host,
    visionOS ships the host app alone, and a (development-only) standalone
    watchOS export is the Watch app host plus its complication.
    ``root_plugin_role`` labels a ``PlugIns/*.appex`` found directly under the
    payload host app — a widget on iPhone/visionOS, the complication on a
    standalone watch export — so failure messages name the bundle's real role.
    """

    key: str
    label: str
    bundle_id_keys: tuple[str, ...]
    root_plugin_role: BundleRole


IPHONE_PLATFORM = Platform(
    key="ios",
    label="iPhone",
    bundle_id_keys=(
        "MOBILE_BUNDLE_ID",
        "WIDGET_BUNDLE_ID",
        "FOCUS_FILTER_BUNDLE_ID",
        "WATCH_BUNDLE_ID",
        "WATCH_COMPLICATION_BUNDLE_ID",
    ),
    root_plugin_role=WIDGET_ROLE,
)
VISIONOS_PLATFORM = Platform(
    key="visionos",
    label="visionOS",
    bundle_id_keys=("VISION_BUNDLE_ID",),
    root_plugin_role=WIDGET_ROLE,
)
WATCHOS_PLATFORM = Platform(
    key="watchos",
    label="watchOS",
    bundle_id_keys=("WATCH_BUNDLE_ID", "WATCH_COMPLICATION_BUNDLE_ID"),
    root_plugin_role=COMPLICATION_ROLE,
)

PLATFORMS_BY_KEY = {
    platform.key: platform
    for platform in (IPHONE_PLATFORM, VISIONOS_PLATFORM, WATCHOS_PLATFORM)
}

# ``DTPlatformName`` values Xcode writes into a built app's Info.plist, mapped to
# the platform whose bundle set the payload must satisfy. visionOS is "xros".
_DT_PLATFORM_NAMES = {
    "iphoneos": IPHONE_PLATFORM,
    "xros": VISIONOS_PLATFORM,
    "visionos": VISIONOS_PLATFORM,
    "watchos": WATCHOS_PLATFORM,
}


def platform_for_payload(info: dict | None, override: str | None = None) -> Platform:
    """The :class:`Platform` whose release bundle set the payload must match.

    ``override`` (the ``--platform`` flag ``archive_ios.sh`` passes) wins when
    given and must name a known platform key. Otherwise the payload host app's
    ``Info.plist`` ``DTPlatformName`` selects it; an absent or unrecognized value
    falls back to :data:`IPHONE_PLATFORM`, preserving the historical iPhone shape
    for any artifact that predates a stamped platform name.
    """
    if override is not None:
        platform = PLATFORMS_BY_KEY.get(override.lower())
        if platform is None:
            raise ValueError(
                f"unknown --platform {override!r} (valid: "
                f"{', '.join(sorted(PLATFORMS_BY_KEY))})"
            )
        return platform
    dt_name = str((info or {}).get("DTPlatformName", "")).lower()
    return _DT_PLATFORM_NAMES.get(dt_name, IPHONE_PLATFORM)


@dataclass
class DiscoveredBundle:
    role: BundleRole
    path: Path

    @property
    def label(self) -> str:
        return f"{self.role.label} ({self.path.name})"


# --------------------------------------------------------------------------
# Real-tool adapters (injectable so the verification logic is testable without
# signing credentials — tests pass fakes, mirroring verify_macho_closure.py's
# `macho_info` injection).
# --------------------------------------------------------------------------
def codesign_verify(bundle: Path) -> tuple[bool, str]:
    """(ok, detail) for ``codesign --verify --strict --deep`` on one bundle."""
    result = subprocess.run(
        ["codesign", "--verify", "--strict", "--deep", str(bundle)],
        capture_output=True,
        text=True,
    )
    detail = (result.stderr or result.stdout or "").strip()
    return result.returncode == 0, detail


def read_signed_entitlements(bundle: Path) -> dict:
    return signed_entitlements(bundle)


def decode_embedded_profile(profile_path: Path) -> dict:
    """Decode a signed ``.mobileprovision`` CMS blob into its plist payload.

    ``security cms -D -i`` only parses the profile's own local signature — no
    network access or Apple account is involved."""
    output = subprocess.check_output(["security", "cms", "-D", "-i", str(profile_path)])
    return plistlib.loads(output)


# --------------------------------------------------------------------------
# Bundle-shape helpers (iOS layout: Info.plist / executable / profile / privacy
# manifest at the bundle root; the macOS ``Contents/`` layout is tolerated as a
# fallback so this can lint either).
# --------------------------------------------------------------------------
def read_info_plist(bundle: Path) -> dict | None:
    for candidate in (bundle / "Info.plist", bundle / "Contents" / "Info.plist"):
        if candidate.is_file():
            with candidate.open("rb") as handle:
                return plistlib.load(handle)
    return None


def embedded_profile_path(bundle: Path) -> Path | None:
    for candidate in (
        bundle / EMBEDDED_PROFILE_NAME,
        bundle / "Contents" / EMBEDDED_PROFILE_NAME,
    ):
        if candidate.is_file():
            return candidate
    return None


def privacy_manifest_present(bundle: Path) -> bool:
    for candidate in (
        bundle / PRIVACY_MANIFEST_NAME,
        bundle / "Contents" / "Resources" / PRIVACY_MANIFEST_NAME,
    ):
        if candidate.is_file():
            return True
    return False


def discover_payload_bundles(
    payload_app: Path,
    root_plugin_role: BundleRole = WIDGET_ROLE,
    root_plugin_roles_by_bundle_id: dict[str, BundleRole] | None = None,
) -> list[DiscoveredBundle]:
    """The host app plus every nested executable bundle, in nesting order.

    Nested slots mirror an App Store iOS export: the host app's own
    ``PlugIns/*.appex`` extensions (``root_plugin_role`` — a widget on
    iPhone/visionOS, the complication on a standalone watch export), its embedded
    ``Watch/*.app``, and each Watch app's ``PlugIns/*.appex`` complications."""
    bundles = [DiscoveredBundle(HOST_ROLE, payload_app)]

    plugins = payload_app / "PlugIns"
    if plugins.is_dir():
        for appex in sorted(plugins.glob("*.appex")):
            role = root_plugin_role
            if root_plugin_roles_by_bundle_id:
                info = read_info_plist(appex) or {}
                role = root_plugin_roles_by_bundle_id.get(
                    str(info.get("CFBundleIdentifier", "")), root_plugin_role
                )
            bundles.append(DiscoveredBundle(role, appex))

    watch_dir = payload_app / "Watch"
    if watch_dir.is_dir():
        for watch_app in sorted(watch_dir.glob("*.app")):
            bundles.append(DiscoveredBundle(WATCH_ROLE, watch_app))
            watch_plugins = watch_app / "PlugIns"
            if watch_plugins.is_dir():
                for appex in sorted(watch_plugins.glob("*.appex")):
                    bundles.append(DiscoveredBundle(COMPLICATION_ROLE, appex))

    return bundles


# --------------------------------------------------------------------------
# Application-identifier helpers.
# --------------------------------------------------------------------------
def entitlements_application_identifier(entitlements: dict) -> str:
    """The signed app id, iOS ``application-identifier`` first."""
    return entitlements.get("application-identifier") or entitlements.get(
        "com.apple.application-identifier", ""
    )


def prefix_from_application_identifier(app_id: str) -> str:
    """Return the App ID prefix, which is not necessarily the Team ID."""
    prefix, _, _ = app_id.partition(".")
    return prefix


def bundle_id_from_application_identifier(app_id: str) -> str:
    _, _, suffix = app_id.partition(".")
    return suffix


def app_id_authorizes_bundle(app_id_suffix: str, bundle_id: str) -> bool:
    """Whether a provisioned app-id suffix covers ``bundle_id``.

    An explicit App Store profile names the exact bundle id; a development
    profile may use a wildcard (``com.lorvex.*`` or bare ``*``), which
    authorizes any bundle id under its prefix."""
    if app_id_suffix == bundle_id:
        return True
    if app_id_suffix.endswith("*"):
        return bundle_id.startswith(app_id_suffix[:-1])
    return False


# --------------------------------------------------------------------------
# Per-bundle pure checks (take already-collected facts, return failures).
# --------------------------------------------------------------------------
def signature_failures(label: str, ok: bool, detail: str) -> list[str]:
    if not ok:
        return [f"{label}: code signature is invalid (codesign --verify failed): {detail}"]
    return []


def entitlements_failures(label: str, entitlements: dict, bundle_id: str) -> list[str]:
    if not entitlements:
        return [
            f"{label}: signed entitlements are empty — the bundle was signed "
            "without an entitlements plan (unsigned or ad-hoc)"
        ]
    app_id = entitlements_application_identifier(entitlements)
    if "." not in app_id:
        return [
            f"{label}: entitlements application-identifier is missing or malformed: {app_id!r}"
        ]
    suffix = bundle_id_from_application_identifier(app_id)
    if not app_id_authorizes_bundle(suffix, bundle_id):
        return [
            f"{label}: entitlements application-identifier provisions {suffix!r}, "
            f"which does not authorize bundle id {bundle_id!r}"
        ]
    return []


def embedded_profile_failures(
    label: str,
    profile_present: bool,
    profile_plist: dict | None,
    bundle_id: str,
    *,
    require_exact_app_id: bool = False,
) -> list[str]:
    if not profile_present:
        return [
            f"{label}: no embedded {EMBEDDED_PROFILE_NAME} — the bundle is not a "
            "signed distribution build"
        ]
    if profile_plist is None:
        return [f"{label}: embedded {EMBEDDED_PROFILE_NAME} could not be decoded"]
    app_id = profile_application_identifier(profile_plist)
    if "." not in app_id:
        return [f"{label}: embedded profile application-identifier is malformed: {app_id!r}"]
    suffix = bundle_id_from_application_identifier(app_id)
    prefix = prefix_from_application_identifier(app_id)
    prefixes = profile_plist.get("ApplicationIdentifierPrefix")
    if not isinstance(prefixes, list) or prefix not in prefixes:
        return [
            f"{label}: embedded profile ApplicationIdentifierPrefix "
            f"{prefixes!r} does not authorize app-id prefix {prefix!r}"
        ]
    if require_exact_app_id and suffix != bundle_id:
        return [
            f"{label}: App Store profile must explicitly provision bundle id "
            f"{bundle_id!r}, got {suffix!r}"
        ]
    if require_exact_app_id:
        teams = profile_plist.get("TeamIdentifier")
        if not isinstance(teams, list) or len(teams) != 1 or not teams[0]:
            return [
                f"{label}: App Store profile has no single TeamIdentifier: "
                f"{teams!r}"
            ]
    if not app_id_authorizes_bundle(suffix, bundle_id):
        return [
            f"{label}: embedded profile provisions {suffix!r}, which does not "
            f"authorize bundle id {bundle_id!r}"
        ]
    return []


def signed_profile_identity_failures(
    label: str,
    signed_entitlements: dict,
    profile_plist: dict,
    *,
    require_exact_app_id: bool,
) -> list[str]:
    """Cross-check signature and profile without conflating prefix and team.

    Older Apple developer accounts can have an App ID prefix distinct from
    their Team ID. The signature's application identifier must use a prefix
    authorized by ``ApplicationIdentifierPrefix``; the separately signed team
    entitlement must agree with the profile's ``TeamIdentifier``.
    """
    failures: list[str] = []
    signed_app_id = entitlements_application_identifier(signed_entitlements)
    profile_app_id = profile_application_identifier(profile_plist)
    signed_prefix = prefix_from_application_identifier(signed_app_id)
    prefixes = profile_plist.get("ApplicationIdentifierPrefix")
    if (
        not signed_prefix
        or not isinstance(prefixes, list)
        or signed_prefix not in prefixes
    ):
        failures.append(
            f"{label}: signed application-identifier prefix {signed_prefix!r} "
            f"is not authorized by profile prefixes {prefixes!r}"
        )
    if require_exact_app_id and signed_app_id != profile_app_id:
        failures.append(
            f"{label}: App Store signed application-identifier {signed_app_id!r} "
            f"does not exactly match profile {profile_app_id!r}"
        )

    signed_team = signed_entitlements.get("com.apple.developer.team-identifier")
    profile_team = profile_team_identifier(profile_plist)
    if signed_team and profile_team and signed_team != profile_team:
        failures.append(
            f"{label}: signed team identifier {signed_team!r} disagrees with "
            f"embedded-profile team {profile_team!r}"
        )
    return failures


def profile_aps_capability_failures(
    label: str, profile_plist: dict, target_entitlements: dict
) -> list[str]:
    """Cross-check the iOS and macOS spellings of the APNs environment key."""
    for key in ("aps-environment", "com.apple.developer.aps-environment"):
        required = target_entitlements.get(key)
        if not required:
            continue
        profile_value = profile_plist.get("Entitlements", {}).get(key)
        if profile_value != required:
            return [
                f"{label} profile {key} {profile_value!r} does not match "
                f"required {required!r}"
            ]
    return []


def privacy_manifest_failures(label: str, present: bool) -> list[str]:
    if not present:
        return [f"{label}: missing {PRIVACY_MANIFEST_NAME} privacy manifest"]
    return []


def version_metadata_failures(
    label: str, info: dict, expected_short: str, expected_build: str
) -> list[str]:
    failures: list[str] = []
    short = info.get("CFBundleShortVersionString")
    if str(short) != str(expected_short):
        failures.append(
            f"{label}: CFBundleShortVersionString {short!r} does not match release "
            f"metadata {expected_short!r}"
        )
    build = info.get("CFBundleVersion")
    if str(build) != str(expected_build):
        failures.append(
            f"{label}: CFBundleVersion {build!r} does not match release metadata "
            f"{expected_build!r}"
        )
    return failures


def team_consistency_failures(team_by_label: dict[str, str]) -> list[str]:
    """Every bundle that declares a team must name the same Apple Developer
    team — the host app, widget, Watch app, and complication are signed and
    submitted together, so a divergent team is a packaging mistake."""
    distinct = sorted({team for team in team_by_label.values() if team})
    if len(distinct) <= 1:
        return []
    return [
        "exported bundles disagree on team identifier: "
        f"{dict(sorted(team_by_label.items()))!r}"
    ]


def bundle_set_failures(seen_ids: set[str], expected_ids: set[str]) -> list[str]:
    """The discovered bundle-id set must equal the expected release set."""
    if not expected_ids or seen_ids == expected_ids:
        return []
    missing = sorted(expected_ids - seen_ids)
    unexpected = sorted(seen_ids - expected_ids)
    parts = []
    if missing:
        parts.append(f"missing {missing!r}")
    if unexpected:
        parts.append(f"unexpected {unexpected!r}")
    return ["exported payload bundle set does not match release metadata: " + ", ".join(parts)]


def verify_payload_app(
    payload_app: Path,
    metadata: dict[str, str],
    *,
    verify_signature: Callable[[Path], tuple[bool, str]] = codesign_verify,
    read_entitlements: Callable[[Path], dict] = read_signed_entitlements,
    decode_profile: Callable[[Path], dict] = decode_embedded_profile,
    expected_team: str | None = None,
    platform: Platform = IPHONE_PLATFORM,
    require_app_store_profile: bool = False,
) -> list[str]:
    """Recursively verify every bundle under ``payload_app``; return failures.

    ``platform`` fixes the expected release bundle set and the role label for a
    root ``PlugIns/*.appex``, so the same recursive signature/profile/
    entitlement/privacy/version checks run against whichever bundles that
    platform actually ships. The three tool adapters are injected so the whole
    traversal is exercisable against a synthetic fixture tree with no signing
    credentials."""
    failures: list[str] = []
    expected_short = metadata.get("MARKETING_VERSION", "")
    expected_build = metadata.get("BUILD_VERSION", "")
    expected_ids = {
        metadata[key] for key in platform.bundle_id_keys if metadata.get(key)
    }

    seen_ids: set[str] = set()
    team_by_label: dict[str, str] = {}
    root_roles_by_bundle_id = {
        metadata.get("WIDGET_BUNDLE_ID", ""): WIDGET_ROLE,
        metadata.get("FOCUS_FILTER_BUNDLE_ID", ""): FOCUS_FILTER_ROLE,
    }
    root_roles_by_bundle_id.pop("", None)

    for bundle in discover_payload_bundles(
        payload_app,
        platform.root_plugin_role,
        root_roles_by_bundle_id if platform is IPHONE_PLATFORM else None,
    ):
        label = bundle.label

        info = read_info_plist(bundle.path)
        if info is None:
            failures.append(f"{label}: missing Info.plist")
            continue
        bundle_id = info.get("CFBundleIdentifier", "")
        if not bundle_id:
            failures.append(f"{label}: Info.plist has no CFBundleIdentifier")
            continue
        seen_ids.add(bundle_id)

        ok, detail = verify_signature(bundle.path)
        failures.extend(signature_failures(label, ok, detail))

        try:
            entitlements = read_entitlements(bundle.path)
        except subprocess.CalledProcessError as error:
            entitlements = {}
            failures.append(f"{label}: could not read signed entitlements ({error})")
        else:
            failures.extend(entitlements_failures(label, entitlements, bundle_id))
            signed_app_id = entitlements_application_identifier(entitlements)
            if "." in signed_app_id:
                signed_team = entitlements.get(
                    "com.apple.developer.team-identifier"
                )
                if not isinstance(signed_team, str) or not signed_team:
                    failures.append(
                        f"{label}: signed entitlements have no team identifier"
                    )

        profile_path = embedded_profile_path(bundle.path)
        profile_plist: dict | None = None
        if profile_path is not None:
            try:
                profile_plist = decode_profile(profile_path)
            except subprocess.CalledProcessError as error:
                failures.append(
                    f"{label}: embedded {EMBEDDED_PROFILE_NAME} could not be decoded ({error})"
                )
        failures.extend(
            embedded_profile_failures(
                label,
                profile_path is not None,
                profile_plist,
                bundle_id,
                require_exact_app_id=require_app_store_profile,
            )
        )
        if profile_plist is not None and entitlements:
            # Xcode signs each extension independently.  App-id equality alone
            # does not prove the profile authorizes restricted capabilities;
            # in particular, the Focus Filter must carry its own App Group
            # authorization rather than inheriting the widget's profile.
            failures.extend(profile_app_group_failures(label, profile_plist, entitlements))
            failures.extend(
                profile_icloud_container_failures(label, profile_plist, entitlements)
            )
            failures.extend(profile_aps_capability_failures(label, profile_plist, entitlements))
            failures.extend(
                profile_icloud_environment_failures(label, profile_plist, entitlements)
            )
            failures.extend(
                signed_profile_identity_failures(
                    label,
                    entitlements,
                    profile_plist,
                    require_exact_app_id=require_app_store_profile,
                )
            )
            if require_app_store_profile:
                failures.extend(profile_distribution_type_failures(label, profile_plist))
                if "ExpirationDate" not in profile_plist:
                    failures.append(
                        f"{label}: App Store profile has no ExpirationDate"
                    )
                failures.extend(profile_expiry_failures(label, profile_plist))

        failures.extend(privacy_manifest_failures(label, privacy_manifest_present(bundle.path)))
        failures.extend(version_metadata_failures(label, info, expected_short, expected_build))

        entitlements_team = entitlements.get("com.apple.developer.team-identifier")
        profile_team = profile_team_identifier(profile_plist) if profile_plist else None
        team = profile_team or entitlements_team
        if team:
            team_by_label[label] = team

    failures.extend(team_consistency_failures(team_by_label))
    if expected_team:
        for label, team in sorted(team_by_label.items()):
            if team != expected_team:
                failures.append(
                    f"{label}: team {team!r} does not match expected APPLE_TEAM_ID "
                    f"{expected_team!r}"
                )
    failures.extend(bundle_set_failures(seen_ids, expected_ids))

    return failures


def resolve_payload_app(artifact: Path, work_root: Path) -> Path | None:
    """The ``Payload/*.app`` to verify: unzip an ``.ipa`` into ``work_root``, or
    accept an already-extracted ``.app`` directory. ``None`` if malformed."""
    if artifact.is_file() and artifact.suffix == ".ipa":
        subprocess.check_call(["unzip", "-q", str(artifact), "-d", str(work_root)])
        payload = work_root / "Payload"
        apps = sorted(payload.glob("*.app")) if payload.is_dir() else []
        return apps[0] if apps else None
    if artifact.is_dir() and artifact.suffix == ".app":
        return artifact
    return None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Recursively verify a re-signed iOS/visionOS/watchOS IPA export "
            "(signatures, entitlements, embedded profiles, privacy manifests, "
            "version metadata)."
        )
    )
    parser.add_argument(
        "artifact",
        type=Path,
        help="the exported .ipa file or the extracted Payload/<App>.app directory",
    )
    parser.add_argument(
        "--platform",
        choices=sorted(PLATFORMS_BY_KEY),
        default=None,
        help=(
            "target platform whose bundle set to assert; auto-detected from the "
            "payload's DTPlatformName when omitted (falls back to ios)."
        ),
    )
    parser.add_argument(
        "--distribution-method",
        choices=("app-store-connect", "development"),
        default="development",
        help=(
            "export method; app-store-connect additionally requires explicit "
            "per-bundle App Store profiles (no wildcard/development profile)"
        ),
    )
    args = parser.parse_args(argv)

    artifact: Path = args.artifact
    if not artifact.exists():
        print(
            f"NOTE: no signed iOS artifact at {artifact} — skipping iOS IPA recursive "
            "verification (no signed artifact / signing credentials on this runner)."
        )
        return 0
    if shutil.which("codesign") is None:
        print("verify_ios_ipa: codesign not available on this host — skipping.", file=sys.stderr)
        return 78

    metadata = load_metadata()
    expected_team = os.environ.get("APPLE_TEAM_ID", "").strip() or None

    work_root: Path | None = None
    try:
        if artifact.is_file() and artifact.suffix == ".ipa":
            work_root = Path(tempfile.mkdtemp(prefix="lorvex-ios-ipa-verify."))
        payload_app = resolve_payload_app(artifact, work_root or artifact.parent)
        if payload_app is None:
            print(
                f"artifact is not a verifiable IPA/app (expected an .ipa with a "
                f"Payload/*.app, or a Payload/*.app directory): {artifact}",
                file=sys.stderr,
            )
            return 2
        try:
            platform = platform_for_payload(read_info_plist(payload_app), args.platform)
        except ValueError as error:
            print(str(error), file=sys.stderr)
            return 2
        print(f"verifying {platform.label} IPA payload: {payload_app}")
        failures = verify_payload_app(
            payload_app,
            metadata,
            expected_team=expected_team,
            platform=platform,
            require_app_store_profile=args.distribution_method == "app-store-connect",
        )
    finally:
        if work_root is not None:
            shutil.rmtree(work_root, ignore_errors=True)

    if failures:
        print(f"iOS IPA recursive verification failed: {artifact}", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    print(f"iOS IPA recursive verification passed: {artifact}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
