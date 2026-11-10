import Foundation
import LorvexCore

/// The inspector's unsaved edits to a task the selection is leaving.
struct TaskDraftLeftBehind {
  /// The title, notes, and other scalar fields the user changed, as one update;
  /// nil when none changed.
  var update: TaskUpdateDraft?
  /// Each checklist row whose text was changed, with the text to store.
  var checklistTexts: [(itemID: TaskChecklistItem.ID, text: String)]
  /// The task as stored when the edits were captured, and the editor's fields
  /// with their fingerprint, so a write that fails can put the editor back.
  var record: LorvexTask
  var editor: AppStoreTaskDetailStorage
  var fingerprint: String
}

/// Saving the inspector's unsaved edits when the selection leaves their task.
extension AppStore {
  /// Writes the inspector's unsaved edits to `taskID` as the selection leaves
  /// it.
  ///
  /// The draft is replaced the moment the selection changes: cleared when the
  /// inspector closes, refilled when another row opens. A view's own save runs
  /// after that, and a view that has left the screen runs none, so the edits
  /// are captured here, before the draft is replaced, and written in the
  /// background. The draft autosaves only once typing pauses, so without this
  /// a note typed and left at once would be lost whole.
  ///
  /// A title emptied in the draft is left out, since a task cannot have an
  /// empty title; the other edits are still saved. When the write fails, the
  /// error is shown and the editor returns to the task with the text as it was
  /// typed (``restoreTaskDraftLeftBehind(_:taskID:)``).
  func saveTaskDraftLeftBehind(for taskID: LorvexTask.ID?) {
    guard let taskID, taskDetailDraftTaskID == taskID else { return }
    // A save that has just written these very fields moves the selection as
    // its last step; there is nothing more to write, and it refills the draft.
    if let saved = lastSavedTaskDraft, saved.id == taskID,
      saved.fingerprint == taskDetailDraftFingerprint
    {
      return
    }
    guard let edits = taskDraftLeftBehind(for: taskID) else { return }
    // The edits are on their way to the store, so the fields hold no task's
    // draft until they are filled again: a later save must not send them twice.
    taskDetailDraftTaskID = nil
    let writeID = UUID()
    leftBehindDraftWrites[writeID] = Task { [weak self] in
      guard let self else { return }
      let saved = await self.writeTaskDraftLeftBehind(edits, taskID: taskID)
      if !saved {
        await self.restoreTaskDraftLeftBehind(edits, taskID: taskID)
      }
      self.leftBehindDraftWrites[writeID] = nil
    }
  }

  /// The unsaved edits the draft holds for task `id`, or nil when it is not
  /// that task's draft or holds nothing worth writing.
  func taskDraftLeftBehind(for id: LorvexTask.ID) -> TaskDraftLeftBehind? {
    guard taskDetailDraftTaskID == id, let record = taskForDetailDraft(id: id) else { return nil }
    let update = taskDetailUpdateDraft(id: id, droppingBlankTitle: true)
    let checklistTexts = editedChecklistTexts(of: record)
    guard update != nil || !checklistTexts.isEmpty else { return nil }
    return TaskDraftLeftBehind(
      update: update, checklistTexts: checklistTexts, record: record,
      editor: taskDetailStorage, fingerprint: taskDetailDraftFingerprint)
  }

  /// The checklist rows of `task` whose draft text differs from the stored
  /// text, with the text a commit would store. A row emptied in the draft is
  /// left out: an item must have text.
  private func editedChecklistTexts(
    of task: LorvexTask
  ) -> [(itemID: TaskChecklistItem.ID, text: String)] {
    task.checklistItems.compactMap { item in
      guard let draft = taskDetailChecklistDrafts[item.id] else { return nil }
      let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty, text != item.text else { return nil }
      return (item.id, text)
    }
  }

  /// Writes captured edits and reloads what shows the task, leaving the
  /// selection where the user put it. Returns whether the write succeeded; a
  /// failure is shown to the user.
  ///
  /// When the task is selected again by the time the write lands and its
  /// editor holds no edits of its own, the editor adopts what was saved;
  /// otherwise it would keep showing the record from before the write.
  func writeTaskDraftLeftBehind(
    _ edits: TaskDraftLeftBehind, taskID: LorvexTask.ID
  ) async -> Bool {
    let detail = taskDetailReloadSnapshot()
    do {
      var saved: LorvexTask?
      if let update = edits.update {
        saved = try await core.updateTask(update)
      }
      for row in edits.checklistTexts {
        saved = try await core.updateTaskChecklistItem(itemID: row.itemID, text: row.text)
      }
      guard let saved else { return true }
      replaceTask(saved)
      // The edits are stored; a failed reload below must not report otherwise.
      if let loaded = try? await core.loadToday() { today = loaded }
      if let loaded = try? await core.loadLists() { lists = loaded }
      // The reload must not move the selection the user has since made.
      try? await loadSelectedListDetail(preservingTaskSelection: selectedTaskID)
      await reloadTaskWorkspaceIfLoaded()
      await republishSurfacesAfterLocalMutation()
      if selectedTaskID == taskID, dirtyTaskIDToPreserve(after: detail) != taskID {
        syncSelectedTaskDraft(force: true)
      }
      return true
    } catch {
      await presentUserFacingError(error)
      return false
    }
  }

  /// Returns the editor to `taskID` with the text a failed write could not
  /// save, so the user can correct it instead of losing it.
  ///
  /// It does so once for a given text. Leaving the task again without changing
  /// anything fails the same way, and bringing the editor back every time
  /// would hold the user on a task they have chosen to leave twice. Nothing is
  /// restored where the workspace on screen shows no task inspector, or once
  /// the task is gone.
  private func restoreTaskDraftLeftBehind(
    _ edits: TaskDraftLeftBehind, taskID: LorvexTask.ID
  ) async {
    guard edits.fingerprint != restoredLeftBehindDraftFingerprint else {
      restoredLeftBehindDraftFingerprint = nil
      return
    }
    guard (try? await core.loadTask(id: taskID)) != nil,
      Self.selectionUsesSelectedTaskID(selection)
    else { return }
    restoredLeftBehindDraftFingerprint = edits.fingerprint
    // Selecting the task hands off whatever the editor holds now.
    selectedTaskID = taskID
    if taskForDetailDraft(id: taskID) == nil {
      taskDetailStorage.loadedTasksByID[taskID] = edits.record
    }
    taskDetailStorage.restoreDraft(from: edits.editor)
  }

  /// Waits for every write started by ``saveTaskDraftLeftBehind(for:)``.
  func waitForLeftBehindDraftWrites() async {
    while let write = leftBehindDraftWrites.values.first {
      await write.value
    }
  }
}
