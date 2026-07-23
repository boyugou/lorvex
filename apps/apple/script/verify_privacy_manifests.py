#!/usr/bin/env python3
"""Source-tree privacy-manifest completeness + consistency gate.

Lorvex ships two first-party ``PrivacyInfo.xcprivacy`` manifests: the macOS
app target's `Config/PrivacyInfo.xcprivacy` and the shared app-resource copy
at `Sources/LorvexApple/Resources/PrivacyInfo.xcprivacy`. Both must describe
the same privacy posture — a drift between them (e.g. one gets a reason code
added and the other doesn't) would silently ship an inconsistent story to App
Review. This script asserts, from source alone:

1. The two manifests are consistent on every field that must match: the
   tracking flag, tracking domains, collected-data types, and required-reason
   API categories/reasons.
2. Every required-reason API category the app's own Swift code actually uses
   (detected by grepping `Sources/` and `core/Sources/` for the category's
   trigger APIs) has a declared reason in both manifests. Declaring a reason
   for a category the code does not (yet, detectably) use is not flagged —
   only a used-but-undeclared category fails.
3. Every declared category key and reason code is one Apple actually defines
   (catches typos/stale codes), and the app declares no tracking and no data
   collection (`NSPrivacyTracking` false, `NSPrivacyTrackingDomains` and
   `NSPrivacyCollectedDataTypes` both empty).
4. A non-failing note lists the resolved third-party SwiftPM dependencies
   whose own privacy-manifest contributions this gate does not (and cannot)
   verify — that requires Xcode's App Store Connect privacy report generated
   from a signed archive, which is beyond what a source checkout can produce.
   Confirm those there before release; this gate only guards the first-party
   declarations above.
"""

from __future__ import annotations

import plistlib
import re
import sys
from pathlib import Path

from acknowledgments_data import ResolvedPackage, load_resolved_packages


ROOT = Path(__file__).resolve().parents[1]

MACOS_MANIFEST_PATH = ROOT / "Config" / "PrivacyInfo.xcprivacy"
APP_RESOURCE_MANIFEST_PATH = ROOT / "Sources" / "LorvexApple" / "Resources" / "PrivacyInfo.xcprivacy"

# Where the app's own shipping Swift code lives. Deliberately excludes
# `Tests/` (never shipped) and `.build/` (dependency checkouts, not
# first-party code, and explicitly out of scope per the module docstring).
CODE_SCAN_ROOTS: tuple[Path, ...] = (ROOT / "Sources", ROOT / "core" / "Sources")


class RequiredReasonCategory:
    """One Apple "required-reason" API category this gate can detect usage of.

    `usage_pattern` matches source text that calls a real Foundation/Darwin
    API in the category (not just an unrelated identifier that happens to
    share a word, e.g. a local function named `stat`) — see the two
    instances below for the exact APIs each pattern targets. `valid_reasons`
    is Apple's currently-published set of permitted reason codes for the
    category; a manifest declaring anything else has a stale or mistyped
    code.
    """

    def __init__(self, key: str, description: str, usage_pattern: re.Pattern[str], valid_reasons: frozenset[str]) -> None:
        self.key = key
        self.description = description
        self.usage_pattern = usage_pattern
        self.valid_reasons = valid_reasons


REQUIRED_REASON_CATEGORIES: tuple[RequiredReasonCategory, ...] = (
    RequiredReasonCategory(
        key="NSPrivacyAccessedAPICategoryUserDefaults",
        description="UserDefaults",
        usage_pattern=re.compile(r"\bUserDefaults\b"),
        valid_reasons=frozenset({"1C8F.1", "CA92.1", "C56D.1", "AC6B.1"}),
    ),
    RequiredReasonCategory(
        key="NSPrivacyAccessedAPICategoryFileTimestamp",
        description=(
            "file timestamp reads (attributesOfItem, FileAttributeKey/URLResourceKey "
            "modification or creation date, or the getattrlist syscall family)"
        ),
        usage_pattern=re.compile(
            r"\.attributesOfItem\(atPath"
            r"|FileAttributeKey\.(?:modificationDate|creationDate)\b"
            r"|\.(?:contentModificationDateKey|creationDateKey)\b"
            r"|\.contentModificationDate\b"
            r"|NSFile(?:Modification|Creation)Date\b"
            r"|\b(?:fstatat|getattrlistbulk|fgetattrlist|getattrlist)\s*\("
        ),
        valid_reasons=frozenset({"0A2A.1", "3B52.1", "C617.1", "DDA9.1"}),
    ),
)

# Apple defines exactly five required-reason API categories today. Every
# category key a manifest declares must be one of these, and every reason
# code under it must be in that category's published set — this validates
# manifest correctness independent of whether this gate has a usage detector
# for the category (the two above are the ones the app currently exercises).
ALL_CATEGORY_VALID_REASONS: dict[str, frozenset[str]] = {
    category.key: category.valid_reasons for category in REQUIRED_REASON_CATEGORIES
} | {
    "NSPrivacyAccessedAPICategorySystemBootTime": frozenset({"35F9.1", "8FFB.1", "3D61.1"}),
    "NSPrivacyAccessedAPICategoryDiskSpace": frozenset({"85F4.1", "E174.1", "7D9E.1", "B728.1"}),
    "NSPrivacyAccessedAPICategoryActiveKeyboards": frozenset({"3EC4.1", "54BD.1"}),
}


def load_privacy_plist(path: Path) -> dict:
    with path.open("rb") as file:
        return plistlib.load(file)


def _canonicalize_entry(entry: dict) -> tuple:
    canonical: list[tuple] = []
    for key, value in entry.items():
        if isinstance(value, list):
            value = tuple(sorted(value))
        canonical.append((key, value))
    return tuple(sorted(canonical))


def canonical_collected_data_types(plist: dict) -> frozenset[tuple]:
    return frozenset(_canonicalize_entry(entry) for entry in plist.get("NSPrivacyCollectedDataTypes", []))


def canonical_accessed_api_types(plist: dict) -> dict[str, frozenset[str]]:
    declared: dict[str, frozenset[str]] = {}
    for entry in plist.get("NSPrivacyAccessedAPITypes", []):
        category = entry.get("NSPrivacyAccessedAPIType")
        reasons = entry.get("NSPrivacyAccessedAPITypeReasons", [])
        declared[category] = frozenset(reasons)
    return declared


def consistency_failures(macos_label: str, macos: dict, resource_label: str, resource: dict) -> list[str]:
    """Every field the two first-party manifests must agree on.

    A drift here means the macOS target and the shared app-resource copy
    would tell App Review two different stories about the same app.
    """
    failures: list[str] = []

    macos_tracking = macos.get("NSPrivacyTracking")
    resource_tracking = resource.get("NSPrivacyTracking")
    if macos_tracking != resource_tracking:
        failures.append(
            f"NSPrivacyTracking drift: {macos_label}={macos_tracking!r}, "
            f"{resource_label}={resource_tracking!r}"
        )

    macos_domains = frozenset(macos.get("NSPrivacyTrackingDomains", []))
    resource_domains = frozenset(resource.get("NSPrivacyTrackingDomains", []))
    if macos_domains != resource_domains:
        failures.append(
            f"NSPrivacyTrackingDomains drift: {macos_label}={sorted(macos_domains)!r}, "
            f"{resource_label}={sorted(resource_domains)!r}"
        )

    macos_collected = canonical_collected_data_types(macos)
    resource_collected = canonical_collected_data_types(resource)
    if macos_collected != resource_collected:
        failures.append(
            f"NSPrivacyCollectedDataTypes drift between {macos_label} and {resource_label}"
        )

    macos_apis = canonical_accessed_api_types(macos)
    resource_apis = canonical_accessed_api_types(resource)
    if macos_apis != resource_apis:
        macos_view = {key: sorted(value) for key, value in macos_apis.items()}
        resource_view = {key: sorted(value) for key, value in resource_apis.items()}
        failures.append(
            f"NSPrivacyAccessedAPITypes drift between {macos_label} ({macos_view}) and "
            f"{resource_label} ({resource_view})"
        )

    return failures


def no_tracking_no_collection_failures(label: str, plist: dict) -> list[str]:
    failures: list[str] = []
    tracking = plist.get("NSPrivacyTracking")
    if tracking is not False:
        failures.append(f"{label}: NSPrivacyTracking must be false, got {tracking!r}")

    domains = plist.get("NSPrivacyTrackingDomains", [])
    if domains:
        failures.append(f"{label}: NSPrivacyTrackingDomains must be empty, got {domains!r}")

    collected = plist.get("NSPrivacyCollectedDataTypes", [])
    if collected:
        failures.append(f"{label}: NSPrivacyCollectedDataTypes must be empty, got {collected!r}")

    return failures


def accessed_api_type_structural_failures(label: str, plist: dict) -> list[str]:
    """Every declared category key and reason code is one Apple defines.

    Independent of whether this app currently uses the category — this
    catches a typo'd category name or a stale/invalid reason code regardless.
    """
    failures: list[str] = []
    seen_categories: set[str] = set()

    for entry in plist.get("NSPrivacyAccessedAPITypes", []):
        category = entry.get("NSPrivacyAccessedAPIType")
        reasons = entry.get("NSPrivacyAccessedAPITypeReasons", [])

        if category in seen_categories:
            failures.append(f"{label}: duplicate NSPrivacyAccessedAPIType entry for {category!r}")
        seen_categories.add(category)

        valid_reasons = ALL_CATEGORY_VALID_REASONS.get(category)
        if valid_reasons is None:
            failures.append(f"{label}: unrecognized NSPrivacyAccessedAPIType category {category!r}")
            continue

        if not reasons:
            failures.append(f"{label}: category {category!r} declares no reason codes")
        for reason in reasons:
            if reason not in valid_reasons:
                failures.append(
                    f"{label}: category {category!r} declares unknown reason code {reason!r}; "
                    f"valid codes are {sorted(valid_reasons)!r}"
                )

    return failures


def swift_files(roots: tuple[Path, ...]) -> list[Path]:
    files: list[Path] = []
    for root in roots:
        if not root.exists():
            continue
        files.extend(sorted(root.rglob("*.swift")))
    return files


def category_usage_evidence(pattern: re.Pattern[str], roots: tuple[Path, ...]) -> Path | None:
    """First source file matching `pattern`, or `None` if the category is unused.

    Only the first hit is needed — this gate cares whether the category is
    used at all, not every call site.
    """
    for path in swift_files(roots):
        try:
            source = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        if pattern.search(source):
            return path
    return None


def required_reason_coverage_failures(
    label: str,
    plist: dict,
    *,
    code_roots: tuple[Path, ...] = CODE_SCAN_ROOTS,
    categories: tuple[RequiredReasonCategory, ...] = REQUIRED_REASON_CATEGORIES,
) -> list[str]:
    """Fail if shipping code uses a required-reason category with no declared reason.

    The converse (a declared-but-undetected-as-used category) is not a
    failure: grep-based usage detection cannot prove a negative, and
    over-declaring a reason is not a compliance problem.
    """
    failures: list[str] = []
    declared = canonical_accessed_api_types(plist)

    for category in categories:
        evidence = category_usage_evidence(category.usage_pattern, code_roots)
        if evidence is None:
            continue
        if not declared.get(category.key):
            try:
                evidence_label = evidence.relative_to(ROOT)
            except ValueError:
                evidence_label = evidence
            failures.append(
                f"{label}: first-party code uses {category.description} "
                f"(e.g. {evidence_label}) but declares no "
                f"{category.key} reason"
            )

    return failures


def dependency_boundary_note(*, resolved: dict[str, ResolvedPackage] | None = None) -> str:
    """Non-failing note naming the third-party manifest boundary this gate cannot cover.

    Third-party SwiftPM dependencies (GRDB, the SwiftNIO family, etc.) carry
    their own `PrivacyInfo.xcprivacy` manifests, merged into the app's privacy
    report only by Xcode at archive time. A source checkout has no equivalent
    of that merge, so the resolved dependency set is only ever surfaced here
    as a checklist for the archive-level report, never asserted against.

    `resolved` defaults to the real `Package.resolved` union
    (`acknowledgments_data.load_resolved_packages`); tests inject a synthetic
    mapping instead.
    """
    if resolved is None:
        try:
            resolved = load_resolved_packages()
        except (FileNotFoundError, ValueError) as error:
            return (
                "Third-party privacy-manifest boundary: could not enumerate resolved "
                f"SwiftPM dependencies ({error}). Confirm third-party manifest "
                "contributions in the final archive-level Apple privacy report."
            )

    lines = [
        "Third-party privacy-manifest boundary: this gate verifies only the two "
        "first-party PrivacyInfo.xcprivacy manifests. The following resolved "
        "SwiftPM dependencies carry (or may carry) their own privacy manifests, "
        f"merged into the app's privacy report only at archive time — confirm "
        "each one's contribution in the final signed-archive privacy report, "
        "not from this source-tree gate:",
    ]
    for identity in sorted(resolved):
        package = resolved[identity]
        lines.append(f"  - {identity} {package.version} ({package.location})")
    return "\n".join(lines)


def privacy_manifest_failures(
    macos_label: str,
    macos: dict,
    resource_label: str,
    resource: dict,
    *,
    code_roots: tuple[Path, ...] = CODE_SCAN_ROOTS,
) -> list[str]:
    failures: list[str] = []
    failures.extend(consistency_failures(macos_label, macos, resource_label, resource))
    failures.extend(no_tracking_no_collection_failures(macos_label, macos))
    failures.extend(no_tracking_no_collection_failures(resource_label, resource))
    failures.extend(accessed_api_type_structural_failures(macos_label, macos))
    failures.extend(accessed_api_type_structural_failures(resource_label, resource))
    failures.extend(required_reason_coverage_failures(macos_label, macos, code_roots=code_roots))
    failures.extend(required_reason_coverage_failures(resource_label, resource, code_roots=code_roots))
    return failures


def main() -> int:
    for path in (MACOS_MANIFEST_PATH, APP_RESOURCE_MANIFEST_PATH):
        if not path.is_file():
            print(f"missing first-party privacy manifest: {path}", file=sys.stderr)
            return 1

    macos_label = str(MACOS_MANIFEST_PATH.relative_to(ROOT))
    resource_label = str(APP_RESOURCE_MANIFEST_PATH.relative_to(ROOT))
    macos_plist = load_privacy_plist(MACOS_MANIFEST_PATH)
    resource_plist = load_privacy_plist(APP_RESOURCE_MANIFEST_PATH)

    failures = privacy_manifest_failures(macos_label, macos_plist, resource_label, resource_plist)

    print(dependency_boundary_note())

    if failures:
        print("Privacy manifest verification failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    print(f"Privacy manifest verification passed: {macos_label} and {resource_label} are consistent")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
