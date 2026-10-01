import LorvexCore
import LorvexMobile
import Testing

@Test
func mobileTabsPromotePrimaryDailySurfaces() {
  #expect(MobileTab.allCases == [.today, .tasks, .calendar, .habits, .review])
  #expect(MobileTab.tasks.systemImage == "checklist")
  #expect(MobileTab.today.title == "Today")
}

@Test
func mobileDestinationKeyboardShortcutsCoverEveryExtendedWorkspace() {
  #expect(MobileDestination.tasks.keyboardShortcutKey == "6")
  #expect(MobileDestination.calendar.keyboardShortcutKey == "7")
  #expect(MobileDestination.lists.keyboardShortcutKey == "8")
  #expect(MobileDestination.habits.keyboardShortcutKey == "9")
  #expect(MobileDestination.memory.keyboardShortcutKey == "m")
  #expect(MobileDestination.settings.keyboardShortcutKey == ",")
}
