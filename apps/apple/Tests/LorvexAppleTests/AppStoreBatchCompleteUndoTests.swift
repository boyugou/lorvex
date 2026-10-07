import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

// A completion or cancellation started from the menu bar, a keyboard shortcut,
// or a batch menu registers the same ⌘Z reopen as the row controls do.

/// Polls `condition` for up to three seconds. An undo runs its writes in a task
/// of its own, so a test waits for the result rather than for a return.
@MainActor
private func waitUntil(_ condition: () async throws -> Bool) async throws -> Bool {
  for _ in 0..<60 {
    if try await condition() { return true }
    try await Task.sleep(for: .milliseconds(50))
  }
  return false
}

@MainActor
private func allStatuses(
  _ ids: [LorvexTask.ID], in core: any LorvexCoreServicing
) async throws -> [LorvexTask.Status] {
  var statuses: [LorvexTask.Status] = []
  for id in ids { statuses.append(try await core.loadTask(id: id).status) }
  return statuses
}

@MainActor
private func makeStore() async throws -> (store: AppStore, core: any LorvexCoreServicing) {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()
  await store.loadTaskWorkspace()
  return (store, core)
}

@MainActor
@Test
func aBatchCompletionIsUndoneByOneCommandZ() async throws {
  let (store, core) = try await makeStore()
  let ids = Array(store.taskWorkspaceOpenTasks.prefix(3).map(\.id))
  #expect(ids.count >= 2)
  store.setTaskWorkspaceSelection(Set(ids))
  let undoManager = UndoManager()
  undoManager.groupsByEvent = false

  undoManager.beginUndoGrouping()
  await store.completeTaskWorkspaceSelection(undoManager: undoManager)
  undoManager.endUndoGrouping()

  #expect(try await allStatuses(ids, in: core).allSatisfy { $0 == .completed })
  #expect(undoManager.canUndo)
  #expect(undoManager.undoActionName == TaskCommand.complete.title)

  undoManager.undo()
  #expect(
    try await waitUntil { try await allStatuses(ids, in: core).allSatisfy { $0 == .open } })
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func aBatchCompletionWithoutAnUndoManagerRegistersNothing() async throws {
  let (store, core) = try await makeStore()
  let ids = Array(store.taskWorkspaceOpenTasks.prefix(2).map(\.id))
  store.setTaskWorkspaceSelection(Set(ids))

  await store.completeTaskWorkspaceSelection()

  #expect(try await allStatuses(ids, in: core).allSatisfy { $0 == .completed })
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func theCompleteCommandOnOneTaskRegistersAnUndo() async throws {
  let (store, core) = try await makeStore()
  let task = try #require(store.taskWorkspaceOpenTasks.first)
  store.selectOnlyTaskInWorkspace(task.id)
  let undoManager = UndoManager()
  let dispatcher = LorvexCommandDispatcher(store: store, openWindow: { _ in })

  dispatcher.perform(
    .completeSelectedTask, selectionSurface: .taskWorkspace, undoManager: undoManager)
  #expect(
    try await waitUntil { try await core.loadTask(id: task.id).status == .completed })
  #expect(try await waitUntil { undoManager.canUndo })
  #expect(undoManager.undoActionName == TaskCommand.complete.title)

  undoManager.undo()
  #expect(try await waitUntil { try await core.loadTask(id: task.id).status == .open })
}

@MainActor
@Test
func theCompleteCommandOnSeveralTasksRegistersOneUndo() async throws {
  let (store, core) = try await makeStore()
  let ids = Array(store.taskWorkspaceOpenTasks.prefix(2).map(\.id))
  store.setTaskWorkspaceSelection(Set(ids))
  let undoManager = UndoManager()
  let dispatcher = LorvexCommandDispatcher(store: store, openWindow: { _ in })

  dispatcher.perform(
    .completeSelectedTask, selectionSurface: .taskWorkspace, undoManager: undoManager)
  #expect(
    try await waitUntil { try await allStatuses(ids, in: core).allSatisfy { $0 == .completed } })
  #expect(try await waitUntil { undoManager.canUndo })

  undoManager.undo()
  #expect(
    try await waitUntil { try await allStatuses(ids, in: core).allSatisfy { $0 == .open } })
}

@MainActor
@Test
func theCancelCommandOnOneTaskRegistersAnUndo() async throws {
  let (store, core) = try await makeStore()
  let task = try #require(store.taskWorkspaceOpenTasks.first { $0.recurrence == nil })
  store.selectOnlyTaskInWorkspace(task.id)
  let undoManager = UndoManager()
  let dispatcher = LorvexCommandDispatcher(store: store, openWindow: { _ in })

  dispatcher.perform(
    .cancelSelectedTask, selectionSurface: .taskWorkspace, undoManager: undoManager)
  #expect(
    try await waitUntil { try await core.loadTask(id: task.id).status == .cancelled })
  #expect(try await waitUntil { undoManager.canUndo })
  #expect(undoManager.undoActionName == TaskCommand.cancel.title)

  undoManager.undo()
  #expect(try await waitUntil { try await core.loadTask(id: task.id).status == .open })
}

@MainActor
@Test
func theTaskMenuCommandsUseTheKeyWindowsUndoManager() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let command = try String(
    contentsOf: root.appending(path: "Sources/LorvexApple/Support/TaskCommand.swift"),
    encoding: .utf8)
  #expect(command.contains("undoManager: NSApp?.keyWindow?.undoManager"))
}
