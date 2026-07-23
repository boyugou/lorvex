import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

/// Completing a task with an `UndoManager` registers a recoverable undo, and the
/// registered inverse (`reopenTaskForUndo`) restores the task to open — so an
/// accidental complete is recoverable with ⌘Z.
@MainActor
@Test
func completeRegistersReopenUndo() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()
  guard let open = store.today.tasks.first(where: { $0.status == .open }) else {
    Issue.record("seed data had no open task")
    return
  }
  store.selectedTaskID = open.id
  let undoManager = UndoManager()

  await store.completeSelectedTask(undoManager: undoManager)

  // The Today snapshot carries only open tasks, so the completed task leaves
  // it; the store row is the completion evidence.
  #expect(!store.today.tasks.contains { $0.id == open.id })
  #expect(try await core.loadTask(id: open.id).status == .completed)
  #expect(undoManager.canUndo)
  #expect(undoManager.undoActionName == "Complete Task")

  // The registered inverse restores the task to open (and back into Today).
  await store.reopenTaskForUndo(open.id)
  #expect(store.today.tasks.first { $0.id == open.id }?.status == .open)
}

/// Completing without an `UndoManager` (e.g. a menu/keyboard action) registers
/// nothing — the action is a deliberate keystroke, not a recoverable mis-click.
@MainActor
@Test
func completeWithoutUndoManagerRegistersNothing() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()
  guard let open = store.today.tasks.first(where: { $0.status == .open }) else {
    Issue.record("seed data had no open task")
    return
  }
  store.selectedTaskID = open.id
  let undoManager = UndoManager()

  await store.completeSelectedTask(undoManager: nil)

  #expect(!store.today.tasks.contains { $0.id == open.id })
  #expect(try await core.loadTask(id: open.id).status == .completed)
  #expect(!undoManager.canUndo)
}
