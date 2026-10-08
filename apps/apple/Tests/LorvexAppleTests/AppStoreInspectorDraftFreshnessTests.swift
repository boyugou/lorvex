import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

// The task inspector edits a draft copy of the selected task. A change made to
// that task from anywhere else (a menu command, a row control, a batch action)
// shows in the draft's fields, and a draft the user has not touched never reads
// as an edit: the inspector autosaves a draft that does, and saving would write
// the old values back over the change.

/// A store whose Tasks workspace is loaded, so the task stays resolvable from a
/// refreshed list while a change moves it out of Today.
@MainActor
func makeInspectorStore(
  planned: Bool = false
) async throws -> (store: AppStore, core: any LorvexCoreServicing, id: LorvexTask.ID) {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()
  let task = try await core.createTask(title: "Write the launch note", notes: "")
  if planned {
    let day = try #require(store.deferStorageDate(daysFromNow: 0))
    _ = try await core.updateTask(TaskUpdateDraft(id: task.id, plannedDate: .set(day)))
  }
  store.selection = .tasks
  await store.loadTaskWorkspace()
  return (store, core, task.id)
}

/// What the inspector does when a task is selected: adopt it into the draft,
/// then load its full detail.
@MainActor
func openInspector(on id: LorvexTask.ID, in store: AppStore) async {
  store.selectedTaskID = id
  store.syncSelectedTaskDraft()
  await store.loadSelectedTaskDetail()
}

@MainActor
private func expectDraftMatchesStoredTask(
  _ id: LorvexTask.ID, in store: AppStore, core: any LorvexCoreServicing
) async throws {
  let stored = try await core.loadTask(id: id)
  #expect(store.selectedTask == stored)
  #expect(store.taskDetailTitle == stored.title)
  #expect(store.taskDetailHasPlannedDate == (stored.plannedDate != nil))
  #expect(store.taskDetailPlannedDateForSave == stored.plannedDate)
  #expect(store.taskDetailPlannedTimeForSave == stored.plannedTime)
  #expect(store.taskDetailHasAvailableFrom == (stored.availableFrom != nil))
  #expect(store.taskDetailAvailableFromForSave == stored.availableFrom)
  #expect(!store.selectedTaskDraftHasChanges)
  #expect(!store.taskDetailDraftHasChanges(for: id))
  #expect(!store.selectedTaskHasUnsavedEditorState)
}

@MainActor
@Test
func deferringTheOpenTaskMovesItsPlannedDayField() async throws {
  let (store, core, id) = try await makeInspectorStore()
  await openInspector(on: id, in: store)

  await store.deferSelectedTask()

  #expect(try await core.loadTask(id: id).plannedDate != nil)
  try await expectDraftMatchesStoredTask(id, in: store, core: core)
}

@MainActor
@Test
func deferringAPlannedOpenTaskReplacesItsPlannedDayField() async throws {
  let (store, core, id) = try await makeInspectorStore(planned: true)
  await openInspector(on: id, in: store)
  let before = try #require(store.taskDetailPlannedDateForSave)

  await store.deferSelectedTask()

  let stored = try await core.loadTask(id: id)
  #expect(try #require(stored.plannedDate) > before)
  try await expectDraftMatchesStoredTask(id, in: store, core: core)
}

@MainActor
@Test
func snoozingTheOpenTaskFillsItsAvailableFromField() async throws {
  let (store, core, id) = try await makeInspectorStore()
  await openInspector(on: id, in: store)
  let until = try #require(store.deferStorageDate(daysFromNow: 3))

  await store.snoozeSelectedTask(until: until)

  #expect(try await core.loadTask(id: id).availableFrom == until)
  try await expectDraftMatchesStoredTask(id, in: store, core: core)
}

@MainActor
@Test
func movingOnAfterADeferDoesNotWriteTheOldDayBack() async throws {
  let (store, core, id) = try await makeInspectorStore(planned: true)
  await openInspector(on: id, in: store)
  let other = try await core.createTask(title: "Another task", notes: "")
  await store.loadTaskWorkspace()

  await store.deferSelectedTask()
  let deferredDay = try #require(try await core.loadTask(id: id).plannedDate)

  // The inspector saves the task it leaves when its draft reads as edited.
  store.selectedTaskID = other.id
  if store.taskDetailDraftHasChanges(for: id) {
    await store.saveTaskDetailDraft(id: id, preserveSelection: other.id)
  }

  #expect(try await core.loadTask(id: id).plannedDate == deferredDay)
}

@MainActor
@Test
func movingOnAfterASnoozeDoesNotClearTheSnooze() async throws {
  let (store, core, id) = try await makeInspectorStore()
  await openInspector(on: id, in: store)
  let other = try await core.createTask(title: "Another task", notes: "")
  await store.loadTaskWorkspace()
  let until = try #require(store.deferStorageDate(daysFromNow: 3))

  await store.snoozeSelectedTask(until: until)
  store.selectedTaskID = other.id
  if store.taskDetailDraftHasChanges(for: id) {
    await store.saveTaskDetailDraft(id: id, preserveSelection: other.id)
  }

  #expect(try await core.loadTask(id: id).availableFrom == until)
}

@MainActor
@Test
func aTitleTheUserIsTypingSurvivesADeferOfTheSameTask() async throws {
  let (store, core, id) = try await makeInspectorStore()
  await openInspector(on: id, in: store)
  store.taskDetailTitle = "Write the launch note, second draft"

  await store.deferSelectedTask()

  #expect(store.taskDetailTitle == "Write the launch note, second draft")
  #expect(store.selectedTaskDraftHasChanges)
  #expect(store.taskDetailDraftHasChanges(for: id))
  #expect(try await core.loadTask(id: id).title == "Write the launch note")
}

@MainActor
@Test
func deferringTheOpenTaskInABatchMovesItsPlannedDayField() async throws {
  let (store, core, id) = try await makeInspectorStore(planned: true)
  await openInspector(on: id, in: store)
  store.selectOnlyTaskInWorkspace(id)

  await store.deferTaskWorkspaceSelection()

  try await expectDraftMatchesStoredTask(id, in: store, core: core)
}

@MainActor
@Test
func reopeningTheOpenTaskInABatchClearsTheFieldsTheReopenClears() async throws {
  let (store, core, id) = try await makeInspectorStore(planned: true)
  await openInspector(on: id, in: store)
  store.selectOnlyTaskInWorkspace(id)
  await store.completeTaskWorkspaceSelection(undoManager: nil)

  store.selectOnlyTaskInWorkspace(id)
  await store.reopenTaskWorkspaceSelection()

  try await expectDraftMatchesStoredTask(id, in: store, core: core)
}

@MainActor
@Test
func aChangeFromAnotherWriterShowsInAnUntouchedDraftAfterARefresh() async throws {
  let (store, core, id) = try await makeInspectorStore()
  await openInspector(on: id, in: store)
  let day = try #require(store.deferStorageDate(daysFromNow: 4))

  _ = try await core.updateTask(TaskUpdateDraft(id: id, plannedDate: .set(day)))
  await store.refresh()

  try await expectDraftMatchesStoredTask(id, in: store, core: core)
}
