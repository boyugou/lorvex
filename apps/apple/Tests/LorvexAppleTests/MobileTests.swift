import LorvexCore
import LorvexMobile
import Testing

@Test
func mobileTabsPromotePrimaryDailySurfaces() {
  #expect(MobileTab.allCases == [.today, .tasks, .calendar, .habits, .more])
  #expect(MobileTab.tasks.systemImage == "checklist")
  #expect(MobileTab.today.title == "Today")
}

@Test
func mobileChromeUsesTabsOnCompactAndSidebarOnRegularLayouts() {
  #expect(MobileChromeStyle.preferred(horizontalSizeClass: .compact) == .tabBar)
  #expect(MobileChromeStyle.preferred(horizontalSizeClass: .regular) == .sidebar)

  #if os(visionOS)
    #expect(MobileChromeStyle.preferred(horizontalSizeClass: nil) == .sidebar)
  #else
    #expect(MobileChromeStyle.preferred(horizontalSizeClass: nil) == .tabBar)
  #endif
}

@Test
func mobileShellConfigurationKeepsMobileAndVisionMetadataSeparate() {
  #expect(MobileShellConfiguration.mobile.appDisplayName == MobileAppMetadata.appDisplayName)
  #expect(MobileShellConfiguration.vision.appDisplayName == VisionAppMetadata.appDisplayName)
  #expect(
    MobileShellConfiguration.mobile.preferredChromeStyle(horizontalSizeClass: .compact)
      == .tabBar)
  #expect(
    MobileShellConfiguration.mobile.preferredChromeStyle(horizontalSizeClass: .regular)
      == .sidebar)
  #expect(
    MobileShellConfiguration.vision.preferredChromeStyle(horizontalSizeClass: .compact)
      == .sidebar)
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
