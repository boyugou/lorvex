import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

// Dropping tasks on a list in the sidebar, and the Move to List menu, move them
// through `AppStore.moveTasks(ids:toListID:undoManager:)`.

/// Polls `condition` for up to three seconds. An undo or redo runs its writes in
/// a task of its own, so a test waits for the result rather than for a return.
@MainActor
private func waitUntil(_ condition: () async throws -> Bool) async throws -> Bool {
  for _ in 0..<60 {
    if try await condition() { return true }
    try await Task.sleep(for: .milliseconds(50))
  }
  return false
}

/// The task leaves the pane it was moved out of. The Tasks workspace scoped to
/// the old list is the pane a drag from the list's own view starts in; it has
/// to reload, or the task stays on screen after landing in another list.
@MainActor
@Test
func movingATaskRemovesItFromTheTasksPaneScopedToItsOldList() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()
  let personal = try await core.createList(name: "Personal", description: nil)
  store.openTaskListScope(LorvexPreviewSeedID.appleNativeList)
  await store.loadTaskWorkspace()
  #expect(store.taskWorkspaceAllTasks.contains { $0.id == LorvexPreviewSeedID.agendaTask })

  await store.moveTasks(ids: [LorvexPreviewSeedID.agendaTask], toListID: personal.id)

  #expect(!store.taskWorkspaceAllTasks.contains { $0.id == LorvexPreviewSeedID.agendaTask })
  #expect(try await core.loadTask(id: LorvexPreviewSeedID.agendaTask).listID == personal.id)
  #expect(store.lists?.lists.first { $0.id == personal.id }?.openCount == 1)
  #expect(store.toastMessage == AppStore.moveToastMessage(count: 1, listName: "Personal"))
}

/// The task also leaves the open list detail and arrives in the destination's.
@MainActor
@Test
func movingATaskUpdatesTheOpenListDetailAndTheDestination() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()
  let personal = try await core.createList(name: "Personal", description: nil)
  store.selectedListID = LorvexPreviewSeedID.appleNativeList
  await store.loadSelectedListDetailForUI()
  #expect(store.selectedListDetail?.tasks.contains { $0.id == LorvexPreviewSeedID.agendaTask } == true)

  await store.moveTasks(ids: [LorvexPreviewSeedID.agendaTask], toListID: personal.id)
  #expect(store.selectedListDetail?.tasks.contains { $0.id == LorvexPreviewSeedID.agendaTask } == false)

  store.selectedListID = personal.id
  await store.loadSelectedListDetailForUI()
  #expect(store.selectedListDetail?.tasks.map(\.id) == [LorvexPreviewSeedID.agendaTask])
}

/// ⌘Z puts the task back, ⇧⌘Z moves it again, and the Edit menu names the move.
@MainActor
@Test
func aListMoveIsUndoneAndRedone() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()
  let personal = try await core.createList(name: "Personal", description: nil)
  let undoManager = UndoManager()
  undoManager.groupsByEvent = false

  undoManager.beginUndoGrouping()
  await store.moveTasks(
    ids: [LorvexPreviewSeedID.agendaTask], toListID: personal.id, undoManager: undoManager)
  undoManager.endUndoGrouping()

  #expect(undoManager.canUndo)
  #expect(undoManager.undoActionName == AppStore.moveToListTitle)
  #expect(try await core.loadTask(id: LorvexPreviewSeedID.agendaTask).listID == personal.id)

  undoManager.undo()
  #expect(
    try await waitUntil {
      try await core.loadTask(id: LorvexPreviewSeedID.agendaTask).listID
        == LorvexPreviewSeedID.appleNativeList
    })
  #expect(undoManager.canRedo)
  #expect(undoManager.redoActionName == AppStore.moveToListTitle)

  undoManager.redo()
  #expect(
    try await waitUntil {
      try await core.loadTask(id: LorvexPreviewSeedID.agendaTask).listID == personal.id
    })
  #expect(undoManager.canUndo)
}

/// A selection moved out of two lists goes back to the two lists it came from.
@MainActor
@Test
func undoingAMoveFromSeveralListsRestoresEachTasksOwnList() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()
  let personal = try await core.createList(name: "Personal", description: nil)
  let undoManager = UndoManager()
  undoManager.groupsByEvent = false

  undoManager.beginUndoGrouping()
  await store.moveTasks(
    ids: [LorvexPreviewSeedID.agendaTask, LorvexPreviewSeedID.venueTask],
    toListID: personal.id, undoManager: undoManager)
  undoManager.endUndoGrouping()
  #expect(store.toastMessage == AppStore.moveToastMessage(count: 2, listName: "Personal"))

  undoManager.undo()
  #expect(
    try await waitUntil {
      let agenda = try await core.loadTask(id: LorvexPreviewSeedID.agendaTask).listID
      let venue = try await core.loadTask(id: LorvexPreviewSeedID.venueTask).listID
      return agenda == LorvexPreviewSeedID.appleNativeList && venue == LorvexPreviewSeedID.inboxList
    })
}

/// The selection menus' Move to is the same move: it names the destination in a
/// toast, and ⌘Z puts each selected task back in the list it came from.
@MainActor
@Test
func aMoveFromASelectionMenuConfirmsItselfAndUndoes() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()
  let personal = try await core.createList(name: "Personal", description: nil)
  await store.loadTaskWorkspace()
  store.setTaskWorkspaceSelection([LorvexPreviewSeedID.agendaTask, LorvexPreviewSeedID.venueTask])
  #expect(store.taskWorkspaceSelectionCount == 2)
  let undoManager = UndoManager()
  undoManager.groupsByEvent = false

  undoManager.beginUndoGrouping()
  await store.moveTaskWorkspaceSelection(toListID: personal.id, undoManager: undoManager)
  undoManager.endUndoGrouping()

  #expect(try await core.loadTask(id: LorvexPreviewSeedID.agendaTask).listID == personal.id)
  #expect(try await core.loadTask(id: LorvexPreviewSeedID.venueTask).listID == personal.id)
  #expect(store.toastMessage == AppStore.moveToastMessage(count: 2, listName: "Personal"))
  #expect(undoManager.undoActionName == AppStore.moveToListTitle)

  undoManager.undo()
  #expect(
    try await waitUntil {
      let agenda = try await core.loadTask(id: LorvexPreviewSeedID.agendaTask).listID
      let venue = try await core.loadTask(id: LorvexPreviewSeedID.venueTask).listID
      return agenda == LorvexPreviewSeedID.appleNativeList && venue == LorvexPreviewSeedID.inboxList
    })
}

/// Tasks already in the destination are not rewritten, a drop with nothing left
/// to move says nothing, and it leaves no undo behind.
@MainActor
@Test
func movingTasksAlreadyInTheListWritesAndAnnouncesNothing() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()
  let undoManager = UndoManager()
  let before = try await core.loadTask(id: LorvexPreviewSeedID.agendaTask)

  await store.moveTasks(
    ids: [LorvexPreviewSeedID.agendaTask], toListID: LorvexPreviewSeedID.appleNativeList,
    undoManager: undoManager)

  #expect(store.toastMessage == nil)
  #expect(!undoManager.canUndo)
  #expect(try await core.loadTask(id: LorvexPreviewSeedID.agendaTask) == before)
}

/// A task that is in the list and one that is not: only the second moves, and
/// the toast counts one.
@MainActor
@Test
func movingAMixOfTasksCountsOnlyTheOnesThatMoved() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()

  await store.moveTasks(
    ids: [LorvexPreviewSeedID.agendaTask, LorvexPreviewSeedID.venueTask],
    toListID: LorvexPreviewSeedID.appleNativeList)

  #expect(try await core.loadTask(id: LorvexPreviewSeedID.venueTask).listID == LorvexPreviewSeedID.appleNativeList)
  #expect(
    store.toastMessage
      == AppStore.moveToastMessage(count: 1, listName: store.listDisplayName(LorvexPreviewSeedID.appleNativeList)))
}

/// Dragging a row that belongs to the selection drags the whole selection, the
/// dragged row first; dragging an unselected row drags that row alone.
@MainActor
@Test
func dragPayloadCarriesTheSelectionOnlyWhenTheRowIsSelected() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  store.navigateToWorkspace(.tasks)
  await store.loadTaskWorkspace()
  let selected: Set<LorvexTask.ID> = [
    LorvexPreviewSeedID.agendaTask, LorvexPreviewSeedID.venueTask,
    LorvexPreviewSeedID.statusUpdateTask,
  ]
  store.setTaskSelection(selected, on: .taskWorkspace)
  let venue = try #require(store.taskWorkspaceAllTasks.first { $0.id == LorvexPreviewSeedID.venueTask })

  let payload = store.taskDragPayload(for: venue, on: .taskWorkspace)

  #expect(payload.id == LorvexPreviewSeedID.venueTask)
  #expect(payload.taskIDs.first == LorvexPreviewSeedID.venueTask)
  #expect(Set(payload.taskIDs) == selected)
  #expect(payload.taskIDs.count == 3)

  let outside = try #require(
    store.taskWorkspaceAllTasks.first { !selected.contains($0.id) })
  #expect(store.taskDragPayload(for: outside, on: .taskWorkspace).taskIDs == [outside.id])
}

/// A single selected task is just the open task, not a batch, so its drag
/// carries that task alone.
@MainActor
@Test
func dragPayloadOfASingleSelectedTaskCarriesNoCompanions() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  store.navigateToWorkspace(.tasks)
  await store.loadTaskWorkspace()
  store.setTaskSelection([LorvexPreviewSeedID.agendaTask], on: .taskWorkspace)
  let agenda = try #require(store.taskWorkspaceAllTasks.first { $0.id == LorvexPreviewSeedID.agendaTask })

  let payload = store.taskDragPayload(for: agenda, on: .taskWorkspace)

  #expect(payload.companions.isEmpty)
}
