import LorvexCore

extension AppStore {
  func saveSelectedTaskRecurrence() async {
    guard let selectedTask, !isSavingTaskRecurrence else { return }
    let taskID = selectedTask.id
    let submittedDraft = taskDetailRecurrenceDraft
    let submittedFingerprint = submittedDraft.fingerprint
    let intent: TaskRecurrenceEditorSaveIntent
    do {
      intent = try taskDetailRecurrenceDraft.saveIntent(liveRule: selectedTask.recurrence)
    } catch {
      await presentUserFacingError(error)
      return
    }
    guard intent != .none else { return }
    isSavingTaskRecurrence = true
    defer { isSavingTaskRecurrence = false }

    await perform {
      let updated: LorvexTask
      switch intent {
      case .none:
        return
      case .remove:
        updated = try await core.removeTaskRecurrence(taskID: selectedTask.id)
      case .set(let rule):
        updated = try await core.setTaskRecurrence(taskID: selectedTask.id, rule: rule)
      }
      replaceTask(updated)
      today = try await core.loadToday()
      try await refreshListSurfaces()
      await reloadTaskWorkspaceIfLoaded()
      await republishSurfacesAfterLocalMutation()
      guard selectedTaskID == taskID, taskDetailDraftTaskID == taskID else { return }
      let currentDraft = taskDetailRecurrenceDraft
      if currentDraft.fingerprint == submittedFingerprint {
        taskDetailRecurrenceDraft = TaskRecurrenceEditorDraft(rule: updated.recurrence)
      } else {
        taskDetailRecurrenceDraft = currentDraft.rebasedPreservingEdits(
          since: submittedDraft, onto: updated.recurrence)
      }
    }
  }
}
