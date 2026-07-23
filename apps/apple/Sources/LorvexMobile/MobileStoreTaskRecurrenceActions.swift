import Foundation
import LorvexCore

/// Recurrence-editing state and persistence for the mobile task detail editor.
///
/// Both Apple editors use ``TaskRecurrenceEditorDraft`` so an edit to one basic
/// field preserves every AI-authored advanced modifier and resolves against the
/// latest loaded rule before entering the write funnel.
extension MobileStore {
  /// Weekday codes for the recurrence editor's `BYDAY` chips, in week order.
  public static let recurrenceWeekdayCodes = TaskRecurrenceWeekday.allCases.map(\.rawValue)

  public var taskDetailHasRecurrence: Bool {
    get { taskDetailRecurrenceDraft.isEnabled }
    set { taskDetailRecurrenceDraft.isEnabled = newValue }
  }

  public var taskDetailRecurrenceFrequency: TaskRecurrenceRule.Frequency {
    get { taskDetailRecurrenceDraft.frequency }
    set { taskDetailRecurrenceDraft.frequency = newValue }
  }

  public var taskDetailRecurrenceIntervalText: String {
    get { taskDetailRecurrenceDraft.intervalText }
    set { taskDetailRecurrenceDraft.intervalText = newValue }
  }

  public var taskDetailRecurrenceByDay: Set<String> {
    get { Set(taskDetailRecurrenceDraft.weeklyDays.map(\.rawValue)) }
    set {
      taskDetailRecurrenceDraft.weeklyDays =
        Set(newValue.compactMap(TaskRecurrenceWeekday.init(rawValue:)))
    }
  }

  public var taskDetailRecurrenceAnchor: TaskRecurrenceRule.Anchor {
    get { taskDetailRecurrenceDraft.anchor }
    set { taskDetailRecurrenceDraft.anchor = newValue }
  }

  var parsedTaskDetailRecurrenceInterval: Int? {
    taskDetailRecurrenceDraft.validatedInterval
  }

  var taskDetailDraftRecurrenceRule: TaskRecurrenceRule? {
    guard
      let intent = try? taskDetailRecurrenceDraft.saveIntent(
        liveRule: taskDetailRecurrenceDraft.originalRule)
    else { return nil }
    switch intent {
    case .none: return taskDetailRecurrenceDraft.originalRule
    case .remove: return nil
    case .set(let rule): return rule
    }
  }

  public var taskDetailRecurrenceCanSave: Bool {
    selectedTask != nil && taskDetailRecurrenceDraft.canSave
  }

  /// Seed the editor fields from the selected task's current recurrence.
  /// Call when opening the recurrence editor so an already-recurring task
  /// shows its existing frequency, interval, and weekday selection.
  public func beginRecurrenceEditing() {
    taskDetailRecurrenceDraft = TaskRecurrenceEditorDraft(rule: selectedTask?.recurrence)
  }

  /// Set the visible frequency. The shared draft decides at save time whether
  /// positional fields remain compatible, so changing away and back is a true
  /// undo instead of destructively clearing the original weekday selection.
  public func setRecurrenceFrequency(_ frequency: TaskRecurrenceRule.Frequency) {
    taskDetailRecurrenceFrequency = frequency
  }

  public func toggleRecurrenceDay(_ day: String) {
    guard let weekday = TaskRecurrenceWeekday(rawValue: day) else { return }
    if taskDetailRecurrenceDraft.weeklyDays.contains(weekday) {
      taskDetailRecurrenceDraft.weeklyDays.remove(weekday)
    } else {
      taskDetailRecurrenceDraft.weeklyDays.insert(weekday)
    }
  }

  /// Persist the drafted recurrence rule (or remove recurrence when disabled)
  /// through the same core calls the macOS editor uses, then update the loaded
  /// task surfaces without reloading unrelated workspaces.
  @discardableResult
  public func saveSelectedTaskRecurrence() async -> Bool {
    guard let selectedTask else { return false }
    let taskID = selectedTask.id
    let submittedDraft = taskDetailRecurrenceDraft
    let submittedFingerprint = submittedDraft.fingerprint
    let intent: TaskRecurrenceEditorSaveIntent
    do {
      intent = try taskDetailRecurrenceDraft.saveIntent(liveRule: selectedTask.recurrence)
    } catch {
      await presentUserFacingError(error)
      return false
    }
    if intent == .none { return true }
    let saved = await mutateTaskReturningTask(id: selectedTask.id) {
      switch intent {
      case .none:
        return selectedTask
      case .remove:
        return try await core.removeTaskRecurrence(taskID: selectedTask.id)
      case .set(let rule):
        return try await core.setTaskRecurrence(taskID: selectedTask.id, rule: rule)
      }
    }
    if saved {
      guard self.selectedTask?.id == taskID else { return true }
      let persistedRule = self.selectedTask?.recurrence
      let currentDraft = taskDetailRecurrenceDraft
      if currentDraft.fingerprint == submittedFingerprint {
        taskDetailRecurrenceDraft = TaskRecurrenceEditorDraft(rule: persistedRule)
      } else {
        taskDetailRecurrenceDraft = currentDraft.rebasedPreservingEdits(
          since: submittedDraft, onto: persistedRule)
      }
    }
    return saved
  }
}
