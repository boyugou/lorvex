import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

@Test
func menuBarStatusActionsMapToStableNativeCommandActions() {
  #expect(MenuBarStatusAction.openMain.commandAction == .openWindow(.main))
  #expect(MenuBarStatusAction.quit.commandAction == .quitApplication)
}

@Test
func menuBarSecondaryEntriesExposeCompactNativeOrder() {
  #expect(MenuBarStatusAction.openMain.title == "Open Lorvex")
  #expect(MenuBarStatusAction.quit.title == "Quit Lorvex")
}

@MainActor
@Test
func todayAndTheMenuBarPanelReadTheWholeDayWhileAllTasksSearches() async throws {
  let suiteName = "MenuBarStatusViewTests.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defaults.removePersistentDomain(forName: suiteName)
  let store = AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)
  await store.refresh()
  let day = store.today.tasks.filter(\.status.isActionable)
  let target = try #require(day.first)
  #expect(day.count > 1)

  store.selection = .tasks
  store.searchText = target.title

  #expect(Set(store.calmToday.items.map(\.id)) == Set(day.map(\.id)))
}
