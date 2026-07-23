import Foundation
import LorvexCore

extension AppStore {
  /// Drop a task/habit inspector selection that the just-completed refresh made
  /// invalid (the row left the visible set for the current surface, or a habit
  /// was deleted on another device). Calendar tap-selection is preserved while
  /// the task is still scheduled in the window; other surfaces clear a stale
  /// selection so the inspector doesn't hang on a "not found" placeholder.
  func reconcileSelectedTaskAfterRefresh(preservingDirtyTaskID: LorvexTask.ID? = nil) {
    // Persisted state may legitimately make the selected row leave the current
    // surface, but that must not close the inspector and clear unsaved text. Keep
    // the stale loaded record as the draft's base until the user saves or
    // dismisses it; a later save can surface a typed not-found/conflict instead
    // of silently discarding the draft.
    if let preservingDirtyTaskID, selectedTaskID == preservingDirtyTaskID {
      return
    }
    switch selection {
    case .today:
      let visibleTasks = focusSurfaceOrderedTasks
      if let selectedTaskID, visibleTasks.contains(where: { $0.id == selectedTaskID }) {
        return
      }
      selectedTaskID = nil
    case .tasks:
      let visible = taskWorkspaceHasLoaded ? taskWorkspaceAllTasks : today.tasks
      if let selectedTaskID, visible.contains(where: { $0.id == selectedTaskID }) {
        return
      }
      // Deep-link / Spotlight / Handoff route a task open to the .tasks surface
      // (`applyRouteNavigation` case .task) and load it into
      // `taskDetailStorage.loadedTasksByID` even when the Tasks workspace hasn't
      // loaded and the task isn't in today.tasks. Treat that loaded-but-off-pool
      // task as a valid selection so the next refresh doesn't close the
      // just-opened inspector.
      if let selectedTaskID, taskDetailStorage.loadedTasksByID[selectedTaskID] != nil { return }
      selectedTaskID = nil
    case .lists:
      let visibleListTasks = filteredSelectedListTasks
      if let selectedTaskID, visibleListTasks.contains(where: { $0.id == selectedTaskID }) {
        return
      }
      selectedTaskID = nil
    case .calendar:
      // Calendar tap-selection opens the task inspector; keep it across a
      // refresh as long as the task is still scheduled in the window, rather
      // than closing the inspector — and discarding unsaved draft edits via the
      // selectedTaskID didSet — on every CloudKit push, import, or window open.
      // Unlike the list workspaces, the calendar never
      // auto-selects a first task; the inspector opens only on an explicit tap.
      if let selectedTaskID,
        (calendarScheduledTasks ?? []).contains(where: { $0.id == selectedTaskID })
      {
        return
      }
      selectedTaskID = nil
    case .habits:
      selectedTaskID = nil
      // Drop a habit-inspector selection whose habit no longer exists after the
      // refresh (deleted on another device / import), so the inspector doesn't
      // hang on a "Habit Not Found" placeholder.
      if let selectedHabitID,
        (habits?.habits ?? []).contains(where: { $0.id == selectedHabitID }) != true
      {
        self.selectedHabitID = nil
      }
    case .reviews, .memory:
      selectedTaskID = nil
    }
  }

  /// Reset every loaded surface to its empty state after a refresh throws, so the
  /// UI shows a clean empty/error state rather than a half-stale mix.
  func clearLoadedStateAfterRefreshFailure() {
    today = .empty
    currentFocus = nil
    focusSchedule = nil
    proposedFocusSchedule = nil
    dailyReview = nil
    weeklyReview = nil
    dayReviewEvidence = nil
    weekReviewDigest = []
    lists = nil
    selectedListID = nil
    selectedListDetail = nil
    calendarTimeline = nil
    calendarScheduledTasks = nil
    habits = nil
    runtimeDiagnostics = nil
    // The published widget snapshot is loaded view state, so clear it too —
    // leaving it set while everything else is empty is exactly the "half-stale
    // mix" this reset exists to avoid. Clear only this field, NOT the rest of
    // syncReportsStorage: a local DB read failure must not clear the CloudKit
    // pacing / circuit-breaker state, or a transient local error would trigger an
    // immediate re-burst that bypasses backoff.
    lastPublishedWidgetSnapshot = nil
    selectedTaskID = nil
    taskDetailStorage.reset()
  }
}
