#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import re
import sys

from expected_mcp_tools import EXPECTED_MCP_TOOLS


ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = ROOT.parents[1]
USER_GUIDE = ROOT / "docs" / "USER_GUIDE.md"
README = ROOT / "README.md"
APPLE_NATIVE_ARCH = ROOT / "docs" / "architecture" / "apple-native-architecture.md"
CONTRIBUTING = ROOT / "docs" / "CONTRIBUTING.md"
CLAUDE_GUIDE = ROOT / "CLAUDE.md"
FEATURES = ROOT / "docs" / "reference" / "FEATURES.md"
DISTRIBUTION = ROOT / "docs" / "DISTRIBUTION.md"
CI_RELEASE_TRIGGER_POLICY = ROOT / "docs" / "execution" / "CI_RELEASE_TRIGGER_POLICY.md"
ROADMAP = REPO_ROOT / "ROADMAP.md"
MCP_TOOL_COUNT_PATTERNS = {
    ROADMAP: {
        "catalog headline": re.compile(
            r"(?m)^- \*\*MCP catalog at (?P<count>\d+) tools\.\*\*"
        ),
        "reference parity count": re.compile(
            r"(?m)^  85 reference tools against Apple's catalog \(now (?P<count>\d+)\):"
        ),
        "parameter audit count": re.compile(
            r"(?m)^  across the Apple MCP catalog \(currently (?P<count>\d+) tools\)"
        ),
        "Tauri parity count": re.compile(
            r"(?m)^- \*\*Full Tauri MCP parity \+ beyond\.\*\* The current Apple catalog has (?P<count>\d+) tools\."
        ),
        "gap closure count": re.compile(
            r"(?m)^  additions leave the current catalog at (?P<count>\d+) tools\."
        ),
    },
    FEATURES: {
        "feature matrix count": re.compile(r"(?m)^MCP tool count: (?P<count>\d+)\."),
    },
    APPLE_NATIVE_ARCH: {
        "architecture count": re.compile(
            r"(?m)^- It exposes (?P<count>\d+) tools spanning tasks, focus, lists, habits, calendar, reviews,"
        ),
    },
}
LEGACY_MCP_TOOL_NAMES = {
    "system_overview",
    "system_status",
    "system_context_read",
    "task_create",
    "task_update",
    "task_detail",
    "task_list_query",
    "task_search",
    "task_complete",
    "task_defer",
    "focus_session_start",
    "focus_session_end",
    "focus_session_read",
    "ics_export",
    "task_ai_notes_read",
    "task_ai_notes_write",
    "data_export",
    "weekly_brief",
}


CHECKS = {
    USER_GUIDE: {
        "stale": [
            "### Complications (future)",
            "Future versions will add watch complications.",
            "Complication support is planned for the Infograph",
            "current focus task and a Start/End session button",
            "It reads the same `widget_snapshot_v2.json` file",
            "`task_create` MCP tool",
            "`ics_export` MCP tool",
            "`data_export` MCP tool",
            "`weekly_brief` tool call",
        ],
        "required": [
            "| **Notifications** | Scheduling a task reminder |",
            "current focus task and opens Lorvex directly to Today when tapped",
            "### Watch Complications",
            "Lorvex ships a focus complication backed by the Watch's atomically stored replica",
            "keeps it until a checksum- and identity-bound application ACK arrives",
            "`create_task`, `update_task`, `get_task`, `list_tasks`, `search_tasks`, `complete_task`, `cancel_task`, `reopen_task`, `defer_task`",
            "`batch_create_tasks`, `batch_update_tasks`, `batch_defer_tasks`, `batch_complete_tasks`, `batch_reopen_tasks`, `batch_move_tasks`",
            "`create_list`, `update_list`, `delete_list`, `archive_list`, `unarchive_list`, `get_lists`, `get_list`, `get_list_health_snapshot`",
            "`create_calendar_event`, `update_calendar_event`, `delete_calendar_event`, `get_calendar_timeline`, `search_calendar_events`",
            "`get_dependency_graph`, `get_upcoming_tasks`",
            "`export_calendar_ics`",
            "`create_task` MCP tool",
            "`export_calendar_ics` MCP tool",
            "`export_data` MCP tool",
            "`get_weekly_brief` tool call",
            "`get_ai_changelog`, `get_recent_logs`",
            "outbound record export, private database subscription, remote-change refresh,\ninbound record application, and atomic SQLite change-token checkpointing are\nready",
            "Core planning entities such as tasks, lists, habits, calendar events, memory,\nand focus plans route through the same native inbound sync\nengine used by the Swift core tests",
            "typed HLC LWW gates, tombstones,\nredirect-aware pending inbox draining, and conflict logging",
        ],
    },
    README: {
        "stale": [
            "Adopt the official MCP Swift SDK for the Apple MCP host after a real stdio",
            "compatibility spike.",
            "local builds fall back to preview data when no App Group",
        ],
        "required": [
            "A Swift-native MCP host built on the official",
            "App Intents / Shortcuts / Siri",
            "widget, CarPlay, and MCP surfaces all consume it",
        ],
    },
    APPLE_NATIVE_ARCH: {
        "stale": [
            "mobile Shortcuts share the same native navigation target",
            "watchOS read paths aligned with the same tested snapshot contract as widgets while avoiding a\n  separate watch sync model",
            "`LorvexWatchStoreFactory` prefers the App Group snapshot",
            "the factory falls back to\n  `LorvexCoreRuntimeFactory`",
        ],
        "required": [
            "The shared `LorvexSystemIntents` target owns the `AppIntent`, `AppEntity`",
            "The mobile app entry links `LorvexSystemIntents`",
            "`MobileStoreFactory` centralizes the mobile/vision store bootstrap",
            "production `LorvexWatchStoreFactory` is read-only with respect\n  to SQLite",
            "through replaceable `WCSession.updateApplicationContext`",
            "replica state fails closed instead of opening a second writable database",
            "whose applied receipt commits in the same transaction as the domain write",
        ],
    },
    CONTRIBUTING: {
        "stale": [
            "Add user-facing Shortcuts/App Intents under `Sources/LorvexApple/Intents`",
        ],
        "required": [
            "LorvexSystemIntents/    # Shared App Intents and Shortcuts provider",
            "Add user-facing Shortcuts/App Intents here, not under the macOS-only app target",
            "Update `script/expected_mcp_tools.py` in the same change",
            "Apple-only strategy checks (`script/verify_apple_strategy.py`)",
            "Tauri/Node packaging artifacts",
            "web UI source artifacts such as `.tsx`, `.jsx`, `.css`, `.html`, and `.js`",
            "custom theme-system source paths",
            "Rust MCP server fallback names",
            "`RustMCP`, `MCPServer`, `MCPDaemon`, or `MCPSupervisor`",
            "script/verify_mcp_tool_catalog.py",
            "script/verify_core_service_coverage.py",
            "fall through to an `unsupportedServiceOperation` default",
            "Hotspot checks (`script/verify_hotspots.py`)",
            "current 800-line cap",
            "Python verification script compilation and unit tests, including MCP client config validation",
            "build matrix validation, system entrypoint drift checks",
            "shared quality gate metadata",
            "Generated MCP client config verification, including executable bundled helper validation",
            "script/verify_build_matrix.py",
            "script/verify_system_entrypoints.py",
        ],
    },
    CLAUDE_GUIDE: {
        "stale": [
            'Dispatch with `model: "opus"`',
            'model: "opus"',
            'Dispatch with `model: "gpt-5.5"`',
            '`reasoning_effort: "high"`',
        ],
        "required": [
            "Do not pin a model or reasoning setting in repository policy.",
            "This repo does not try to preserve the Tauri/React UI",
            "Never add Windows/Linux/Web/Tauri shims.",
            "No third-party UI libraries.",
            "No in-app AI runtime.",
            "The MCP host (`LorvexMCPHost`) is the primary write interface.",
            "SwiftUI/AppKit/SwiftPM",
            "official Swift SDK",
            "swiftlang/swift-markdown",
            "No email addresses.",
        ],
    },
    FEATURES: {
        "stale": [
            "| CloudKit sync (read + write) | [PARTIAL] | Scaffold present; production container provisioning required |",
            "| Prompt-injection fencing on MCP read responses | [SHIPPED] | get_task, list_tasks, get_overview |",
        ],
        "required": [
            "| CloudKit sync (read + write) | [SHIPPED] | Live mode includes outbound record export, private database subscription, remote-change refresh, inbound record application, and atomic SQLite change-token checkpointing; distributed builds still require CloudKit entitlement/container provisioning |",
            "Structured read payloads carrying user-controlled text are key-aware fenced through `SecurityFencing.fenceValue`",
            "including task, calendar, list/tag, focus, habit, review, and memory reads",
        ],
    },
    DISTRIBUTION: {
        "stale": [
            "2. [macOS — Developer ID notarized](#2-macos--developer-id-notarized)",
            "2. [macOS — distributable DMG](#2-macos--distributable-dmg-the-default-packaging-path)",
            "3. [macOS — Developer ID notarized](#3-macos--developer-id-notarized-archive-path)",
            "3. [iOS/iPadOS — App Store Connect](#3-iosipados--app-store-connect)",
            "## 3. iOS/iPadOS — App Store Connect",
            "TODO: MAS archive script",
            "`com.apple.developer.carplay-*` — required if CarPlay integration is added.",
            "`upload_testflight.sh` could wrap `xcrun notarytool` or the App Store Connect",
        ],
        "required": [
            "2. [macOS — production Developer ID DMG](#2-macos--production-developer-id-dmg)",
            "3. [macOS — local development and CI packages](#3-macos--local-development-and-ci-packages)",
            "4. [macOS - Mac App Store](#4-macos---mac-app-store)",
            "5. [iOS/iPadOS — App Store Connect](#5-iosipados--app-store-connect)",
            "10. [Distribution gaps and follow-up work](#10-distribution-gaps-and-follow-up-work)",
            "## 4. macOS - Mac App Store",
            "## 5. iOS/iPadOS — App Store Connect",
            "## 10. Distribution gaps and follow-up work",
            "./script/archive_mas.sh --preflight",
            "./script/archive_mas.sh --package",
            "`package_dmg.sh` is the only direct-distribution release command.",
            "`dist/Lorvex-macOS-<version>+<build>-arm64.dmg`",
            "It never moves, backs up, or restores that data.",
            "com.lorvex.apple.focus-filter",
            "a reused wildcard profile",
            "CloudKit production schema promotion remains a manual release gate",
            "| iOS CarPlay approval template | `LorvexCarPlay.entitlements` | — | — | — | — | — | CarPlay communication entitlement template; merge into the iOS app entitlements only after Apple approval |",
            "The template declares\n`com.apple.developer.carplay-communication`; do not merge it into\n`LorvexMobileApp.entitlements` until Apple approves the CarPlay capability",
            "Do not use\n`xcrun notarytool` for IPA uploads; notarization is the Developer ID macOS\ndistribution path, not the TestFlight/App Store Connect path.",
        ],
    },
    CI_RELEASE_TRIGGER_POLICY: {
        "stale": [
            "`Swift Build`",
            "`Swift Test`",
            "`MCP Smoke`",
            "Signed `.pkg` uploaded to workflow artifacts",
            "Signed `.pkg` uploaded to App Store Connect",
            "App Store Connect (App Store signed .pkg)",
            "App Store distribution signed `.pkg` submitted to App Store Connect",
        ],
        "required": [
            "`Apple CI / Swift package`",
            "`script/verify_schema_embed.sh`",
            "`script/mcp_stdio_smoke.py` — MCP host stdio round-trip against the Swift core",
            "Apple static verifiers for metadata, strategy, build matrix, CloudKit\n  readiness, MCP catalog, localization, system entrypoints, core service\n  coverage, hotspots, repo hygiene, and user docs",
            "Signed `.ipa` uploaded to workflow artifacts",
            "Signed `.ipa` uploaded to App Store Connect",
            "App Store Connect (App Store signed IPA)",
            "App Store distribution signed `.ipa` submitted to App Store Connect",
        ],
    },
    ROOT / "docs" / "release.md": {
        "stale": [
            # The Rust FFI bridge and its dedicated quality-gate verifiers were
            # removed in the pure-Swift core cutover; release.md must not
            # reintroduce them.
            "Rust bridge mutation sequence coverage",
            "Rust bridge mutation sequence validation",
            "bundled Rust bridge presence",
            "Rust bridge dylib",
        ],
        "required": [
            "Swift MCP tool catalog contract",
            "the release manifest records the expected tool count from `script/expected_mcp_tools.py`",
            "`script/verify_mcp_tool_catalog.py` proves that the typed tool-definition",
            "generated MCP client config points at an executable bundled helper",
            "generated MCP client config carries Apple-only Swift-native MCP metadata",
            "explicitly forbids a Rust MCP server fallback",
            "release manifest records the MCP client config generator, verifier, Python test glob, and database environment keys",
            "release manifest records WidgetKit integration metadata for the embedded",
            "Home Screen widget and the Control Widget kind/display contract",
            "release manifest records CloudKit sync readiness metadata",
            "outbound record\n  export, private database subscription, remote-change refresh, and\n  atomic SQLite change-token checkpointing are ready",
            "inbound record application is ready\n  with conservative field-level remote/local merge",
            "builds the `LorvexMobileApp`, `LorvexVisionApp`, and `LorvexWatchApp` SwiftUI entry targets",
            "XcodeGen drift checks for bundle ids",
            "system entrypoint",
            "release manifest records quality gate verifiers for core service coverage",
            "MCP stdio smoke coverage",
            "Swift MCP tool catalog drift checks",
            "user documentation drift checks",
            "release manifest self-verification",
            "release manifest records install-package quality gate verifiers for Mach-O\ndistribution load paths and codesign\n  entitlements",
            "CloudKit sync readiness drift checks",
            "CloudKit production schema promotion and App Store Connect provisioning remain\nhuman-gated release requirements",
            "The release manifest records both the runtime\nCloudKit sync readiness and the separate production release readiness gate",
            "pre-package quality gates for Apple-only strategy, core service coverage,\n  and hotspot limits",
            "shared quality gate verifiers\nfor Apple-only strategy, build matrix coverage, system entrypoints, core service\ncoverage, hotspot limits, MCP client config validation, MCP stdio smoke\ncoverage, Swift MCP tool catalog drift checks, user documentation drift checks,\nMach-O distribution load paths, codesign entitlement checks, and release\nmanifest self-verification",
            "watchOS, Watch complication, Widget, Focus Filter, and shared App Intents targets",
            "rejects AppleDouble sidecar files, `__MACOSX` metadata entries, symlink entries, and entries outside",
            "The archive must contain the app\nexecutable, privacy manifest, bundled MCP helper, and Widget extension files.",
        ],
    },
}


def mcp_tool_catalog_table(text: str) -> str:
    start_match = re.search(r"(?m)^\s*### Tool Catalog\s*$", text)
    if start_match is None:
        return ""
    next_heading = re.search(r"(?m)^\s*###\s+", text[start_match.end() :])
    if next_heading is None:
        return text[start_match.start() :]
    end = start_match.end() + next_heading.start()
    return text[start_match.start() : end]


def mcp_integration_section(text: str) -> str:
    start_match = re.search(r"(?m)^\s*## MCP & AI Integration\s*$", text)
    if start_match is None:
        return ""
    next_heading = re.search(r"(?m)^\s*##\s+", text[start_match.end() :])
    if next_heading is None:
        return text[start_match.start() :]
    end = start_match.end() + next_heading.start()
    return text[start_match.start() : end]


def documented_mcp_tool_examples(text: str) -> set[str]:
    table = mcp_tool_catalog_table(text)
    return set(re.findall(r"`([a-z][a-z0-9_]+)`", table))


def mcp_tool_doc_failures(text: str) -> list[str]:
    tools = documented_mcp_tool_examples(text)
    failures: list[str] = []
    if not tools:
        failures.append("USER_GUIDE MCP tool catalog does not document any tool examples")
    unknown = sorted(tools - EXPECTED_MCP_TOOLS)
    if unknown:
        failures.append(f"USER_GUIDE MCP tool catalog documents unknown tool(s): {unknown}")
    legacy = sorted(tools & LEGACY_MCP_TOOL_NAMES)
    if legacy:
        failures.append(f"USER_GUIDE MCP tool catalog still uses legacy tool name(s): {legacy}")
    integration_section = mcp_integration_section(text)
    legacy_mentions = sorted(
        set(re.findall(r"`([a-z][a-z0-9_]+)`", integration_section)) & LEGACY_MCP_TOOL_NAMES
    )
    if legacy_mentions:
        failures.append(
            f"USER_GUIDE MCP integration section still uses legacy tool name(s): {legacy_mentions}"
        )
    return failures


def contains_phrase(text: str, phrase: str) -> bool:
    if phrase in text:
        return True
    normalized_text = " ".join(text.split())
    normalized_phrase = " ".join(phrase.split())
    return normalized_phrase in normalized_text


def mcp_tool_count_doc_failures(document_texts: dict[Path, str]) -> list[str]:
    expected_count = len(EXPECTED_MCP_TOOLS)
    failures: list[str] = []

    for path, statements in MCP_TOOL_COUNT_PATTERNS.items():
        label = path.relative_to(REPO_ROOT)
        text = document_texts.get(path, "")
        for statement, pattern in statements.items():
            match = pattern.search(text)
            if match is None:
                failures.append(f'MCP tool count statement "{statement}" missing from {label}')
                continue

            documented_count = int(match.group("count"))
            if documented_count != expected_count:
                failures.append(
                    f'MCP tool count statement "{statement}" in {label} is {documented_count}; '
                    f"expected {expected_count} from apps/apple/script/expected_mcp_tools.py"
                )

    return failures


def main() -> int:
    errors: list[str] = []

    for path, checks in CHECKS.items():
        text = path.read_text(encoding="utf-8")
        label = path.relative_to(ROOT)

        for phrase in checks["stale"]:
            if contains_phrase(text, phrase):
                errors.append(f"stale text remains in {label}: {phrase}")

        for phrase in checks["required"]:
            if not contains_phrase(text, phrase):
                errors.append(f"required text missing from {label}: {phrase}")

    errors.extend(mcp_tool_doc_failures(USER_GUIDE.read_text(encoding="utf-8")))
    errors.extend(
        mcp_tool_count_doc_failures(
            {path: path.read_text(encoding="utf-8") for path in MCP_TOOL_COUNT_PATTERNS}
        )
    )

    if errors:
        print("User documentation verification failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print("User documentation verification passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
