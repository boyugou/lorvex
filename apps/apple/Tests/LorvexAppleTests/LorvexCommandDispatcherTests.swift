import LorvexCore
import Testing

@testable import LorvexApple

@MainActor
@Test
func commandDispatcherFocusesInlineQuickAddWithoutOpeningWindow() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  store.selection = .calendar
  var opened: [LorvexWindowID] = []
  let dispatcher = LorvexCommandDispatcher(store: store) { windowID in
    opened.append(windowID)
  }
  let before = store.quickAddFocusToken

  dispatcher.perform(AppCommandAction.focusQuickAdd)

  // Capture is inline now: no popup window opens; the action routes to Tasks
  // (Calendar has no quick-add) and bumps the focus token.
  #expect(opened.isEmpty)
  #expect(store.selection == .tasks)
  #expect(store.quickAddFocusToken == before + 1)
}

@MainActor
@Test
func commandDispatcherOpensTaskDetailForTaskCommand() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  store.selectedTaskID = try #require(store.today.tasks.first?.id)
  var opened: [LorvexWindowID] = []
  let dispatcher = LorvexCommandDispatcher(store: store) { windowID in
    opened.append(windowID)
  }

  dispatcher.perform(TaskCommandAction.openTaskDetail)

  #expect(opened == [.taskDetail])
}

@MainActor
@Test
func commandDispatcherRunsToolbarWindowActions() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  var opened: [LorvexWindowID] = []
  let dispatcher = LorvexCommandDispatcher(store: store) { windowID in
    opened.append(windowID)
  }

  dispatcher.perform(MainToolbarCommandAction.openWindow(.today))
  dispatcher.perform(MainToolbarCommandAction.appCommand(.focusQuickAdd))

  // The window-opening toolbar action still opens Today; the focus-quick-add
  // app command opens no window (capture is inline).
  #expect(opened == [.today])
}

@MainActor
@Test
func commandDispatcherActivatesMenuBarWindowActionsAndQuits() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  store.selectedTaskID = try #require(store.today.tasks.first?.id)
  var opened: [LorvexWindowID] = []
  var activateCount = 0
  var terminateCount = 0
  let dispatcher = LorvexCommandDispatcher(
    store: store,
    openWindow: { windowID in opened.append(windowID) },
    activateApplication: { activateCount += 1 },
    terminateApplication: { terminateCount += 1 }
  )

  dispatcher.perform(MenuBarStatusCommandAction.openWindow(.today))
  dispatcher.perform(MenuBarStatusCommandAction.taskCommand(.openTaskDetail))
  dispatcher.perform(MenuBarStatusCommandAction.appCommand(.focusQuickAdd))
  dispatcher.perform(MenuBarStatusCommandAction.quitApplication)

  // Focus-quick-add opens no window but still brings the app forward so the
  // newly focused inline field is visible (so three activations, two windows).
  #expect(opened == [.today, .taskDetail])
  #expect(activateCount == 3)
  #expect(terminateCount == 1)
}

@MainActor
@Test
func commandDispatcherRoutesByExplicitFocusedSurface() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  let tasks = store.today.tasks.filter { $0.status.isActive }
  let rootTask = try #require(tasks.first)
  let focusedTask = try #require(tasks.dropFirst().first)
  store.setTaskWorkspaceSelection([rootTask.id])
  store.setFocusWorkspaceSelection([focusedTask.id])
  store.selectedTaskID = rootTask.id
  var openedTaskID: LorvexTask.ID?
  let dispatcher = LorvexCommandDispatcher(store: store) { _ in }

  dispatcher.perform(
    .openTaskDetail,
    selectionSurface: .focus,
    openTaskDetail: { openedTaskID = $0 }
  )

  #expect(openedTaskID == focusedTask.id)
  #expect(store.selectedTaskID == focusedTask.id)
  #expect(store.taskWorkspaceSelectedTaskIDs == [rootTask.id])
}
