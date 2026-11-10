import Foundation
import Testing

@testable import LorvexApple
@testable import LorvexCore

/// The inspector autosaves once typing pauses. These pin what happens to
/// edits made inside that pause when the selection leaves their task.

@MainActor
private func makeDraftHandOffStore() async throws -> (AppStore, any LorvexCoreServicing) {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()
  return (store, core)
}

@MainActor
@Test("a note typed and left at once by opening another row is saved")
func openingAnotherRowSavesTheDraftLeftBehind() async throws {
  let (store, core) = try await makeDraftHandOffStore()
  let first = try #require(store.today.tasks.first)
  let second = try #require(store.today.tasks.dropFirst().first)
  store.selectTaskFromList(first.id)
  await store.loadSelectedTaskDetail()
  store.taskDetailNotes = "Typed and left at once"

  store.selectTaskFromList(second.id)
  await store.waitForLeftBehindDraftWrites()

  #expect(try await core.loadTask(id: first.id).notes == "Typed and left at once")
  #expect(store.selectedTaskID == second.id)
  #expect(store.taskDetailDraftTaskID == second.id)
  #expect(store.taskDetailNotes == second.notes)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test("a note typed and left at once by closing the inspector is saved")
func closingTheInspectorSavesTheDraftLeftBehind() async throws {
  let (store, core) = try await makeDraftHandOffStore()
  let task = try #require(store.today.tasks.first)
  store.selectTaskFromList(task.id)
  await store.loadSelectedTaskDetail()
  store.taskDetailTitle = "Retitled, then closed"
  store.taskDetailNotes = "Typed, then closed"

  #expect(store.dismissOpenInspector())
  await store.waitForLeftBehindDraftWrites()

  let stored = try await core.loadTask(id: task.id)
  #expect(stored.title == "Retitled, then closed")
  #expect(stored.notes == "Typed, then closed")
  #expect(store.selectedTaskID == nil)
}

@MainActor
@Test("moving to a workspace without a task inspector saves the draft left behind")
func leavingTheWorkspaceSavesTheDraftLeftBehind() async throws {
  let (store, core) = try await makeDraftHandOffStore()
  let task = try #require(store.today.tasks.first)
  store.selectTaskFromList(task.id)
  await store.loadSelectedTaskDetail()
  store.taskDetailNotes = "Typed, then off to Habits"

  store.selection = .habits
  await store.waitForLeftBehindDraftWrites()

  #expect(try await core.loadTask(id: task.id).notes == "Typed, then off to Habits")
}

@MainActor
@Test("a checklist row's edited text is saved when the selection leaves the task")
func leavingATaskSavesItsEditedChecklistRow() async throws {
  let (store, core) = try await makeDraftHandOffStore()
  let first = try #require(store.today.tasks.first)
  let second = try #require(store.today.tasks.dropFirst().first)
  let withItem = try await core.addTaskChecklistItem(taskID: first.id, text: "Pack the bag")
  let item = try #require(withItem.checklistItems.first)
  await store.refresh()
  store.selectTaskFromList(first.id)
  await store.loadSelectedTaskDetail()
  store.taskDetailChecklistDrafts[item.id] = "Pack the big bag"

  store.selectTaskFromList(second.id)
  await store.waitForLeftBehindDraftWrites()

  let stored = try await core.loadTask(id: first.id)
  #expect(stored.checklistItems.first?.text == "Pack the big bag")
}

@MainActor
@Test("leaving a task whose title was emptied saves its other edits and keeps the title")
func leavingWithAnEmptiedTitleSavesTheOtherEdits() async throws {
  let (store, core) = try await makeDraftHandOffStore()
  let first = try #require(store.today.tasks.first)
  let second = try #require(store.today.tasks.dropFirst().first)
  store.selectTaskFromList(first.id)
  await store.loadSelectedTaskDetail()
  store.taskDetailTitle = "   "
  store.taskDetailNotes = "Kept although the title was cleared"

  store.selectTaskFromList(second.id)
  await store.waitForLeftBehindDraftWrites()

  let stored = try await core.loadTask(id: first.id)
  #expect(stored.title == first.title)
  #expect(stored.notes == "Kept although the title was cleared")
  #expect(store.errorMessage == nil)
}

@MainActor
@Test("an untouched draft writes nothing when the selection leaves its task")
func leavingAnUntouchedDraftWritesNothing() async throws {
  let (store, core) = try await makeDraftHandOffStore()
  let first = try #require(store.today.tasks.first)
  let second = try #require(store.today.tasks.dropFirst().first)
  store.selectTaskFromList(first.id)
  await store.loadSelectedTaskDetail()
  let before = try await core.loadTask(id: first.id)

  store.selectTaskFromList(second.id)

  #expect(store.leftBehindDraftWrites.isEmpty)
  #expect(try await core.loadTask(id: first.id) == before)
}

@MainActor
@Test("a draft that cannot be saved returns to the editor once, with its text")
func aFailedWriteReturnsTheDraftToTheEditorOnce() async throws {
  let (store, core) = try await makeDraftHandOffStore()
  let first = try #require(store.today.tasks.first)
  let second = try #require(store.today.tasks.dropFirst().first)
  let tooLong = String(repeating: "n", count: 50_001)
  store.selectTaskFromList(first.id)
  await store.loadSelectedTaskDetail()
  store.taskDetailNotes = tooLong

  store.selectTaskFromList(second.id)
  await store.waitForLeftBehindDraftWrites()

  // The write was refused: the editor is back on the task with what was typed.
  #expect(try await core.loadTask(id: first.id).notes == first.notes)
  #expect(store.selectedTaskID == first.id)
  #expect(store.taskDetailDraftTaskID == first.id)
  #expect(store.taskDetailNotes == tooLong)
  #expect(store.errorMessage != nil)

  // Leaving again with the same text is the user's choice: it is not undone.
  store.selectTaskFromList(second.id)
  await store.waitForLeftBehindDraftWrites()
  #expect(store.selectedTaskID == second.id)
  #expect(store.taskDetailDraftTaskID == second.id)
}

@MainActor
@Test("Start, Pause, and Reopen keep a note typed in the inspector")
func statusActionsKeepTheTypedDraft() async throws {
  let (store, core) = try await makeDraftHandOffStore()
  let task = try #require(store.today.tasks.first { $0.status == .open })
  store.selectTaskFromList(task.id)
  await store.loadSelectedTaskDetail()

  store.taskDetailNotes = "Typed before Start"
  await store.startSelectedTask()
  #expect(try await core.loadTask(id: task.id).status == .inProgress)
  #expect(store.taskDetailNotes == "Typed before Start")

  store.taskDetailNotes = "Typed before Pause"
  await store.pauseSelectedTask()
  #expect(try await core.loadTask(id: task.id).status == .open)
  #expect(store.taskDetailNotes == "Typed before Pause")

  _ = try await core.completeTask(id: task.id)
  await store.refresh()
  store.selectedTaskID = task.id
  await store.loadSelectedTaskDetail()
  store.taskDetailNotes = "Typed before Reopen"
  await store.reopenSelectedTask()
  #expect(try await core.loadTask(id: task.id).status == .open)
  #expect(store.taskDetailNotes == "Typed before Reopen")
}

@MainActor
@Test("a clean inspector takes the new status after Start")
func aCleanInspectorAdoptsTheStatusChange() async throws {
  let (store, _) = try await makeDraftHandOffStore()
  let task = try #require(store.today.tasks.first { $0.status == .open })
  store.selectTaskFromList(task.id)
  await store.loadSelectedTaskDetail()

  await store.startSelectedTask()

  #expect(store.selectedTask?.status == .inProgress)
  #expect(store.taskDetailDraftTaskID == task.id)
  #expect(!store.selectedTaskHasUnsavedEditorState)
}

@MainActor
@Test("Quit does not wait for a title that was only emptied, and saves the rest")
func quitSavesAroundAnEmptiedTitle() async throws {
  let (store, core) = try await makeDraftHandOffStore()
  let task = try #require(store.today.tasks.first)
  store.selectTaskFromList(task.id)
  await store.loadSelectedTaskDetail()

  store.taskDetailTitle = ""
  #expect(!store.hasPendingAutosaveDraftForTermination)

  store.taskDetailNotes = "Saved at Quit beside an empty title"
  #expect(store.hasPendingAutosaveDraftForTermination)
  #expect(await store.flushPendingAutosaveDraftsForTermination())

  let stored = try await core.loadTask(id: task.id)
  #expect(stored.title == task.title)
  #expect(stored.notes == "Saved at Quit beside an empty title")
}

@MainActor
@Test("Quit waits for edits a selection change handed to the store")
func quitWaitsForTheDraftLeftBehind() async throws {
  let (store, core) = try await makeDraftHandOffStore()
  let task = try #require(store.today.tasks.first)
  store.selectTaskFromList(task.id)
  await store.loadSelectedTaskDetail()
  store.taskDetailNotes = "Closed, then Quit"

  store.dismissOpenInspector()
  #expect(store.hasPendingAutosaveDraftForTermination)
  #expect(await store.flushPendingAutosaveDraftsForTermination())

  #expect(try await core.loadTask(id: task.id).notes == "Closed, then Quit")
}

@MainActor
@Test("Quit saves a checklist row's edited text")
func quitSavesAnEditedChecklistRow() async throws {
  let (store, core) = try await makeDraftHandOffStore()
  let task = try #require(store.today.tasks.first)
  let withItem = try await core.addTaskChecklistItem(taskID: task.id, text: "Call the venue")
  let item = try #require(withItem.checklistItems.first)
  await store.refresh()
  store.selectTaskFromList(task.id)
  await store.loadSelectedTaskDetail()
  store.taskDetailChecklistDrafts[item.id] = "Call the venue back"

  #expect(store.hasPendingAutosaveDraftForTermination)
  #expect(await store.flushPendingAutosaveDraftsForTermination())

  #expect(
    try await core.loadTask(id: task.id).checklistItems.first?.text == "Call the venue back")
}

@MainActor
@Test("a refresh that fails keeps the task being edited and what was typed")
func aFailedRefreshKeepsTheEditedTask() async throws {
  let (store, _) = try await makeDraftHandOffStore()
  let task = try #require(store.today.tasks.first)
  store.selectTaskFromList(task.id)
  await store.loadSelectedTaskDetail()
  store.taskDetailNotes = "Typed before the refresh failed"

  store.clearLoadedStateAfterRefreshFailure()

  #expect(store.today.tasks.isEmpty)
  #expect(store.selectedTaskID == task.id)
  #expect(store.selectedTask?.id == task.id)
  #expect(store.taskDetailNotes == "Typed before the refresh failed")
  #expect(store.selectedTaskHasUnsavedEditorState)
}

@MainActor
@Test("a refresh that fails closes a task inspector that holds no edits")
func aFailedRefreshClosesACleanInspector() async throws {
  let (store, _) = try await makeDraftHandOffStore()
  let task = try #require(store.today.tasks.first)
  store.selectTaskFromList(task.id)
  await store.loadSelectedTaskDetail()

  store.clearLoadedStateAfterRefreshFailure()

  #expect(store.selectedTaskID == nil)
  #expect(store.taskDetailDraftTaskID == nil)
}

@MainActor
@Test("a space typed after a title's last word is not an edit, and survives the autosave")
func aTrailingSpaceInTheTitleIsNotAnEdit() async throws {
  let (store, core) = try await makeDraftHandOffStore()
  let task = try #require(store.today.tasks.first)
  store.selectTaskFromList(task.id)
  await store.loadSelectedTaskDetail()

  store.taskDetailTitle = task.title + " "
  #expect(!store.taskDetailDraftHasChanges(for: task.id))
  #expect(!store.selectedTaskHasUnsavedEditorState)

  // A word, a space, then a pause long enough for the autosave.
  store.taskDetailTitle = "Buy milk "
  await store.saveTaskDetailDraft(id: task.id, preserveSelection: task.id)

  #expect(try await core.loadTask(id: task.id).title == "Buy milk")
  // The field keeps the space, so the next word does not join the last.
  #expect(store.taskDetailTitle == "Buy milk ")
  #expect(!store.selectedTaskHasUnsavedEditorState)
}

@MainActor
@Test("a checklist row that differs from its stored text only by a space at its end is not an edit")
func aTrailingSpaceInAChecklistRowIsNotAnEdit() async throws {
  let (store, core) = try await makeDraftHandOffStore()
  let task = try #require(store.today.tasks.first)
  let withItem = try await core.addTaskChecklistItem(taskID: task.id, text: "Pack the bag")
  let item = try #require(withItem.checklistItems.first { $0.text == "Pack the bag" })
  await store.refresh()
  store.selectTaskFromList(task.id)
  await store.loadSelectedTaskDetail()

  store.taskDetailChecklistDrafts[item.id] = "Pack the bag "
  #expect(!store.selectedTaskHasUnsavedEditorState)

  // The row then follows a change made elsewhere instead of holding its draft.
  _ = try await core.updateTaskChecklistItem(itemID: item.id, text: "Pack both bags")
  await store.refresh()
  #expect(store.taskDetailChecklistDrafts[item.id] == "Pack both bags")
}

