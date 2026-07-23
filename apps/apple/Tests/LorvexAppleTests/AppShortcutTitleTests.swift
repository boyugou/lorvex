import LorvexCore
import LorvexSystemIntents
import SwiftUI
import Testing

@testable import LorvexApple
@testable import LorvexSystemIntents

@Test
func appShortcutsExposeStableShortTitles() {
  #expect(
    LorvexShortcutDescriptor.allCases.map(\.shortTitle) == [
      "Capture Task",
      "Open Lorvex",
      "Overview",
      "Complete Task",
      "Defer Task",
      "Focus Task",
      "List Tasks",
      "Search Tasks",
      "Create Habit",
      "Weekly Review",
    ])
}
