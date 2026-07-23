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
VISION_INFO_PLIST = ROOT / "Config" / "LorvexVisionApp-Info.plist"
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
    "read_list_detail": "ReadLorvexListDetailIntent",
    "read_list_health": "ReadLorvexListHealthIntent",
    "update_habit": "UpdateLorvexHabitIntent",
    "delete_habit": "DeleteLorvexHabitIntent",
    "create_habit": "CreateLorvexHabitIntent",
    "create_calendar_event": "CreateLorvexCalendarEventIntent",
    "update_calendar_event": "UpdateLorvexCalendarEventIntent",
    "delete_calendar_event": "DeleteLorvexCalendarEventIntent",
    "read_calendar_timeline": "ReadLorvexCalendarTimelineIntent",
    "search_calendar_events": "SearchLorvexCalendarEventsIntent",
    "link_task_to_provider_event": "LinkLorvexTaskToProviderEventIntent",
    "unlink_task_from_provider_event": "UnlinkLorvexTaskFromProviderEventIntent",
    "read_linked_events_for_task": "ReadLorvexLinkedEventsForTaskIntent",
    "read_linked_tasks_for_event": "ReadLorvexLinkedTasksForEventIntent",
    "complete_habit": "CompleteLorvexHabitIntent",
    "reset_habit": "ResetLorvexHabitIntent",
    "read_habit_completions": "ReadLorvexHabitCompletionsIntent",
    "read_habit_stats": "ReadLorvexHabitStatsIntent",
    "batch_complete_habits": "BatchCompleteLorvexHabitsIntent",
    "read_habit_reminder_policies": "ReadLorvexHabitReminderPoliciesIntent",
    "upsert_habit_reminder_policy": "UpsertLorvexHabitReminderPolicyIntent",
    "delete_habit_reminder_policy": "DeleteLorvexHabitReminderPolicyIntent",
    "focus_task": "AddLorvexTaskToFocusIntent",
    "read_current_focus": "ReadLorvexCurrentFocusIntent",
    "clear_current_focus": "ClearLorvexCurrentFocusIntent",
    "remove_task_from_focus": "RemoveLorvexTaskFromFocusIntent",
    "read_focus_schedule": "ReadLorvexFocusScheduleIntent",
    "propose_focus_schedule": "ProposeLorvexFocusScheduleIntent",
    "save_focus_schedule": "SaveLorvexFocusScheduleIntent",
    "save_daily_review": "SaveLorvexDailyReviewIntent",
    "amend_daily_review": "AmendLorvexDailyReviewIntent",
    "read_review_history": "ReadLorvexReviewHistoryIntent",
    "read_weekly_review": "ReadLorvexWeeklyReviewIntent",
    "save_memory": "SaveLorvexMemoryIntent",
    "read_memory": "ReadLorvexMemoryIntent",
    "delete_memory": "DeleteLorvexMemoryIntent",
    "read_preferences": "ReadLorvexPreferencesIntent",
    "read_preference": "ReadLorvexPreferenceIntent",
    "set_preference": "SetLorvexPreferenceIntent",
    "complete_setup": "CompleteLorvexSetupIntent",
    "read_overview": "ReadLorvexOverviewIntent",
    "read_session_context": "ReadLorvexSessionContextIntent",
    "export_data": "ExportLorvexDataIntent",
    "export_calendar_ics": "ExportLorvexCalendarICSIntent",
    "read_runtime_diagnostics": "ReadLorvexRuntimeDiagnosticsIntent",
    "read_setup_status": "ReadLorvexSetupStatusIntent",
    "read_sync_status": "ReadLorvexSyncStatusIntent",
    "read_ai_changelog": "ReadLorvexAIChangelogIntent",
    "read_recent_logs": "ReadLorvexRecentLogsIntent",
    "read_guide": "ReadLorvexGuideIntent",
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
    if not VISION_INFO_PLIST.is_file():
        failures.append(f"vision Info.plist missing: {VISION_INFO_PLIST}")
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
                    "vision": plist_user_activity_types(VISION_INFO_PLIST),
                },
            )
        )

    if failures:
        print("System entrypoint verification failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    print("System entrypoint verification passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
