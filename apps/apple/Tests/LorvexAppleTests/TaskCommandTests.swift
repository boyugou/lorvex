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
      .toggleStarted,
      .deferToTomorrow,
      .complete,
      .reopen,
      .cancel,
    ])
  #expect(TaskCommand.showDetail.title == "Show Task Detail")
  #expect(TaskCommand.save.title == "Save Task")
  #expect(TaskCommand.toggleStarted.title(isStarted: false) == "Start Task")
  #expect(TaskCommand.toggleStarted.title(isStarted: true) == "Pause Task")
  #expect(TaskCommand.deferToTomorrow.title == "Defer to Tomorrow")
  #expect(TaskCommand.complete.title == "Complete Task")
  #expect(TaskCommand.reopen.title == "Reopen Task")
  #expect(TaskCommand.cancel.title == "Cancel Task")
}

@Test
func taskCommandsExposeKeyboardShortcuts() {
  #expect(TaskCommand.showDetail.keyboardShortcut.key == "i")
  #expect(TaskCommand.save.keyboardShortcut.key == "s")
  #expect(TaskCommand.toggleStarted.keyboardShortcut.key == "s")
  #expect(TaskCommand.toggleStarted.keyboardShortcut.modifiers == [.command, .shift])
  #expect(TaskCommand.save.keyboardShortcut.modifiers == [.command])
  #expect(TaskCommand.deferToTomorrow.keyboardShortcut.key == "d")
  #expect(TaskCommand.complete.keyboardShortcut.key == .return)
  #expect(TaskCommand.reopen.keyboardShortcut.key == "o")
  #expect(TaskCommand.cancel.keyboardShortcut.key == .delete)
}

@Test
func taskCommandsMapToStableNativeActions() {
  #expect(TaskCommand.showDetail.action == .openTaskDetail)
  #expect(TaskCommand.save.action == .saveSelectedTaskDraft)
  #expect(TaskCommand.toggleStarted.action == .toggleSelectedTaskStarted)
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
  #expect(TaskCommand.toggleStarted.isEnabled(in: context))
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
  store.setTodaySelection(activeIDs)
  store.selection = .tasks
  let context = LorvexTaskCommandContext(store: store, selectionSurface: .today)

  #expect(!TaskCommand.showDetail.isEnabled(in: context))
  #expect(!TaskCommand.toggleStarted.isEnabled(in: context))
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

@Test
func taskPlanDayChoicesCountFromTheLogicalToday() {
  #expect(TaskPlanDayChoice.allCases.map(\.daysFromToday) == [0, 1, 3, 7])
  #expect(TaskPlanDayChoice.allCases.map(\.title) == ["Today", "Tomorrow", "In 3 days", "Next Week"])
}

@MainActor
@Test
func planTaskIsDisabledWithoutASelection() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  let context = LorvexTaskCommandContext(store: store, selectionSurface: nil)

  #expect(!context.canPlanSelection)
}

@MainActor
@Test
func planningTheSelectionPlansEverySelectedOpenTask() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()
  let ids = store.today.tasks.filter { $0.status.isActive }.prefix(2).map(\.id)
  #expect(ids.count == 2)
  store.setTodaySelection(Set(ids))
  store.selection = .tasks
  let context = LorvexTaskCommandContext(store: store, selectionSurface: .today)
  #expect(context.canPlanSelection)

  await context.planSelection(daysFromToday: 1, undoManager: nil)

  let expected = try #require(
    LorvexDateFormatters.ymdUTCAddingDays(store.logicalTodayDateString, days: 1))
  for id in ids {
    let task = try await core.loadTask(id: id)
    #expect(task.plannedDate.map(LorvexDateFormatters.ymdUTC.string(from:)) == expected)
  }
}

@Test
func theTaskMenuOffersPlanTaskForTheSelection() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let commands = try String(
    contentsOf: root.appending(path: "Sources/LorvexApple/App/LorvexAppCommands.swift"),
    encoding: .utf8)
  let plan = try #require(commands.range(of: "Menu(AppStore.planTaskTitle)"))
  let body = commands[plan.upperBound...].prefix(600)
  #expect(body.contains("ForEach(TaskPlanDayChoice.allCases)"))
  #expect(body.contains("taskCommandContext.planSelection("))
  #expect(body.contains("NSApp.keyWindow?.undoManager"))
  #expect(body.contains(".disabled(!(taskCommandContext?.canPlanSelection ?? false))"))
}
