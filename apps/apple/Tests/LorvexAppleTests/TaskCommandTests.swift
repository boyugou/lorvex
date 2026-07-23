import LorvexCore
import SwiftUI
import Testing

@testable import LorvexApple

@Test
func taskCommandsExposeNativeMenuTitles() {
  #expect(
    TaskCommand.allCases == [
      .showDetail,
      .save,
      .toggleFocus,
      .deferToTomorrow,
      .complete,
      .reopen,
      .cancel,
    ])
  #expect(TaskCommand.showDetail.title == "Show Task Detail")
  #expect(TaskCommand.save.title == "Save Task")
  #expect(TaskCommand.toggleFocus.title(isFocused: false) == "Add to Focus")
  #expect(TaskCommand.toggleFocus.title(isFocused: true) == "Remove from Focus")
  #expect(TaskCommand.deferToTomorrow.title == "Defer to Tomorrow")
  #expect(TaskCommand.complete.title == "Complete Task")
  #expect(TaskCommand.reopen.title == "Reopen Task")
  #expect(TaskCommand.cancel.title == "Cancel Task")
}

@Test
func taskCommandsExposeKeyboardShortcuts() {
  #expect(TaskCommand.showDetail.keyboardShortcut.key == "i")
  #expect(TaskCommand.save.keyboardShortcut.key == "s")
  #expect(TaskCommand.toggleFocus.keyboardShortcut.key == "f")
  #expect(TaskCommand.deferToTomorrow.keyboardShortcut.key == "d")
  #expect(TaskCommand.complete.keyboardShortcut.key == .return)
  #expect(TaskCommand.reopen.keyboardShortcut.key == "o")
  #expect(TaskCommand.cancel.keyboardShortcut.key == .delete)
}

@Test
func taskCommandsMapToStableNativeActions() {
  #expect(TaskCommand.showDetail.action == .openTaskDetail)
  #expect(TaskCommand.save.action == .saveSelectedTaskDraft)
  #expect(TaskCommand.toggleFocus.action == .toggleSelectedTaskFocus)
  #expect(TaskCommand.deferToTomorrow.action == .deferSelectedTask)
  #expect(TaskCommand.complete.action == .completeSelectedTask)
  #expect(TaskCommand.reopen.action == .reopenSelectedTask)
  #expect(TaskCommand.cancel.action == .cancelSelectedTask)
}

@MainActor
@Test
func taskCommandsDisableSelectedTaskActionsWithoutSelection() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  let context = LorvexTaskCommandContext(store: store, selectionSurface: nil)

  for command in TaskCommand.allCases {
    #expect(!command.isEnabled(in: context))
    #expect(!command.isEnabled(in: nil))
  }
}

@MainActor
@Test
func taskCommandsMirrorSelectedTaskState() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())

  await store.refresh()
  store.selectedTaskID = LorvexPreviewSeedID.agendaTask
  let context = LorvexTaskCommandContext(store: store, selectionSurface: nil)

  #expect(TaskCommand.showDetail.isEnabled(in: context))
  #expect(!TaskCommand.save.isEnabled(in: context))
  #expect(TaskCommand.toggleFocus.isEnabled(in: context))
  #expect(TaskCommand.deferToTomorrow.isEnabled(in: context))
  #expect(TaskCommand.complete.isEnabled(in: context))
  #expect(!TaskCommand.reopen.isEnabled(in: context))
  #expect(TaskCommand.cancel.isEnabled(in: context))
}

@MainActor
@Test
func taskCommandsUseFocusedStoreAndExactTaskID() async throws {
  let core = try await makeSeededInMemoryCore()
  let rootStore = AppStore(core: core)
  let focusedStore = AppStore(core: core)
  await rootStore.refresh()
  await focusedStore.refresh()
  let tasks = rootStore.today.tasks
  let rootTask = try #require(tasks.first)
  let focusedTask = try #require(tasks.dropFirst().first)
  rootStore.selectedTaskID = rootTask.id
  focusedStore.selectedTaskID = focusedTask.id
  let context = LorvexTaskCommandContext(store: focusedStore, selectionSurface: nil)
  var openedTaskID: LorvexTask.ID?

  TaskCommand.showDetail.perform(in: context) { openedTaskID = $0 }

  #expect(openedTaskID == focusedTask.id)
  #expect(rootStore.selectedTaskID == rootTask.id)
}

@MainActor
@Test
func taskCommandsEnableBatchActionsFromFocusedSurface() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  let activeIDs = Set(store.today.tasks.filter { $0.status.isActive }.prefix(2).map(\.id))
  #expect(activeIDs.count == 2)
  store.setFocusWorkspaceSelection(activeIDs)
  store.selection = .tasks
  let context = LorvexTaskCommandContext(store: store, selectionSurface: .focus)

  #expect(!TaskCommand.showDetail.isEnabled(in: context))
  #expect(!TaskCommand.toggleFocus.isEnabled(in: context))
  #expect(TaskCommand.complete.isEnabled(in: context))
  #expect(TaskCommand.deferToTomorrow.isEnabled(in: context))
  #expect(TaskCommand.cancel.isEnabled(in: context))
}

@MainActor
@Test
func mainInspectorTaskRemainsCommandTargetWithoutSurfaceSelection() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  let task = try #require(store.today.tasks.first)
  store.setTaskWorkspaceSelection([])
  store.selectedTaskID = task.id
  let context = LorvexTaskCommandContext(
    store: store,
    selectionSurface: .taskWorkspace,
    fallbackTaskID: task.id
  )
  var openedTaskID: LorvexTask.ID?

  #expect(TaskCommand.showDetail.isEnabled(in: context))
  TaskCommand.showDetail.perform(in: context) { openedTaskID = $0 }

  #expect(openedTaskID == task.id)
  #expect(store.taskWorkspaceSelectedTaskIDs == [task.id])
}
