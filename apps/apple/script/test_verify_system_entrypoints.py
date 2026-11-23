#!/usr/bin/env python3
from __future__ import annotations

import unittest

from verify_system_entrypoints import (
    intent_security_failures,
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
                plist_values_by_label={"mobile": activity_types[:1]},
            ),
            [
                "mobile NSUserActivityTypes do not match MobileActivityType order/metadata: "
                "['com.lorvex.apple.openTask'] != "
                "['com.lorvex.apple.openTask', 'com.lorvex.apple.openDestination', "
                "'com.lorvex.apple.openList']"
            ],
        )

    def test_intent_declaring_its_tier_policy_in_its_body_passes(self) -> None:
        sources = {
            "Read.swift": """
struct ReadIntent: LorvexLocalAuthIntent {
  static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
  func perform() async throws -> some IntentResult { .result() }
}
""",
            "Delete.swift": """
@AppIntent(schema: .reminders.deleteReminders)
struct DeleteIntent2: DeleteIntent,
  LorvexAuthenticatedIntent
{
  static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
}
""",
            "Open.swift": """
public struct OpenIntent2: AppIntent, ControlConfigurationIntent {
  public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
}
""",
            "Widget.swift": """
public struct TapIntent: LorvexWidgetActionIntent {
  public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
  public static let isDiscoverable: Bool = false
}
""",
            # Not intents: an entity, a view, and the tier protocol itself.
            "Other.swift": """
struct TaskEntity: AppEntity, Identifiable {
}
struct Row: View {
}
protocol LorvexAuthenticatedIntent: LorvexSecuredIntent {}
""",
        }
        self.assertEqual(intent_security_failures(sources), [])

    def test_intent_relying_on_a_protocol_extension_for_its_policy_fails(self) -> None:
        sources = {
            "Export.swift": """
struct ExportIntent: LorvexLocalAuthIntent {
  static let title: LocalizedStringResource = "Export"
}
""",
        }
        failures = intent_security_failures(sources)
        self.assertEqual(len(failures), 1)
        self.assertIn("Export.swift: ExportIntent must declare", failures[0])

    def test_intent_declaring_another_tiers_policy_fails(self) -> None:
        sources = {
            "Update.swift": """
struct UpdateIntent: LorvexAuthenticatedIntent {
  static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
}
""",
        }
        self.assertEqual(
            intent_security_failures(sources),
            [
                "Update.swift: UpdateIntent names LorvexAuthenticatedIntent but declares "
                ".alwaysAllowed; the tier's policy is .requiresAuthentication"
            ],
        )

    def test_computed_policy_and_discoverable_widget_intent_fail(self) -> None:
        sources = {
            "Computed.swift": """
struct ComputedIntent: AppIntent {
  static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
}
""",
            "Widget.swift": """
public struct TapIntent: LorvexWidgetActionIntent {
  public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
}
""",
        }
        failures = intent_security_failures(sources)
        self.assertEqual(len(failures), 2)
        self.assertIn("ComputedIntent must declare", failures[0])
        self.assertIn("TapIntent is a widget-tap intent", failures[1])

    def test_intent_declarations_in_other_forms_are_checked(self) -> None:
        sources = {
            # An attribute on the declaration's own line.
            "Attribute.swift": """
@available(macOS 27.0, *) struct AttributeIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = "A"
}
""",
            # A type inside another, a generic type, and an actor.
            "Nested.swift": """
enum Namespace {
  struct NestedIntent: AppIntent {
    static let title: LocalizedStringResource = "N"
  }

  struct DeclaredIntent: AppIntent {
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
  }
}
final public class GenericIntent<Value>: AppIntent where Value: Sendable {
}
actor ActorIntent: AppIntent & Sendable {
}
""",
            # The macro alone, with no inheritance clause.
            "Macro.swift": """
@available(macOS 27.0, iOS 27.0, *)
@AppIntent(schema: .reminders.createList)
struct MacroOnly {
}
""",
        }
        failures = intent_security_failures(sources)
        self.assertEqual(
            [failure.split(" must declare")[0] for failure in failures],
            [
                "Attribute.swift: AttributeIntent",
                "Macro.swift: MacroOnly",
                "Nested.swift: NestedIntent",
                "Nested.swift: GenericIntent",
                "Nested.swift: ActorIntent",
            ],
        )

    def test_forms_that_would_hide_an_intent_fail(self) -> None:
        sources = {
            "Extension.swift": """
struct Plain {
}
extension Plain: LorvexAuthenticatedIntent {
  static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
}
""",
            "Protocol.swift": """
protocol Secured: AppIntent {}
struct Hidden: Secured {
}
""",
            "TwoTiers.swift": """
struct TwoTierIntent: LorvexAuthenticatedIntent, LorvexLocalAuthIntent {
  static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
}
""",
        }
        failures = intent_security_failures(sources)
        self.assertEqual(len(failures), 3)
        self.assertIn("an extension gives Plain an App Intent conformance", failures[0])
        self.assertIn("protocol Secured refines an App Intent protocol", failures[1])
        self.assertIn(
            "TwoTierIntent names more than one security tier: "
            "LorvexAuthenticatedIntent, LorvexLocalAuthIntent",
            failures[2],
        )


if __name__ == "__main__":
    unittest.main()
