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

/// The common repeats the task detail's Repeat menu offers in one click; any
/// other rule is made in the menu's Custom editor. Each is a fixed schedule:
/// weekly repeats on the task's own weekday, and weekdays on Monday to Friday.
enum TaskDetailRecurrencePreset: CaseIterable, Identifiable {
  case daily, weekdays, weekly, biweekly, monthly, yearly

  var id: Self { self }

  fileprivate var frequency: TaskRecurrenceRule.Frequency {
    switch self {
    case .daily: .daily
    case .weekdays, .weekly, .biweekly: .weekly
    case .monthly: .monthly
    case .yearly: .yearly
    }
  }

  fileprivate var interval: Int { self == .biweekly ? 2 : 1 }

  fileprivate var weekdays: Set<String> {
    self == .weekdays ? ["MO", "TU", "WE", "TH", "FR"] : []
  }

  /// The menu item's name. Every preset but Weekdays is a plain interval, named
  /// by the same phrase the rule summaries use ("Every week", "Every 2 weeks").
  var title: String {
    switch self {
    case .weekdays:
      String(localized: "recurrence.preset.weekdays", defaultValue: "Weekdays", table: "Localizable", bundle: LorvexL10n.bundle)
    case .daily, .weekly, .biweekly, .monthly, .yearly:
      frequency.localizedEveryInterval(interval)
    }
  }
}

extension AppStore {
  /// The preset the selected task's repeat draft matches, if any.
  var taskDetailRecurrencePreset: TaskDetailRecurrencePreset? {
    guard taskDetailHasRecurrence, taskDetailRecurrenceAnchor == .schedule else { return nil }
    let interval = LorvexNumberInput.integer(from: taskDetailRecurrenceIntervalText) ?? 1
    return TaskDetailRecurrencePreset.allCases.first {
      $0.frequency == taskDetailRecurrenceFrequency && $0.interval == interval
        && $0.weekdays == taskDetailRecurrenceByDay
    }
  }

  /// Sets the selected task's repeat to `preset` (nil stops it repeating) and
  /// saves it, as one click in the Repeat menu.
  func applyTaskDetailRecurrencePreset(_ preset: TaskDetailRecurrencePreset?) async {
    if let preset {
      taskDetailHasRecurrence = true
      taskDetailRecurrenceAnchor = .schedule
      taskDetailRecurrenceFrequency = preset.frequency
      taskDetailRecurrenceIntervalText = String(preset.interval)
      taskDetailRecurrenceByDay = preset.weekdays
    } else {
      taskDetailHasRecurrence = false
    }
    await saveSelectedTaskRecurrence()
  }
}
