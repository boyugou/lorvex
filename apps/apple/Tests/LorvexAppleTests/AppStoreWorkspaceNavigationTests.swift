import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

/// Behavioral coverage for `AppStore.navigateToWorkspace(_:)`, the user-initiated
/// navigation entry point that dismisses a lingering task selection so the detail
/// inspector never carries a task from one workspace into another where it does
/// not belong.
@MainActor
@Test
func navigateToWorkspaceClearsLingeringTaskSelection() async throws {
  let suiteName = "navigateToWorkspaceClearsLingeringTaskSelection.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defaults.removePersistentDomain(forName: suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let store = AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)
  await store.refresh()
  await store.loadTaskWorkspace()

  let task = try #require(store.taskWorkspaceOpenTasks.first)
  store.selectTaskFromList(task.id)
  #expect(store.selectedTaskID == task.id)

  // `.lists` is a task-consumer workspace; the regression was the inspector
  // lingering over the Lists catalog after navigating to it. The selection-
  // clearing `didSet` only fired for non-consumer destinations, so the fix
  // routes user navigation through `navigateToWorkspace`, which clears first.
  store.navigateToWorkspace(.lists)
  #expect(store.selection == .lists)
  #expect(store.selectedTaskID == nil)

  // A non-consumer destination clears the selection as well.
  store.selectTaskFromList(task.id)
  store.navigateToWorkspace(.calendar)
  #expect(store.selection == .calendar)
  #expect(store.selectedTaskID == nil)

  // Navigating to Tasks or Lists additionally drops any active list scope so the
  // catalog opens at its "all" entry point rather than pre-filtered.
  store.setTaskWorkspaceListScope("scope-list-id")
  #expect(store.taskWorkspaceListScopeID == "scope-list-id")
  store.navigateToWorkspace(.lists)
  #expect(store.taskWorkspaceListScopeID == nil)
}
