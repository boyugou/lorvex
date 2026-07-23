import Testing

@testable import LorvexApple

@Test
func menuBarStatusActionsMapToStableNativeCommandActions() {
  #expect(MenuBarStatusAction.openMain.commandAction == .openWindow(.main))
  #expect(MenuBarStatusAction.refresh.commandAction == .appCommand(.refreshStore))
  #expect(MenuBarStatusAction.quit.commandAction == .quitApplication)
}

@Test
func menuBarSecondaryEntriesExposeCompactNativeOrder() {
  #expect(MenuBarStatusAction.openMain.title == "Open Lorvex")
  #expect(MenuBarStatusAction.refresh.title == "Refresh")
  #expect(MenuBarStatusAction.quit.title == "Quit Lorvex")
}
