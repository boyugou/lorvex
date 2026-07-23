import Foundation
import LorvexCore
import SwiftUI

extension AppStore {
  /// The refresh tail shared by the single-task mutations: refresh the list
  /// surfaces, reload the Tasks workspace if it is loaded, then publish the
  /// Apple sync surfaces. Defined once so callers can't drift on which surfaces
  /// they reload; animation and selection-draft sync stay with the caller.
  func afterSelectedTaskMutation() async throws {
    try await refreshListSurfaces()
    await reloadTaskWorkspaceIfLoaded()
    await republishSurfacesAfterLocalMutation()
  }
}

extension AppStore {
  func saveSelectedTaskDraft() async {
    guard let id = selectedTask?.id, selectedTaskCanSave else { return }
    await saveTaskDetailDraft(id: id, preserveSelection: id)
  }

  func saveSelectedTaskDraftIfNeeded() async {
    guard selectedTaskCanSave else { return }
    await saveSelectedTaskDraft()
  }

  func saveTaskDetailDraft(id: LorvexTask.ID, preserveSelection: LorvexTask.ID?) async {
    let draftFingerprint = taskDetailDraftFingerprint
    guard taskDetailTitleIsValid else {
      if selectedTaskID != preserveSelection {
        selectedTaskID = preserveSelection
      }
      syncSelectedTaskDraft()
      return
    }
    await perform {
      let updated = try await core.updateTask(
        id: id,
        title: taskDetailTitle,
        notes: taskDetailNotes,
        priority: taskDetailPriority,
        estimatedMinutes: taskDetailEstimateForSave(taskID: id),
        dueDate: taskDetailDueDateForSave,
        plannedDate: taskDetailPlannedDateForSave,
        availableFrom: taskDetailAvailableFromForSave,
        tags: parsedTaskDetailTags,
        dependsOn: parsedTaskDetailDependencies
      )
      today = try await core.loadToday()
      replaceTask(updated)
      try await refreshListSurfaces()
      await reloadTaskWorkspaceIfLoaded()
      // Re-assert the navigation target this save was told to keep — unless the
      // user navigated on to a *third* task while the save was in flight, in
      // which case the live selection (no longer the saved task or its preserve
      // target) is theirs and must not be snapped back. The reloads above no
      // longer clobber the selection outside the Lists workspace, so the live
      // value here reliably reflects the user's latest navigation.
      if selectedTaskID == id || selectedTaskID == preserveSelection {
        selectedTaskID = preserveSelection
      }
      await republishSurfacesAfterLocalMutation()
      if selectedTaskID == id, taskDetailDraftFingerprint != draftFingerprint {
        // The user kept editing this task while the save was in flight; keep
        // the newer draft (still bound to the task) instead of clobbering the
        // fields with the just-saved values — the next save picks it up.
      } else {
        taskDetailDraftTaskID = nil
        syncSelectedTaskDraft()
      }
    }
  }

  func clearSelectedTaskAINotes() async {
    guard let id = selectedTask?.id else { return }
    await perform {
      let updated = try await core.setTaskAINotes(taskID: id, notes: "")
      replaceTask(updated)
      try await afterSelectedTaskMutation()
      syncSelectedTaskDraft()
    }
  }

  func completeSelectedTask(undoManager: UndoManager? = nil) async {
    guard let id = selectedTask?.id else { return }
    do {
      let updatedToday = try await core.completeTask(id: id)
      lorvexAnimated(.snappy(duration: 0.18)) {
        today = updatedToday
      }
      try await afterSelectedTaskMutation()
      feedbackProvider.playFeedback(.taskCompleted)
      errorMessage = nil
      registerReopenUndo(id: id, undoManager: undoManager, actionName: "Complete Task")
    } catch {
      await presentUserFacingError(error)
    }
  }

  /// Toggle a specific task's completion from a list row's leading circle.
  /// Does not change `selectedTaskID`, so checking a task off never opens its
  /// detail inspector. Completing plays feedback and registers a ⌘Z reopen;
  /// cancelled tasks are inert.
  func toggleTaskCompletion(_ task: LorvexTask, undoManager: UndoManager? = nil) async {
    // A cancelled task is inert here, and a parked Someday task is activated via
    // its own action — neither participates in the complete/reopen toggle.
    guard task.status != .cancelled, task.status != .someday else { return }
    await perform {
      let updatedToday: TodaySnapshot
      if task.status == .completed {
        updatedToday = try await core.reopenTask(id: task.id)
        feedbackProvider.playFeedback(.taskReopened)
      } else {
        updatedToday = try await core.completeTask(id: task.id)
        feedbackProvider.playFeedback(.taskCompleted)
        registerReopenUndo(id: task.id, undoManager: undoManager, actionName: "Complete Task")
      }
      lorvexAnimated(.snappy(duration: 0.18)) {
        today = updatedToday
      }
      try await afterSelectedTaskMutation()
      syncSelectedTaskDraft()
    }
  }

  /// Defer a specific task to `date` from a list-row control, without changing
  /// `selectedTaskID`. Inert for completed / cancelled tasks. Plays defer
  /// feedback and animates the task out of today's lanes.
  func deferTaskFromRow(_ task: LorvexTask, until date: Date) async {
    guard task.status != .completed, task.status != .cancelled else { return }
    await perform {
      let updatedToday = try await core.deferTask(id: task.id, until: date)
      feedbackProvider.playFeedback(.taskDeferred)
      lorvexAnimated(.snappy(duration: 0.18)) {
        today = updatedToday
      }
      try await afterSelectedTaskMutation()
    }
  }

  /// Reopens `id` (the inverse of complete/cancel) without disturbing the
  /// current selection — used by the registered undo action.
  func reopenTaskForUndo(_ id: LorvexTask.ID) async {
    await perform {
      today = try await core.reopenTask(id: id)
      try await afterSelectedTaskMutation()
      syncSelectedTaskDraft()
    }
  }

  /// Registers a reopen of `id` as the undo for a complete/cancel, so an
  /// accidental complete or non-recurring cancel is recoverable with ⌘Z.
  /// No-op without an `undoManager` (e.g. menu/keyboard-triggered actions, which
  /// are deliberate keystrokes rather than mis-clicks).
  func registerReopenUndo(id: LorvexTask.ID, undoManager: UndoManager?, actionName: String) {
    guard let undoManager else { return }
    undoManager.registerUndo(withTarget: self) { store in
      Task { @MainActor in await store.reopenTaskForUndo(id) }
    }
    undoManager.setActionName(actionName)
  }

  /// Begin cancelling `task` from any surface. Selects the task, then routes a
  /// recurring task to the scope dialog (via ``pendingRecurringCancelTaskID``)
  /// and cancels a non-recurring task immediately. This is the single entry
  /// point so context menus and the detail pane behave identically.
  func requestCancel(_ task: LorvexTask, undoManager: UndoManager? = nil) {
    selectedTaskID = task.id
    if task.recurrence != nil {
      pendingRecurringCancelTaskID = task.id
    } else {
      Task { await cancelSelectedTask(undoManager: undoManager) }
    }
  }

  func cancelSelectedTask(undoManager: UndoManager? = nil) async {
    guard let id = selectedTask?.id else { return }
    do {
      today = try await core.cancelTask(id: id)
      try await refreshListSurfaces()
      await reloadTaskWorkspaceIfLoaded()
      await loadSelectedTaskDetail()
      await republishSurfacesAfterLocalMutation()
      syncSelectedTaskDraft()
      errorMessage = nil
      registerReopenUndo(id: id, undoManager: undoManager, actionName: "Cancel Task")
    } catch {
      await presentUserFacingError(error)
    }
  }

  /// Stage `task` for the irreversible permanent-delete confirmation. The shared
  /// `.lorvexPermanentDeleteDialog(_:)` modifier presents the destructive prompt;
  /// confirming calls ``confirmPermanentDelete()``.
  func requestPermanentDelete(_ task: LorvexTask) {
    pendingPermanentDeleteTask = task
  }

  /// Permanently delete the staged task (archive + hard delete in one core
  /// transaction). Clears the selection and inspector if they pointed at it, and
  /// refreshes every task surface. No undo — the deletion is irreversible.
  func confirmPermanentDelete() async {
    guard let task = pendingPermanentDeleteTask else { return }
    pendingPermanentDeleteTask = nil
    await perform {
      try await core.permanentlyDeleteTask(id: task.id)
      if selectedTaskID == task.id { selectedTaskID = nil }
      today = try await core.loadToday()
      try await afterSelectedTaskMutation()
    }
  }

  /// Cancel `id` (a recurring task) with the chosen Calendar.app-style scope,
  /// dispatching the core operations the scope maps to
  /// (`RecurringTaskCancelScope.coreOperations`) in order. The final
  /// `cancelTask` result drives the refreshed `today` snapshot. Takes an
  /// explicit `id` — captured from `pendingRecurringCancelTaskID` when the scope
  /// dialog opened — so a selection change in another window while the dialog is
  /// up can't redirect the cancel to the wrong task.
  func cancelRecurringTask(id: LorvexTask.ID, scope: RecurringTaskCancelScope) async {
    await perform {
      if let snapshot = try await applyRecurringCancelScope(scope, taskID: id) {
        today = snapshot
      }
      try await refreshListSurfaces()
      await reloadTaskWorkspaceIfLoaded()
      await loadSelectedTaskDetail()
      await republishSurfacesAfterLocalMutation()
      syncSelectedTaskDraft()
    }
  }

  /// Park the selected task in the GTD Someday/Maybe bucket (`status='someday'`).
  /// `markTaskSomeday` returns the single updated task rather than a snapshot, so
  /// `today` is reloaded afterwards — the task drops out of Today's open lanes
  /// while keeping its list membership (status is orthogonal to `list_id`).
  func markSelectedTaskSomeday() async {
    guard let id = selectedTask?.id else { return }
    await perform {
      let updated = try await core.markTaskSomeday(id: id)
      replaceTask(updated)
      today = try await core.loadToday()
      try await afterSelectedTaskMutation()
      syncSelectedTaskDraft()
    }
  }

  /// Reopen the selected task (the inverse of complete/cancel) from the detail
  /// ⋯-menu, a row context menu, or Someday → Open. Mirrors
  /// ``completeSelectedTask(undoManager:)``: plays the reopen feedback and
  /// animates the task's row back into the queue instead of snapping it in.
  func reopenSelectedTask() async {
    // Use the stored selection id, not `selectedTask?.id`: a just-completed task
    // sits in the completed bucket and is briefly unresolvable in every pool
    // `selectedTask` searches while the workspace is mid-reload (only observable
    // under heavy concurrency), which would silently no-op the reopen. The id is
    // all `reopenTask` needs.
    guard let id = selectedTaskID else { return }
    await perform {
      let updatedToday = try await core.reopenTask(id: id)
      feedbackProvider.playFeedback(.taskReopened)
      lorvexAnimated(.snappy(duration: 0.18)) {
        today = updatedToday
      }
      try await refreshListSurfaces()
      await reloadTaskWorkspaceIfLoaded()
      selectedTaskID = id
      taskDetailDraftTaskID = nil
      await republishSurfacesAfterLocalMutation()
      syncSelectedTaskDraft()
    }
  }

  /// Start the selected task (`open → in_progress`) — put the "In Progress"
  /// marker on. Mirrors ``reopenSelectedTask()``: animates the row and keeps the
  /// selection so the detail inspector stays open. A dependency-blocked start
  /// surfaces the core's typed error.
  func startSelectedTask() async {
    guard let id = selectedTaskID else { return }
    await perform {
      let updatedToday = try await core.startTask(id: id)
      feedbackProvider.playFeedback(.taskReopened)
      lorvexAnimated(.snappy(duration: 0.18)) {
        today = updatedToday
      }
      try await refreshListSurfaces()
      await reloadTaskWorkspaceIfLoaded()
      selectedTaskID = id
      taskDetailDraftTaskID = nil
      await republishSurfacesAfterLocalMutation()
      syncSelectedTaskDraft()
    }
  }

  /// Remove the "In Progress" marker from the selected task
  /// (`in_progress → open`, the "Mark as Not Started" action). Leaves the task's
  /// planning state (planned_date / defer_count) untouched.
  func markSelectedTaskNotStarted() async {
    guard let id = selectedTaskID else { return }
    await perform {
      let updatedToday = try await core.pauseTask(id: id)
      feedbackProvider.playFeedback(.taskReopened)
      lorvexAnimated(.snappy(duration: 0.18)) {
        today = updatedToday
      }
      try await refreshListSurfaces()
      await reloadTaskWorkspaceIfLoaded()
      selectedTaskID = id
      taskDetailDraftTaskID = nil
      await republishSurfacesAfterLocalMutation()
      syncSelectedTaskDraft()
    }
  }

  /// Defer the selected task to tomorrow (the default action).
  func deferSelectedTask() async {
    guard let date = deferStorageDate(daysFromNow: 1) else { return }
    await deferSelectedTask(until: date)
  }

  /// Defer the selected task to `date`, with feedback. The task animates out of
  /// today's lanes into the deferred lane.
  func deferSelectedTask(until date: Date) async {
    guard let id = selectedTask?.id else { return }
    await perform {
      let updatedToday = try await core.deferTask(id: id, until: date)
      feedbackProvider.playFeedback(.taskDeferred)
      lorvexAnimated(.snappy(duration: 0.18)) {
        today = updatedToday
      }
      try await afterSelectedTaskMutation()
    }
  }
}
