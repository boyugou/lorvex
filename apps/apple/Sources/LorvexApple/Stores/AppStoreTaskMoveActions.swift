import Foundation
import LorvexCore

/// One leg of a list move: the tasks that go into one list. A move out of
/// several lists is undone with one leg per list the tasks came from.
struct TaskListMoveStep: Equatable, Sendable {
  let ids: [LorvexTask.ID]
  let listID: LorvexList.ID
}

extension AppStore {
  /// The shown name of a list. A list this store has not loaded reads as the
  /// Inbox: the core files an undirected capture there, and a task that names
  /// no list belongs to it.
  func listDisplayName(_ listID: LorvexList.ID?) -> String {
    lists?.lists.first { $0.id == listID }?.displayName ?? LorvexListNaming.localizedInboxName
  }

  /// The reference a drag of `task`'s row carries on `surface`: the task alone,
  /// or — when the row belongs to a multi-task selection — the whole selection,
  /// `task` first and the other selected rows after it in the order the surface
  /// shows them. Dragging a row outside the selection drags that row alone, as
  /// in Finder and Mail.
  func taskDragPayload(
    for task: LorvexTask, on surface: AppStoreBatchCancelSurface
  ) -> LorvexTaskRef {
    let selected = surface.selectedTasks(self)
    guard selected.count > 1, selected.contains(where: { $0.id == task.id }) else {
      return LorvexTaskRef(id: task.id, title: task.title)
    }
    return LorvexTaskRef(
      id: task.id, title: task.title,
      companions: selected.filter { $0.id != task.id }.map {
        LorvexTaskRef(id: $0.id, title: $0.title)
      })
  }

  /// Moves `ids` into the list `listID` in one write. Every gesture that puts
  /// tasks into a list on the Mac goes through here: dropping them on a list in
  /// the sidebar or the Lists overview, the row menu's Move to List, and the
  /// selection menus' Move to.
  ///
  /// A task already in the list, or one that no longer exists, is left alone,
  /// and a move that leaves nothing to do writes and shows nothing. A move that
  /// happened
  /// - reloads Today, the list catalog (the sidebar counts), the open list's
  ///   pane, the Tasks workspace and the review lists, so a task leaves the pane
  ///   it was moved out of;
  /// - names the destination in a toast, since a task can leave the pane without
  ///   a visible landing place;
  /// - registers its inverse with `undoManager`, so ⌘Z puts each task back in
  ///   the list it came from, and the undo is itself redoable.
  func moveTasks(
    ids: [LorvexTask.ID], toListID listID: LorvexList.ID, undoManager: UndoManager? = nil
  ) async {
    var seen = Set<LorvexTask.ID>()
    let ids = ids.filter { seen.insert($0).inserted }
    guard !ids.isEmpty else { return }
    await perform {
      var origin: [LorvexTask.ID: LorvexList.ID] = [:]
      for id in ids {
        if let task = try? await core.loadTask(id: id) {
          origin[id] = task.listID ?? LorvexListNaming.inboxID
        }
      }
      let movedIDs = try await core.batchMoveTasks(ids: ids, toListID: listID).moved.map(\.id)
      guard !movedIDs.isEmpty else { return }
      try await refreshAfterListMove(taskCount: movedIDs.count)
      toastMessage = Self.moveToastMessage(count: movedIDs.count, listName: listDisplayName(listID))
      let back = Dictionary(grouping: movedIDs) { origin[$0] ?? LorvexListNaming.inboxID }
        .map { TaskListMoveStep(ids: $0.value, listID: $0.key) }
        .sorted { $0.listID < $1.listID }
      registerListMoveUndo(
        undo: back, redo: [TaskListMoveStep(ids: movedIDs, listID: listID)],
        undoManager: undoManager)
    }
  }

  /// Confirmation for a move that may leave the pane: the moved count and the
  /// shown name of the destination list, pluralized through the catalog.
  static func moveToastMessage(count: Int, listName: String) -> String {
    String(
      localized: "task.move.toast",
      defaultValue: "Moved \(count) tasks to \(listName).",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }

  /// "Move to List": the label of the task menus' list submenu and the name of
  /// the Edit menu's undo and redo item for a list move.
  static var moveToListTitle: String {
    String(
      localized: "task.action.move_to_list", defaultValue: "Move to List",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }

  /// Registers `undo` as the manager's next undo and `redo` as what undoing
  /// re-registers, so ⌘Z and ⇧⌘Z move the tasks back and forth. The handler
  /// registers the opposite pair synchronously, while the manager is still
  /// undoing, which is what makes it a redo rather than a new undo; the writes
  /// run afterwards on the main actor.
  private func registerListMoveUndo(
    undo: [TaskListMoveStep], redo: [TaskListMoveStep], undoManager: UndoManager?
  ) {
    guard let undoManager else { return }
    undoManager.registerUndo(withTarget: self) { store in
      MainActor.assumeIsolated {
        store.registerListMoveUndo(undo: redo, redo: undo, undoManager: undoManager)
        Task { @MainActor in await store.applyListMoves(undo) }
      }
    }
    undoManager.setActionName(Self.moveToListTitle)
  }

  /// Applies the legs of an undo or redo of a list move and reloads what shows
  /// the tasks.
  private func applyListMoves(_ steps: [TaskListMoveStep]) async {
    await perform {
      var moved = 0
      for step in steps {
        moved += try await core.batchMoveTasks(ids: step.ids, toListID: step.listID).moved.count
      }
      guard moved > 0 else { return }
      try await refreshAfterListMove(taskCount: moved)
    }
  }

  private func refreshAfterListMove(taskCount: Int) async throws {
    let updatedToday = try await core.loadToday()
    publishBatchToday(updatedToday, taskCount: taskCount)
    pruneTodaySelection()
    try await afterSelectedTaskMutation()
  }
}
