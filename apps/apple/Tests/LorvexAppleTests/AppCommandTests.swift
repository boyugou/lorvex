import LorvexCore
import LorvexSystemIntents
import SwiftUI
import Testing

@testable import LorvexApple
@testable import LorvexSystemIntents

@Test
func appCommandsExposeNativeEntrypointMetadata() {
  #expect(AppCommand.allCases == [.newTask, .refresh])
  #expect(AppCommand.newTask.title == "New Task")
  #expect(AppCommand.newTask.systemImage == "plus.circle")
  #expect(AppCommand.newTask.keyboardShortcut.key == "n")
  #expect(AppCommand.refresh.title == "Refresh")
  #expect(AppCommand.refresh.systemImage == "arrow.clockwise")
  #expect(AppCommand.refresh.keyboardShortcut.key == "r")
}

@Test
func appCommandsMapToStableNativeActions() {
  #expect(AppCommand.newTask.action == .focusQuickAdd)
  #expect(AppCommand.refresh.action == .refreshStore)
}

@MainActor
@Test
func newTaskCommandFocusesInlineQuickAddOnTaskSurface() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  store.selection = .tasks
  let before = store.quickAddFocusToken

  AppCommand.newTask.perform(in: store)

  // Already on a task-bearing surface: focus is signalled in place, no nav.
  #expect(store.selection == .tasks)
  #expect(store.quickAddFocusToken == before + 1)
}

@MainActor
@Test
func newTaskCommandNavigatesToTasksFromNonTaskSurface() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  store.selection = .habits
  let before = store.quickAddFocusToken

  AppCommand.newTask.perform(in: store)

  // No quick-add on Habits: route to Tasks, then signal focus.
  #expect(store.selection == .tasks)
  #expect(store.quickAddFocusToken == before + 1)
}

@MainActor
@Test
func newTaskCommandKeepsTodaySurface() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  store.selection = .today
  let before = store.quickAddFocusToken

  AppCommand.newTask.perform(in: store)

  #expect(store.selection == .today)
  #expect(store.quickAddFocusToken == before + 1)
}

@Test
func appCommandMenusExposeNativeTopLevelOrder() {
  #expect(AppCommandMenu.allCases == [.workspace, .navigate, .task])
  #expect(AppCommandMenu.workspace.title == "Workspace")
  #expect(AppCommandMenu.navigate.title == "Navigate")
  #expect(AppCommandMenu.task.title == "Task")
}
