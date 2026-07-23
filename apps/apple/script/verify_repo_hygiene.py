#!/usr/bin/env python3
"""Verify source-controlled project areas stay free of editor and OS detritus."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCAN_ROOTS = [
    ROOT / "Config",
    ROOT / "Sources",
    ROOT / "Tests",
    ROOT / "docs",
    ROOT / "core",
    ROOT / "script",
]
APP_INTENTS_METADATA_ROOTS = [
    ROOT / "Sources" / "LorvexSystemIntents",
    ROOT / "Sources" / "LorvexWidgetIntents",
    ROOT / "Sources" / "LorvexWidgetExtension",
]
IOS_ARCHIVE_SCRIPT = ROOT / "script" / "archive_ios.sh"
VERIFY_ALL_SCRIPT = ROOT / "script" / "verify_all.sh"
APPLE_CI_WORKFLOW = ROOT.parents[1] / ".github" / "workflows" / "apple-ci.yml"
FORBIDDEN_FILENAMES = {
    ".DS_Store",
    "Thumbs.db",
    "desktop.ini",
}
FORBIDDEN_SUFFIXES = {
    ".bak",
    ".orig",
    ".rej",
    ".swp",
    ".tmp",
}
FORBIDDEN_CURRENT_SOURCE_PHRASES = {
    "requires the " + "Rust store": (
        "current Swift sources must not describe active functionality as requiring "
        "the deleted Rust store"
    ),
    "engine sync coordinator " + "is not built": (
        "current Swift sources must not describe the live Cloud Sync coordinator "
        "as unbuilt"
    ),
}
FORBIDDEN_APP_INTENTS_METADATA_MARKERS = {
    "SystemL10n.resource(": (
        "App Intents metadata must use direct LocalizedStringResource initializers, "
        "not SystemL10n.resource"
    ),
    "WidgetSupportL10n.resource(": (
        "App Intents metadata must use direct LocalizedStringResource initializers, "
        "not WidgetSupportL10n.resource"
    ),
    "WidgetL10n.resource(": (
        "App Intents metadata must use direct LocalizedStringResource initializers, "
        "not WidgetL10n.resource"
    ),
    "static var title": "App Intents title metadata must be static let, not computed static var",
    "static var description": (
        "App Intents description metadata must be static let, not computed static var"
    ),
    "static var typeDisplayRepresentation": (
        "App Intents typeDisplayRepresentation must be static let, not computed static var"
    ),
    "static var caseDisplayRepresentations": (
        "App Intents caseDisplayRepresentations must be static let, not computed static var"
    ),
}


def repo_hygiene_failures(
    *,
    root: Path = ROOT,
    scan_roots: list[Path] | None = None,
) -> list[str]:
    failures: list[str] = []
    roots = scan_roots or SCAN_ROOTS

    for scan_root in roots:
        if not scan_root.exists():
            continue
        for path in sorted(scan_root.rglob("*")):
            if path.is_dir():
                continue
            if path.name in FORBIDDEN_FILENAMES or path.suffix in FORBIDDEN_SUFFIXES:
                failures.append(f"forbidden generated/editor artifact: {path.relative_to(root)}")
                continue
            if path.suffix in {".swift", ".md", ".py", ".sh"}:
                try:
                    source = path.read_text(encoding="utf-8")
                except UnicodeDecodeError:
                    continue
                for phrase, message in FORBIDDEN_CURRENT_SOURCE_PHRASES.items():
                    if phrase in source:
                        failures.append(
                            f"{message}: {path.relative_to(root)} contains '{phrase}'"
                        )

    return failures


def app_intents_metadata_literal_failures(
    *,
    root: Path = ROOT,
    scan_roots: list[Path] | None = None,
) -> list[str]:
    failures: list[str] = []
    roots = scan_roots or APP_INTENTS_METADATA_ROOTS

    for scan_root in roots:
        if not scan_root.exists():
            continue
        for path in sorted(scan_root.rglob("*.swift")):
            source = path.read_text(encoding="utf-8")
            for marker, message in FORBIDDEN_APP_INTENTS_METADATA_MARKERS.items():
                if marker in source:
                    failures.append(
                        f"{message}: {path.relative_to(root)} contains '{marker}'"
                    )

    return failures


def distribution_script_failures(path: Path = IOS_ARCHIVE_SCRIPT) -> list[str]:
    if not path.is_file():
        return [f"missing iOS archive script: {path.relative_to(ROOT)}"]

    source = path.read_text(encoding="utf-8")
    failures: list[str] = []
    if "notarytool submit '$IPA_PATH'" in source or 'notarytool submit "$IPA_PATH"' in source:
        failures.append(
            "script/archive_ios.sh must not suggest notarytool for IPA uploads"
        )
    if "xcrun altool --upload-app" not in source:
        failures.append("script/archive_ios.sh must document App Store Connect IPA upload via altool")
    if "verify_macho_closure.py" not in source:
        failures.append("script/archive_ios.sh must use verify_macho_closure.py for watch embed validation")
    if "grep -A 20 'LorvexMobileApp:'" in source:
        failures.append("script/archive_ios.sh must not use grep windows for watch embed validation")
    return failures


def uncommented_yaml_line(line: str) -> str:
    in_single = False
    in_double = False
    escaped = False
    for index, char in enumerate(line):
        if escaped:
            escaped = False
            continue
        if char == "\\" and in_double:
            escaped = True
            continue
        if char == "'" and not in_double:
            in_single = not in_single
            continue
        if char == '"' and not in_single:
            in_double = not in_double
            continue
        if char == "#" and not in_single and not in_double:
            return line[:index].rstrip()
    return line


def uncommented_yaml_source(path: Path) -> str:
    lines: list[str] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        uncommented = uncommented_yaml_line(line)
        if not uncommented.strip():
            continue
        lines.append(uncommented)
    return "\n".join(lines)


# A trailing `|| true`, `|| :`, or `|| exit 0` swallows a command's failure — the
# gate name stays present for a substring check while the gate itself is dead.
FAILURE_SWALLOWING = re.compile(r"\|\|\s*(?:true\b|:|exit\s+0\b)")


def _marker_is_neutered(source: str, marker: str) -> bool:
    """True if a line carrying ``marker`` also swallows its own exit status."""
    return any(
        marker in line and FAILURE_SWALLOWING.search(line)
        for line in source.splitlines()
    )


def _required_command_failures(source: str, markers: list[str], label: str) -> list[str]:
    """Assert each required command is present *and* not failure-swallowed."""
    failures: list[str] = []
    for marker in markers:
        if marker not in source:
            failures.append(f"{label} missing required command: {marker}")
        elif _marker_is_neutered(source, marker):
            failures.append(
                f"{label} neuters required command (|| true / || : / || exit 0): {marker}"
            )
    return failures


def verify_all_gate_failures(path: Path = VERIFY_ALL_SCRIPT) -> list[str]:
    """Assert the verification gate script runs each required verifier command.

    ``apple-ci.yml`` delegates its whole non-packaging gate to
    ``verify_all.sh``, so the individual verifier commands the workflow used to
    inline now live here. Each must be present *and* not failure-swallowed."""
    if not path.is_file():
        return [f"missing verification gate script: {path}"]

    source = path.read_text(encoding="utf-8")
    required_markers = [
        "swift build",
        "swift test",
        "( cd core && swift test )",
        "python3 -m py_compile",
        "python3 -m unittest discover -s script -p 'test_*.py'",
        "./script/verify_schema_embed.sh",
        "./script/verify_sync_payload_contract.py",
        "./script/verify_repo_hygiene.py",
        "./script/verify_app_metadata.py",
        "./script/verify_apple_strategy.py",
        "./script/verify_build_matrix.py",
        "./script/verify_cloudkit_sync_readiness.py",
        "./script/verify_mcp_tool_catalog.py",
        "./script/verify_localization_catalog.py",
        "./script/verify_system_entrypoints.py",
        "./script/verify_core_service_coverage.py",
        "./script/verify_hotspots.py",
        "./script/verify_user_docs.py",
        "./script/mcp_stdio_smoke.py",
    ]
    return _required_command_failures(source, required_markers, "Apple verification gate")


def ci_workflow_failures(
    path: Path = APPLE_CI_WORKFLOW,
    verify_all_path: Path = VERIFY_ALL_SCRIPT,
) -> list[str]:
    """The Apple CI workflow delegates its gate to ``verify_all.sh`` plus the
    two platform Release-link scripts. Assert that delegation is present and not
    failure-swallowed, then follow it into ``verify_all.sh`` for the individual
    verifier commands that gate now owns."""
    if not path.is_file():
        return [f"missing Apple CI workflow: {path}"]

    source = uncommented_yaml_source(path)
    delegation_markers = [
        "./script/verify_all.sh",
        "./script/verify_mobile_release_link.sh",
        "./script/verify_vision_release_link.sh",
    ]
    failures = _required_command_failures(source, delegation_markers, "Apple CI workflow")
    failures.extend(verify_all_gate_failures(verify_all_path))
    return failures


def main() -> int:
    failures = repo_hygiene_failures()
    failures.extend(app_intents_metadata_literal_failures())
    failures.extend(distribution_script_failures())
    failures.extend(ci_workflow_failures())
    if failures:
        print("Repository hygiene verification failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    print("Repository hygiene verification passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
