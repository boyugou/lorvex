#!/usr/bin/env python3
"""Verify native Apple system entrypoint contracts."""

from __future__ import annotations

import plistlib
import re
import sys
from pathlib import Path

from release_strategy import SYSTEM_INTENTS_ACTIONS


ROOT = Path(__file__).resolve().parents[1]
QUICK_ACTION_SOURCE = ROOT / "Sources" / "LorvexCore" / "Support" / "LorvexQuickActions.swift"
DESKTOP_ACTIVITY_SOURCE = ROOT / "Sources" / "LorvexCore" / "Models" / "LorvexActivityType.swift"
MOBILE_ACTIVITY_SOURCE = ROOT / "Sources" / "LorvexMobile" / "MobileActivityType.swift"
SHORTCUTS_PROVIDER_SOURCE = (
    ROOT / "Sources" / "LorvexSystemIntents" / "LorvexShortcutsProvider.swift"
)
# The curated flagship AppShortcuts all live in the single provider source; the
# non-registered App Intents keep their own struct files but no longer declare
# auto-registered shortcut phrases.
SHORTCUTS_PROVIDER_PARTS = [
    SHORTCUTS_PROVIDER_SOURCE,
]
MOBILE_INFO_PLIST = ROOT / "Config" / "LorvexMobileApp-Info.plist"
BUILD_AND_RUN_SCRIPT = ROOT / "script" / "build_and_run.sh"
SYSTEM_INTENT_ACTION_CLASSES = {
    "capture_task": "CaptureLorvexTaskIntent",
    "open_lorvex": "OpenLorvexIntent",
    "open_task": "OpenLorvexTaskIntent",
    "read_task": "ReadLorvexTaskIntent",
    "list_tasks": "ListLorvexTasksIntent",
    "search_tasks": "SearchLorvexTasksIntent",
    "read_deferred_tasks": "ReadLorvexDeferredTasksIntent",
    "read_upcoming_tasks": "ReadLorvexUpcomingTasksIntent",
    "read_dependency_graph": "ReadLorvexDependencyGraphIntent",
    "update_task": "UpdateLorvexTaskIntent",
    "batch_create_tasks": "BatchCreateLorvexTasksIntent",
    "complete_task": "CompleteLorvexTaskIntent",
    "cancel_task": "CancelLorvexTaskIntent",
    "reopen_task": "ReopenLorvexTaskIntent",
    "start_task": "StartLorvexTaskIntent",
    "pause_task": "PauseLorvexTaskIntent",
    "defer_task": "DeferLorvexTaskIntent",
    "append_task_body": "AppendLorvexTaskBodyIntent",
    "set_task_reminders": "SetLorvexTaskRemindersIntent",
    "set_task_recurrence": "SetLorvexTaskRecurrenceIntent",
    "remove_task_recurrence": "RemoveLorvexTaskRecurrenceIntent",
    "add_task_recurrence_exception": "AddLorvexTaskRecurrenceExceptionIntent",
    "remove_task_recurrence_exception": "RemoveLorvexTaskRecurrenceExceptionIntent",
    "add_task_checklist_item": "AddLorvexChecklistItemIntent",
    "toggle_task_checklist_item": "ToggleLorvexChecklistItemIntent",
    "update_task_checklist_item": "UpdateLorvexChecklistItemIntent",
    "remove_task_checklist_item": "RemoveLorvexChecklistItemIntent",
    "batch_complete_tasks": "BatchCompleteLorvexTasksIntent",
    "batch_reopen_tasks": "BatchReopenLorvexTasksIntent",
    "batch_defer_tasks": "BatchDeferLorvexTasksIntent",
    "batch_move_tasks": "BatchMoveLorvexTasksIntent",
    "add_task_reminder": "AddLorvexTaskReminderIntent",
    "remove_task_reminder": "RemoveLorvexTaskReminderIntent",
    "read_due_task_reminders": "ReadLorvexDueTaskRemindersIntent",
    "read_upcoming_task_reminders": "ReadLorvexUpcomingTaskRemindersIntent",
    "create_list": "CreateLorvexListIntent",
    "update_list": "UpdateLorvexListIntent",
    "delete_list": "DeleteLorvexListIntent",
    "list_tags": "ListLorvexTagsIntent",
    "rename_tag": "RenameLorvexTagIntent",
    "find_tasks_by_tag": "FindLorvexTasksByTagIntent",
    "read_lists": "ReadLorvexListsIntent",
    "read_list_health": "ReadLorvexListHealthIntent",
    "update_habit": "UpdateLorvexHabitIntent",
    "delete_habit": "DeleteLorvexHabitIntent",
    "create_habit": "CreateLorvexHabitIntent",
    "create_calendar_event": "CreateLorvexCalendarEventIntent",
    "update_calendar_event": "UpdateLorvexCalendarEventIntent",
    "delete_calendar_event": "DeleteLorvexCalendarEventIntent",
    "read_calendar_timeline": "ReadLorvexCalendarTimelineIntent",
    "search_calendar_events": "SearchLorvexCalendarEventsIntent",
    "read_linked_events_for_task": "ReadLorvexLinkedEventsForTaskIntent",
    "read_linked_tasks_for_event": "ReadLorvexLinkedTasksForEventIntent",
    "complete_habit": "CompleteLorvexHabitIntent",
    "reset_habit": "ResetLorvexHabitIntent",
    "skip_habit": "SkipLorvexHabitIntent",
    "unskip_habit": "UnskipLorvexHabitIntent",
    "read_habit_completions": "ReadLorvexHabitCompletionsIntent",
    "read_habit_stats": "ReadLorvexHabitStatsIntent",
    "batch_complete_habits": "BatchCompleteLorvexHabitsIntent",
    "read_habit_reminders": "ReadLorvexHabitRemindersIntent",
    "add_habit_reminder": "AddLorvexHabitReminderIntent",
    "update_habit_reminder": "UpdateLorvexHabitReminderIntent",
    "delete_habit_reminder": "DeleteLorvexHabitReminderIntent",
    "plan_task_for_today": "PlanLorvexTaskForTodayIntent",
    "read_day_times": "ReadLorvexDayTimesIntent",
    "propose_day_times": "ProposeLorvexDayTimesIntent",
    "save_day_times": "SaveLorvexDayTimesIntent",
    "save_daily_review": "SaveLorvexDailyReviewIntent",
    "amend_daily_review": "AmendLorvexDailyReviewIntent",
    "read_review_history": "ReadLorvexReviewHistoryIntent",
    "read_weekly_review": "ReadLorvexWeeklyReviewIntent",
    "save_memory": "SaveLorvexMemoryIntent",
    "read_memory": "ReadLorvexMemoryIntent",
    "delete_memory": "DeleteLorvexMemoryIntent",
    "complete_setup": "CompleteLorvexSetupIntent",
    "read_overview": "ReadLorvexOverviewIntent",
    "export_data": "ExportLorvexDataIntent",
    "export_calendar_ics": "ExportLorvexCalendarICSIntent",
}


def swift_quick_action_cases(source: str) -> list[dict[str, str]]:
    case_matches = re.findall(r'case\s+(\w+)\s*=\s*"([^"]+)"', source)
    titles = switch_values(source, "localizedTitle")
    symbols = switch_values(source, "systemImageName")
    return [
        {
            "case": case_name,
            "type": type_identifier,
            "title": titles.get(case_name, ""),
            "symbol": symbols.get(case_name, ""),
        }
        for case_name, type_identifier in case_matches
    ]


def switch_values(source: str, property_name: str) -> dict[str, str]:
    property_match = re.search(
        rf"var\s+{property_name}\s*:\s*String\s*\{{(?P<body>.*?)\n\s*\}}",
        source,
        flags=re.DOTALL,
    )
    if property_match is None:
        return {}
    body = property_match.group("body")
    return {
        case_name: value
        for case_name, value in re.findall(r'case\s+\.(\w+):\s*"([^"]+)"', body)
    }


def plist_quick_actions(path: Path = MOBILE_INFO_PLIST) -> list[dict[str, str]]:
    with path.open("rb") as file:
        plist = plistlib.load(file)
    items = plist.get("UIApplicationShortcutItems", [])
    return [
        {
            "type": str(item.get("UIApplicationShortcutItemType", "")),
            "title": str(item.get("UIApplicationShortcutItemTitle", "")),
            "symbol": str(item.get("UIApplicationShortcutItemIconSymbolName", "")),
        }
        for item in items
        if isinstance(item, dict)
    ]


def swift_activity_types(
    source: str, type_name: str, resolver: dict[str, str] | None = None
) -> list[str]:
    """Extracts the activity-type string values declared by `type_name`.

    Each `static let X = …` is read in declaration order. A string-literal value
    is taken verbatim; a reference value of the form `OtherEnum.case` is resolved
    through `resolver` (case name → string), so an enum that re-exports another's
    constants (e.g. `MobileActivityType` over `LorvexActivityType`) reports the
    underlying strings. The `all:` aggregate property is ignored.
    """
    type_match = re.search(
        rf"\benum\s+{re.escape(type_name)}\s*\{{(?P<body>.*?)\n\}}",
        source,
        flags=re.DOTALL,
    )
    if type_match is None:
        return []
    values: list[str] = []
    for name, rhs in re.findall(
        r"(?:public\s+)?static\s+let\s+(\w+)\s*(?::[^=]+)?=\s*([^\n]+)",
        type_match.group("body"),
    ):
        if name == "all":
            continue
        rhs = rhs.strip()
        literal = re.match(r'"([^"]+)"', rhs)
        if literal is not None:
            values.append(literal.group(1))
            continue
        reference = re.match(r"\w+\.(\w+)$", rhs)
        if reference is not None and resolver is not None:
            resolved = resolver.get(reference.group(1))
            if resolved is not None:
                values.append(resolved)
    return values


def swift_activity_case_names(source: str, type_name: str) -> list[str]:
    """Returns the `static let` names (excluding `all`) declared by `type_name`,
    in declaration order — the keys that pair with `swift_activity_types`."""
    type_match = re.search(
        rf"\benum\s+{re.escape(type_name)}\s*\{{(?P<body>.*?)\n\}}",
        source,
        flags=re.DOTALL,
    )
    if type_match is None:
        return []
    names: list[str] = []
    for name, rhs in re.findall(
        r"(?:public\s+)?static\s+let\s+(\w+)\s*(?::[^=]+)?=\s*([^\n]+)",
        type_match.group("body"),
    ):
        if name == "all":
            continue
        rhs = rhs.strip()
        if re.match(r'"[^"]+"', rhs) or re.match(r"\w+\.\w+$", rhs):
            names.append(name)
    return names


def plist_user_activity_types(path: Path) -> list[str]:
    with path.open("rb") as file:
        plist = plistlib.load(file)
    return [str(item) for item in plist.get("NSUserActivityTypes", [])]


def script_user_activity_types(source: str) -> list[str]:
    activity_match = re.search(
        r"<key>NSUserActivityTypes</key>\s*<array>(?P<body>.*?)</array>",
        source,
        flags=re.DOTALL,
    )
    if activity_match is None:
        return []
    return re.findall(r"<string>([^<]+)</string>", activity_match.group("body"))


def shortcut_intent_classes(source: str) -> list[str]:
    return re.findall(r"AppShortcut\s*\(\s*intent:\s*(\w+Intent)\s*\(", source)


def shortcuts_provider_source() -> str:
    return "\n".join(path.read_text(encoding="utf-8") for path in SHORTCUTS_PROVIDER_PARTS)


def quick_action_contract_failures(
    swift_actions: list[dict[str, str]],
    plist_actions: list[dict[str, str]],
) -> list[str]:
    failures: list[str] = []
    if not swift_actions:
        failures.append("LorvexQuickAction declares no cases")
    for action in swift_actions:
        for key in ["type", "title", "symbol"]:
            if not action.get(key):
                failures.append(f"{action.get('case', '<unknown>')} quick action missing {key}")

    comparable_swift = [
        {"type": action["type"], "title": action["title"], "symbol": action["symbol"]}
        for action in swift_actions
    ]
    if comparable_swift != plist_actions:
        failures.append(
            "UIApplicationShortcutItems do not match LorvexQuickAction order/metadata: "
            f"{plist_actions!r} != {comparable_swift!r}"
        )
    return failures


def shortcut_contract_failures(
    actions: list[str],
    shortcuts_source: str,
    action_intent_classes: dict[str, str] = SYSTEM_INTENT_ACTION_CLASSES,
) -> list[str]:
    failures: list[str] = []
    expected_intents: list[str] = []
    for action in actions:
        intent_class = action_intent_classes.get(action)
        if intent_class is None:
            failures.append(f"system intent action has no expected intent mapping: {action}")
        else:
            expected_intents.append(intent_class)

    actual_intents = shortcut_intent_classes(shortcuts_source)
    if actual_intents != expected_intents:
        failures.append(
            "LorvexShortcutsProvider AppShortcut intents do not match release strategy "
            f"actions/order: {actual_intents!r} != {expected_intents!r}"
        )
    return failures


def user_activity_contract_failures(
    desktop_types: list[str],
    mobile_types: list[str],
    plist_values_by_label: dict[str, list[str]],
) -> list[str]:
    failures: list[str] = []
    if not desktop_types:
        failures.append("LorvexActivityType declares no activity types")
    if not mobile_types:
        failures.append("MobileActivityType declares no activity types")
    if desktop_types != mobile_types:
        failures.append(
            "MobileActivityType does not match LorvexActivityType order/metadata: "
            f"{mobile_types!r} != {desktop_types!r}"
        )
    for label, plist_values in plist_values_by_label.items():
        if plist_values != mobile_types:
            failures.append(
                f"{label} NSUserActivityTypes do not match MobileActivityType order/metadata: "
                f"{plist_values!r} != {mobile_types!r}"
            )
    return failures


# The policy each security tier protocol stands for. An intent that names a
# tier declares that policy in its own body.
INTENT_TIER_POLICIES = {
    "LorvexUnauthenticatedIntent": ".alwaysAllowed",
    "LorvexAuthenticatedIntent": ".requiresAuthentication",
    "LorvexLocalAuthIntent": ".requiresLocalDeviceAuthentication",
    "LorvexWidgetActionIntent": ".alwaysAllowed",
}
# A type, extension or protocol declaration with its inheritance clause. The
# declaration may be indented, generic, and carry attributes on its own line
# or on the lines before it.
INTENT_DECLARATION = re.compile(
    r"^(?P<indent>[ \t]*)(?P<attributes>(?:@\w+(?:\([^)\n]*\))?\s+)*)"
    r"(?:(?:public|package|internal|fileprivate|private|open|final|nonisolated)\s+)*"
    r"(?P<kind>struct|class|actor|enum|extension|protocol)\s+(?P<name>[\w.]+)\s*"
    r"(?:<[^>{]*>)?\s*(?::(?P<inherits>[^{]*))?\{",
    re.MULTILINE,
)
INTENT_POLICY = re.compile(
    r"^\s*(?:public )?static let authenticationPolicy: IntentAuthenticationPolicy = (\.\w+)\s*$",
    re.MULTILINE,
)
INTENT_UNDISCOVERABLE = re.compile(
    r"^\s*(?:public )?static let isDiscoverable: Bool = false\s*$", re.MULTILINE
)


def inherited_names(inherits: str | None) -> list[str]:
    """The names in a declaration's inheritance clause, without its `where` part."""
    if not inherits:
        return []
    return re.findall(r"[A-Za-z_][\w.]*", re.split(r"\bwhere\b", inherits)[0])


def intent_security_failures(sources: dict[str, str]) -> list[str]:
    """The App Intent types in `sources` (path to Swift text) whose own body does
    not declare the authentication policy the build can read.

    The build's App Intents metadata step reads only what a type declares itself,
    as a `static let` with a literal value. A policy supplied by a protocol
    extension never reaches the metadata, which then records the intent as
    allowed on a locked device. So every type that conforms to a protocol named
    `...Intent`, or carries the `@AppIntent` macro, must declare
    `authenticationPolicy` in its body; one that names a security tier must name
    only one and declare that tier's policy; and a widget-tap intent must also
    declare itself not discoverable.

    Two forms would hide an intent from this check, so both fail: a conformance
    added in an extension, and a protocol that refines an intent protocol under
    a name that does not end in `Intent`. This is a check of source text: the
    Mac build's metadata step, which fails when an action reaches the metadata
    without a declared policy, covers a form this does not read.
    """
    failures: list[str] = []
    for path, source in sorted(sources.items()):
        for match in INTENT_DECLARATION.finditer(source):
            inherits = inherited_names(match.group("inherits"))
            names_intent = any(token.endswith("Intent") for token in inherits)
            kind = match.group("kind")
            name = match.group("name")
            if kind == "protocol":
                if names_intent and not name.endswith("Intent"):
                    failures.append(
                        f"{path}: protocol {name} refines an App Intent protocol; name it "
                        "`...Intent` so the types that conform to it are checked"
                    )
                continue
            if kind == "extension":
                if names_intent:
                    failures.append(
                        f"{path}: an extension gives {name} an App Intent conformance; "
                        "declare it on the type, where its authentication policy is checked"
                    )
                continue
            if not names_intent and "@AppIntent(" not in match.group("attributes"):
                continue
            end = source.find(f"\n{match.group('indent')}}}", match.end())
            body = source[match.end(): end if end != -1 else len(source)]
            declared = INTENT_POLICY.findall(body)
            if len(declared) != 1:
                failures.append(
                    f"{path}: {name} must declare `static let authenticationPolicy: "
                    "IntentAuthenticationPolicy = ...` once in its own body"
                )
                continue
            tiers = [token for token in inherits if token in INTENT_TIER_POLICIES]
            if len(tiers) > 1:
                failures.append(
                    f"{path}: {name} names more than one security tier: {', '.join(tiers)}"
                )
                continue
            tier = tiers[0] if tiers else None
            if tier and declared[0] != INTENT_TIER_POLICIES[tier]:
                failures.append(
                    f"{path}: {name} names {tier} but declares {declared[0]}; "
                    f"the tier's policy is {INTENT_TIER_POLICIES[tier]}"
                )
            if tier == "LorvexWidgetActionIntent" and not INTENT_UNDISCOVERABLE.search(body):
                failures.append(
                    f"{path}: {name} is a widget-tap intent and must declare "
                    "`static let isDiscoverable: Bool = false` in its own body"
                )
    return failures


def swift_sources(root: Path = ROOT / "Sources") -> dict[str, str]:
    return {
        str(path.relative_to(ROOT)): path.read_text(encoding="utf-8")
        for path in sorted(root.rglob("*.swift"))
    }


def main() -> int:
    failures: list[str] = []
    if not QUICK_ACTION_SOURCE.is_file():
        failures.append(f"quick action source missing: {QUICK_ACTION_SOURCE}")
    if not DESKTOP_ACTIVITY_SOURCE.is_file():
        failures.append(f"desktop activity source missing: {DESKTOP_ACTIVITY_SOURCE}")
    if not MOBILE_ACTIVITY_SOURCE.is_file():
        failures.append(f"mobile activity source missing: {MOBILE_ACTIVITY_SOURCE}")
    if not MOBILE_INFO_PLIST.is_file():
        failures.append(f"mobile Info.plist missing: {MOBILE_INFO_PLIST}")
    if not SHORTCUTS_PROVIDER_SOURCE.is_file():
        failures.append(f"shortcuts provider source missing: {SHORTCUTS_PROVIDER_SOURCE}")
    for path in SHORTCUTS_PROVIDER_PARTS:
        if not path.is_file():
            failures.append(f"shortcuts provider part missing: {path}")
    if not BUILD_AND_RUN_SCRIPT.is_file():
        failures.append(f"build script missing: {BUILD_AND_RUN_SCRIPT}")

    if not failures:
        swift_actions = swift_quick_action_cases(QUICK_ACTION_SOURCE.read_text(encoding="utf-8"))
        plist_actions = plist_quick_actions(MOBILE_INFO_PLIST)
        failures.extend(quick_action_contract_failures(swift_actions, plist_actions))
        failures.extend(
            shortcut_contract_failures(
                SYSTEM_INTENTS_ACTIONS,
                shortcuts_provider_source(),
            )
        )
        desktop_source = DESKTOP_ACTIVITY_SOURCE.read_text(encoding="utf-8")
        desktop_types = swift_activity_types(desktop_source, "LorvexActivityType")
        desktop_case_values = dict(
            zip(swift_activity_case_names(desktop_source, "LorvexActivityType"), desktop_types)
        )
        mobile_types = swift_activity_types(
            MOBILE_ACTIVITY_SOURCE.read_text(encoding="utf-8"),
            "MobileActivityType",
            resolver=desktop_case_values,
        )
        failures.extend(
            user_activity_contract_failures(
                desktop_types,
                mobile_types,
                {
                    "macos staged template": script_user_activity_types(
                        BUILD_AND_RUN_SCRIPT.read_text(encoding="utf-8")
                    ),
                    "mobile": plist_user_activity_types(MOBILE_INFO_PLIST),
                },
            )
        )

    failures.extend(intent_security_failures(swift_sources()))

    if failures:
        print("System entrypoint verification failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    print("System entrypoint verification passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
