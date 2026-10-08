import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

// Saving the task inspector's draft writes only the fields the user edited, on
// top of the task as it is stored now. A field the user left alone keeps what
// the core holds, so a change another writer made while the inspector was open
// (the assistant, another device) survives the save.

private let launchNote = "Write the launch note"
private let secondDraft = "Write the launch note, second draft"

@MainActor
@Test
func savingATitleEditKeepsAnAssistantsPriorityChange() async throws {
  let (store, core, id) = try await makeInspectorStore()
  await openInspector(on: id, in: store)
  store.taskDetailTitle = secondDraft

  _ = try await core.updateTask(TaskUpdateDraft(id: id, priority: .p1))
  await store.refresh()
  #expect(store.taskDetailTitle == secondDraft)

  await store.saveTaskDetailDraft(id: id, preserveSelection: id)

  let stored = try await core.loadTask(id: id)
  #expect(stored.title == secondDraft)
  #expect(stored.priority == .p1)
}

@MainActor
@Test
func savingATitleEditKeepsAnotherDevicesDayMove() async throws {
  let (store, core, id) = try await makeInspectorStore(planned: true)
  await openInspector(on: id, in: store)
  store.taskDetailTitle = secondDraft
  let moved = try #require(store.deferStorageDate(daysFromNow: 5))

  _ = try await core.updateTask(TaskUpdateDraft(id: id, plannedDate: .set(moved)))
  await store.refresh()

  await store.saveTaskDetailDraft(id: id, preserveSelection: id)

  let stored = try await core.loadTask(id: id)
  #expect(stored.title == secondDraft)
  #expect(stored.plannedDate == moved)
}

@MainActor
@Test
func theAutosaveOnNavigationKeepsAnAssistantsChangeToAnUntouchedField() async throws {
  let (store, core, id) = try await makeInspectorStore()
  await openInspector(on: id, in: store)
  let other = try await core.createTask(title: "Another task", notes: "")
  await store.loadTaskWorkspace()
  store.taskDetailNotes = "Context for the launch note."

  _ = try await core.updateTask(TaskUpdateDraft(id: id, priority: .p3))
  await store.refresh()

  store.selectedTaskID = other.id
  if store.taskDetailDraftHasChanges(for: id) {
    await store.saveTaskDetailDraft(id: id, preserveSelection: other.id)
  }

  let stored = try await core.loadTask(id: id)
  #expect(stored.notes == "Context for the launch note.")
  #expect(stored.priority == .p3)
}

@MainActor
@Test
func theUpdateCarriesOnlyTheEditedFields() async throws {
  let (store, _, id) = try await makeInspectorStore()
  await openInspector(on: id, in: store)
  #expect(store.taskDetailUpdateDraft(id: id) == nil)

  store.taskDetailPriority = .p3

  #expect(store.taskDetailUpdateDraft(id: id) == TaskUpdateDraft(id: id, priority: .p3))
}

@MainActor
@Test
func aDraftTheUserDidNotEditProducesNoUpdateAfterAChangeElsewhere() async throws {
  let (store, core, id) = try await makeInspectorStore()
  await openInspector(on: id, in: store)

  _ = try await core.updateTask(TaskUpdateDraft(id: id, priority: .p1))
  await store.refresh()

  #expect(store.taskDetailUpdateDraft(id: id) == nil)
  #expect(!store.taskDetailDraftHasChanges(for: id))
}

@MainActor
@Test
func editingOnlyTheTimeLeavesTheDayAlone() async throws {
  let (store, core, id) = try await makeInspectorStore(planned: true)
  _ = try await core.updateTask(TaskUpdateDraft(id: id, plannedTime: .set(600..<660)))
  await store.loadTaskWorkspace()
  await openInspector(on: id, in: store)

  store.taskDetailPlannedTime = 660..<720

  let update = try #require(store.taskDetailUpdateDraft(id: id))
  #expect(update.plannedDate == .unset)
  #expect(update.plannedTime == .set(660..<720))
}

@MainActor
@Test
func editingOnlyTheDayWritesTheTimeWithIt() async throws {
  let (store, core, id) = try await makeInspectorStore(planned: true)
  _ = try await core.updateTask(TaskUpdateDraft(id: id, plannedTime: .set(600..<660)))
  await store.loadTaskWorkspace()
  await openInspector(on: id, in: store)
  let day = try #require(store.deferStorageDate(daysFromNow: 3))

  store.taskDetailPlannedDatePickerDate = PlannedDayBridge.displayDate(forStorageDate: day)
  await store.saveTaskDetailDraft(id: id, preserveSelection: id)

  let stored = try await core.loadTask(id: id)
  #expect(stored.plannedDate == day)
  #expect(stored.plannedTime == 600..<660)
}

@MainActor
@Test
func clearingTheDayAndTheDueDateClearsBothAndNothingElse() async throws {
  let (store, core, id) = try await makeInspectorStore(planned: true)
  let due = try #require(store.deferStorageDate(daysFromNow: 6))
  _ = try await core.updateTask(TaskUpdateDraft(id: id, priority: .p1, dueDate: .set(due)))
  await store.loadTaskWorkspace()
  await openInspector(on: id, in: store)

  store.setTaskDetailHasPlannedDate(false)
  store.setTaskDetailHasDueDate(false)
  let update = try #require(store.taskDetailUpdateDraft(id: id))
  #expect(update == TaskUpdateDraft(id: id, dueDate: .clear, plannedDate: .clear))

  await store.saveTaskDetailDraft(id: id, preserveSelection: id)

  let stored = try await core.loadTask(id: id)
  #expect(stored.plannedDate == nil)
  #expect(stored.dueDate == nil)
  #expect(stored.priority == .p1)
  #expect(stored.title == launchNote)
}
