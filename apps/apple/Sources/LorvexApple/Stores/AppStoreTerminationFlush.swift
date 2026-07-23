import LorvexCore

extension AppStore {
  /// Whether a normal macOS termination must wait for an in-memory autosave
  /// draft. Explicit, unsubmitted controls (a new checklist row or recurrence
  /// editor) remain drafts by design; scalar task edits, sticky notes, and the
  /// daily journal are autosave surfaces and must reach SQLite before Quit.
  var hasPendingAutosaveDraftForTermination: Bool {
    if selectedTaskID.map({ taskDetailDraftHasChanges(for: $0) }) == true { return true }
    if !dailyReviewDraftMatchesLoaded { return true }
    return detachedWindowStores.contains { box in
      guard let detached = box.store, let id = detached.selectedTaskID else { return false }
      return detached.taskDetailDraftHasChanges(for: id)
    }
  }

  /// Flush every autosave surface owned by this app instance. The root store
  /// weakly tracks detached-window stores, so one termination barrier covers
  /// the main inspector, daily review, task-detail windows, and sticky notes.
  @discardableResult
  func flushPendingAutosaveDraftsForTermination() async -> Bool {
    if let id = selectedTaskID, taskDetailDraftHasChanges(for: id) {
      await saveTaskDetailDraft(id: id, preserveSelection: id)
    }
    await flushDailyReviewDraftIfNeeded()

    detachedWindowStores.removeAll { $0.store == nil }
    let detachedStores = detachedWindowStores.compactMap(\.store)
    for detached in detachedStores {
      guard let id = detached.selectedTaskID, detached.taskDetailDraftHasChanges(for: id) else {
        continue
      }
      await detached.saveTaskDetailDraft(id: id, preserveSelection: id)
    }

    // The individual save funnels already surface their errors and retain a
    // dirty draft on failure. Re-checking here turns that state into a hard
    // termination decision: normal Quit is cancelled instead of acknowledging
    // termination after an unconfirmed write.
    return !hasPendingAutosaveDraftForTermination
  }
}
