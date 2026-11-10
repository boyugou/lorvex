import LorvexCore

extension AppStore {
  /// Whether a normal macOS termination must wait for an in-memory autosave
  /// draft. Explicit, unsubmitted controls (a new checklist row or recurrence
  /// editor) remain drafts by design; scalar task edits, edited checklist rows,
  /// sticky notes, and the daily journal are autosave surfaces and must reach
  /// SQLite before Quit, and so must the edits a selection change has handed to
  /// the store (``saveTaskDraftLeftBehind(for:)``). A title emptied in a draft
  /// is not waited for: a task cannot be saved without one, so it keeps the
  /// title it has.
  var hasPendingAutosaveDraftForTermination: Bool {
    if hasTaskDraftPendingForTermination { return true }
    if !dailyReviewDraftMatchesLoaded { return true }
    return detachedWindowStores.contains { $0.store?.hasTaskDraftPendingForTermination == true }
  }

  /// Whether this store's task editor holds edits Quit must write, or a write
  /// of such edits is still running.
  var hasTaskDraftPendingForTermination: Bool {
    if !leftBehindDraftWrites.isEmpty { return true }
    return selectedTaskID.map { taskDraftLeftBehind(for: $0) != nil } ?? false
  }

  /// Flush every autosave surface owned by this app instance. The root store
  /// weakly tracks detached-window stores, so one termination barrier covers
  /// the main inspector, daily review, task-detail windows, and sticky notes.
  @discardableResult
  func flushPendingAutosaveDraftsForTermination() async -> Bool {
    await flushTaskDraftForTermination()
    await flushDailyReviewDraftIfNeeded()

    detachedWindowStores.removeAll { $0.store == nil }
    for detached in detachedWindowStores.compactMap(\.store) {
      await detached.flushTaskDraftForTermination()
    }

    // A write that failed showed its error and left its draft in the editor.
    // Re-checking here turns that state into a hard termination decision:
    // normal Quit is cancelled instead of acknowledging termination after an
    // unconfirmed write.
    return !hasPendingAutosaveDraftForTermination
  }

  /// Writes this store's task draft, and waits for the writes a selection
  /// change started. A draft that was written is refilled from the stored
  /// record, so it no longer counts as pending; one whose write failed stays
  /// as typed.
  func flushTaskDraftForTermination() async {
    await waitForLeftBehindDraftWrites()
    guard let id = selectedTaskID, let edits = taskDraftLeftBehind(for: id) else { return }
    if await writeTaskDraftLeftBehind(edits, taskID: id) {
      taskDetailDraftTaskID = nil
      syncSelectedTaskDraft()
    }
  }
}
