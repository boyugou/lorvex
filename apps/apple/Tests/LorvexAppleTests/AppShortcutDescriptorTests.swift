import LorvexCore
import LorvexSystemIntents
import SwiftUI
import Testing

@testable import LorvexApple
@testable import LorvexSystemIntents

@Test
func appShortcutsExposeSystemEntrypointsInStableOrder() {
  #expect(
    LorvexShortcutDescriptor.allCases == [
      .captureTask,
      .openLorvex,
      .readOverview,
      .completeTask,
      .deferTask,
      .planTaskForToday,
      .listTasks,
      .searchTasks,
      .createHabit,
      .readWeeklyReview,
    ])
  #expect(LorvexShortcutsProvider.appShortcuts.count == LorvexShortcutDescriptor.allCases.count)
}
