#!/usr/bin/env python3
from __future__ import annotations

import unittest

from verify_system_entrypoints import (
    quick_action_contract_failures,
    script_user_activity_types,
    shortcut_contract_failures,
    shortcut_intent_classes,
    swift_activity_types,
    swift_quick_action_cases,
    user_activity_contract_failures,
)


SWIFT_SOURCE = """
public enum LorvexQuickAction: String, CaseIterable, Sendable {
  case quickCapture = "com.lorvex.apple.quickCapture"
  case openToday = "com.lorvex.apple.openToday"

  public var localizedTitle: String {
    switch self {
    case .quickCapture: "Quick Capture"
    case .openToday: "Open Today"
    }
  }

  public var systemImageName: String {
    switch self {
    case .quickCapture: "square.and.pencil"
    case .openToday: "sun.max"
    }
  }
}
"""

ACTIVITY_SOURCE = """
public enum MobileActivityType {
  public static let openTask = "com.lorvex.apple.openTask"
  public static let openDestination = "com.lorvex.apple.openDestination"
  public static let openList = "com.lorvex.apple.openList"

  public static let all: [String] = [openTask, openDestination, openList]
}
"""

BUILD_SCRIPT_SOURCE = """
cat >"$INFO_PLIST" <<PLIST
  <key>NSUserActivityTypes</key>
  <array>
    <string>com.lorvex.apple.openTask</string>
    <string>com.lorvex.apple.openDestination</string>
    <string>com.lorvex.apple.openList</string>
  </array>
PLIST
"""

SHORTCUTS_SOURCE = """
struct LorvexShortcutsProvider: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(intent: CaptureLorvexTaskIntent(), phrases: [], shortTitle: "Capture Task", systemImageName: "plus")
    AppShortcut(intent: OpenLorvexIntent(destination: .today), phrases: [], shortTitle: "Open Lorvex", systemImageName: "sun.max")
    AppShortcut(intent: OpenLorvexTaskIntent(), phrases: [], shortTitle: "Open Task", systemImageName: "text.badge.magnifyingglass")
  }
}
"""


class VerifySystemEntrypointsTests(unittest.TestCase):
    def test_swift_quick_action_cases_extracts_ordered_metadata(self) -> None:
        self.assertEqual(
            swift_quick_action_cases(SWIFT_SOURCE),
            [
                {
                    "case": "quickCapture",
                    "type": "com.lorvex.apple.quickCapture",
                    "title": "Quick Capture",
                    "symbol": "square.and.pencil",
                },
                {
                    "case": "openToday",
                    "type": "com.lorvex.apple.openToday",
                    "title": "Open Today",
                    "symbol": "sun.max",
                },
            ],
        )

    def test_quick_action_contract_accepts_matching_plist_metadata(self) -> None:
        actions = swift_quick_action_cases(SWIFT_SOURCE)
        plist_actions = [
            {
                "type": "com.lorvex.apple.quickCapture",
                "title": "Quick Capture",
                "symbol": "square.and.pencil",
            },
            {
                "type": "com.lorvex.apple.openToday",
                "title": "Open Today",
                "symbol": "sun.max",
            },
        ]

        self.assertEqual(quick_action_contract_failures(actions, plist_actions), [])

    def test_quick_action_contract_rejects_plist_drift(self) -> None:
        actions = swift_quick_action_cases(SWIFT_SOURCE)

        failures = quick_action_contract_failures(
            actions,
            [
                {
                    "type": "com.lorvex.apple.openToday",
                    "title": "Open Today",
                    "symbol": "sun.max",
                },
            ],
        )

        self.assertEqual(len(failures), 1)
        self.assertIn("UIApplicationShortcutItems do not match LorvexQuickAction", failures[0])

    def test_swift_activity_types_extracts_ordered_values(self) -> None:
        self.assertEqual(
            swift_activity_types(ACTIVITY_SOURCE, "MobileActivityType"),
            [
                "com.lorvex.apple.openTask",
                "com.lorvex.apple.openDestination",
                "com.lorvex.apple.openList",
            ],
        )

    def test_script_user_activity_types_extracts_staged_plist_values(self) -> None:
        self.assertEqual(
            script_user_activity_types(BUILD_SCRIPT_SOURCE),
            [
                "com.lorvex.apple.openTask",
                "com.lorvex.apple.openDestination",
                "com.lorvex.apple.openList",
            ],
        )

    def test_shortcut_intent_classes_extracts_ordered_app_shortcut_intents(self) -> None:
        self.assertEqual(
            shortcut_intent_classes(SHORTCUTS_SOURCE),
            [
                "CaptureLorvexTaskIntent",
                "OpenLorvexIntent",
                "OpenLorvexTaskIntent",
            ],
        )

    def test_shortcut_contract_accepts_matching_release_strategy_actions(self) -> None:
        self.assertEqual(
            shortcut_contract_failures(
                ["capture_task", "open_lorvex", "open_task"],
                SHORTCUTS_SOURCE,
            ),
            [],
        )

    def test_shortcut_contract_rejects_missing_or_reordered_shortcuts(self) -> None:
        failures = shortcut_contract_failures(
            ["open_lorvex", "capture_task"],
            SHORTCUTS_SOURCE,
        )

        self.assertEqual(len(failures), 1)
        self.assertIn("LorvexShortcutsProvider AppShortcut intents", failures[0])

    def test_shortcut_contract_rejects_unmapped_release_strategy_actions(self) -> None:
        failures = shortcut_contract_failures(["capture_task", "archive_task"], SHORTCUTS_SOURCE)

        self.assertEqual(len(failures), 2)
        self.assertEqual(
            failures[0],
            "system intent action has no expected intent mapping: archive_task",
        )

    def test_user_activity_contract_accepts_matching_sources_and_plists(self) -> None:
        activity_types = swift_activity_types(ACTIVITY_SOURCE, "MobileActivityType")

        self.assertEqual(
            user_activity_contract_failures(
                desktop_types=activity_types,
                mobile_types=activity_types,
                plist_values_by_label={
                    "macos staged template": activity_types,
                    "mobile": activity_types,
                    "vision": activity_types,
                },
            ),
            [],
        )

    def test_user_activity_contract_rejects_plist_drift(self) -> None:
        activity_types = swift_activity_types(ACTIVITY_SOURCE, "MobileActivityType")

        self.assertEqual(
            user_activity_contract_failures(
                desktop_types=activity_types,
                mobile_types=activity_types,
                plist_values_by_label={"vision": activity_types[:1]},
            ),
            [
                "vision NSUserActivityTypes do not match MobileActivityType order/metadata: "
                "['com.lorvex.apple.openTask'] != "
                "['com.lorvex.apple.openTask', 'com.lorvex.apple.openDestination', "
                "'com.lorvex.apple.openList']"
            ],
        )


if __name__ == "__main__":
    unittest.main()
