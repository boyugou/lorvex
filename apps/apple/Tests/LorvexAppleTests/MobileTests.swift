import LorvexCore
import LorvexMobile
import Testing

@Test
func mobileTabsPromotePrimaryDailySurfaces() {
  #expect(MobileTab.allCases == [.today, .calendar, .tasks, .review])
  #expect(MobileTab.tasks.systemImage == "checklist")
  #expect(MobileTab.today.title == "Today")
}

/// The four tabs take ⌘1–⌘4 in bar order, so the secondary workspaces follow
/// at ⌘5 and ⌘6, the numbers the Mac sidebar gives Habits and Memory; the
/// destinations a tab's own key opens have none of their own.
@Test
func mobileDestinationKeyboardShortcutsFollowTheTabs() {
  #expect(MobileDestination.habits.keyboardShortcutKey == "5")
  #expect(MobileDestination.memory.keyboardShortcutKey == "6")
  #expect(MobileDestination.settings.keyboardShortcutKey == ",")
  for destination in [MobileDestination.tasks, .calendar, .lists, .review] {
    #expect(destination.keyboardShortcutKey == nil, "\(destination)")
  }
}
