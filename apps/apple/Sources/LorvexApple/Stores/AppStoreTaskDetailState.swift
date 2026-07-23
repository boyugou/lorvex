import Foundation
import LorvexCore
import LorvexDomain

extension AppStore {
  /// Captures enough editor state to decide whether a reload may safely adopt
  /// the refreshed selected task. The snapshot is taken before the first await:
  /// it therefore protects both a draft that was already dirty and edits the
  /// user starts while database reads are suspended.
  struct TaskDetailReloadSnapshot {
    let selectedTaskID: LorvexTask.ID?
    let draftTaskID: LorvexTask.ID?
    let draftFingerprint: String
    let wasDirty: Bool
  }

  func taskDetailReloadSnapshot() -> TaskDetailReloadSnapshot {
    TaskDetailReloadSnapshot(
      selectedTaskID: selectedTaskID,
      draftTaskID: taskDetailDraftTaskID,
      draftFingerprint: taskDetailDraftFingerprint,
      wasDirty: selectedTaskHasUnsavedEditorState)
  }

  /// The selected task whose editor must survive a completed reload, if any.
  /// Re-evaluating this at each reconciliation point also catches edits begun
  /// after the reload started instead of relying only on `wasDirty`.
  func dirtyTaskIDToPreserve(after snapshot: TaskDetailReloadSnapshot) -> LorvexTask.ID? {
    let stillEditingCapturedTask =
      selectedTaskID == snapshot.selectedTaskID
      && taskDetailDraftTaskID == snapshot.draftTaskID
    if stillEditingCapturedTask,
      snapshot.wasDirty || taskDetailDraftFingerprint != snapshot.draftFingerprint
    {
      return selectedTaskID
    }
    // When the same editor stayed bound and its fingerprint did not change, a
    // difference from `selectedTask` was introduced by the freshly reloaded
    // persisted row, not by the user. Treat that editor as clean so the caller
    // force-adopts the peer values. Falling through to the broad current-state
    // predicate here would misclassify every remote title/notes change as a local
    // draft and permanently leave a clean inspector stale.
    if stillEditingCapturedTask { return nil }
    return selectedTaskHasUnsavedEditorState ? selectedTaskID : nil
  }

  var selectedTaskDraftHasChanges: Bool {
    guard let task = selectedTask else { return false }
    return taskDetailDraftHasChanges(comparedTo: task)
  }

  /// Any unsaved editor state in the task inspector, including checklist-row
  /// text and the new-item field that the scalar draft comparison intentionally
  /// does not persist. Invalidation reloads use this broader predicate so an
  /// out-of-band write can never erase half-typed checklist text.
  var selectedTaskHasUnsavedEditorState: Bool {
    guard let task = selectedTask else { return false }
    if taskDetailDraftHasChanges(comparedTo: task) { return true }
    if taskDetailRecurrenceDraft.hasChanges { return true }
    if !taskDetailNewChecklistText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return true
    }
    return task.checklistItems.contains { item in
      (taskDetailChecklistDrafts[item.id] ?? item.text) != item.text
    }
  }

  /// One value that changes with any edit to the task-detail draft fields.
  /// Snapshotted around a save so an in-flight save can tell whether the user
  /// kept typing — in which case the post-save re-sync must not clobber the
  /// newer draft.
  var taskDetailDraftFingerprint: String {
    [
      taskDetailTitle,
      taskDetailNotes,
      String(describing: taskDetailPriority),
      taskDetailEstimatedMinutesText,
      String(taskDetailHasPlannedDate),
      String(taskDetailPlannedDatePickerDate.timeIntervalSinceReferenceDate),
      String(taskDetailHasDueDate),
      String(taskDetailDueDatePickerDate.timeIntervalSinceReferenceDate),
      String(taskDetailHasAvailableFrom),
      String(taskDetailAvailableFromPickerDate.timeIntervalSinceReferenceDate),
      taskDetailTagsText,
      taskDetailDependsOnText,
      taskDetailRecurrenceDraft.fingerprint,
      taskDetailNewChecklistText,
      taskDetailChecklistDrafts.sorted { $0.key < $1.key }
        .map { "\($0.key)=\($0.value)" }
        .joined(separator: "\u{1E}"),
    ].joined(separator: "\u{1F}")
  }

  func taskDetailDraftHasChanges(for taskID: LorvexTask.ID) -> Bool {
    guard let task = taskForDetailDraft(id: taskID) else { return false }
    return taskDetailDraftHasChanges(comparedTo: task)
  }

  private func taskDetailDraftHasChanges(comparedTo task: LorvexTask) -> Bool {
    guard taskDetailDraftTaskID == task.id else { return false }
    let plannedDate = taskDetailPlannedDateForSave
    if taskDetailTitle != task.title
      || taskDetailNotes != task.notes
      || taskDetailPriority != task.priority
      || parsedTaskDetailEstimate != task.estimatedMinutes
      || plannedDate != task.plannedDate
      || taskDetailDueDateForSave != task.dueDate
      || taskDetailAvailableFromForSave != task.availableFrom
    {
      return true
    }
    if parsedTaskDetailTags != task.tags { return true }
    return parsedTaskDetailDependencies != task.dependsOn
  }

  func taskForDetailDraft(id: LorvexTask.ID) -> LorvexTask? {
    today.inProgressTasks.first { $0.id == id }
      ?? today.tasks.first { $0.id == id }
      ?? selectedListDetail?.tasks.first { $0.id == id }
      ?? taskWorkspaceTask(id: id)
      ?? taskDetailStorage.loadedTasksByID[id]
  }

  /// The estimate to persist for `taskID`: the parsed input when it is valid
  /// (a number, or `nil` to clear when the field is blank), or the task's
  /// existing estimate when the field holds non-empty unparseable text (e.g.
  /// "30m"). This keeps an auto-save on navigation from discarding the user's
  /// title / notes / priority edits just because the estimate field is mid-edit
  /// or malformed.
  func taskDetailEstimateForSave(taskID: LorvexTask.ID) -> Int? {
    if taskDetailEstimateIsValid { return parsedTaskDetailEstimate }
    return taskForDetailDraft(id: taskID)?.estimatedMinutes
  }

  var taskDetailPlannedDateForSave: Date? {
    guard taskDetailHasPlannedDate else { return nil }
    // The picker hands back local-midnight instants; the service layer
    // formats in UTC, so re-anchor or an east-of-UTC save lands on the
    // previous day.
    return taskDetailPlannedDate.map { PlannedDayBridge.storageDate(forLocalInstant: $0) }
  }

  var taskDetailPlannedDatePickerDate: Date {
    get { taskDetailPlannedDate ?? taskDetailStorage.taskDetailPlannedDatePickerDate }
    set {
      taskDetailStorage.taskDetailPlannedDatePickerDate = newValue
      taskDetailPlannedDate = newValue
    }
  }

  /// The due date to persist: the chosen day re-anchored from local midnight to
  /// UTC for the service layer (a due date is a day, like the planned date), or
  /// `nil` when no due date is set.
  var taskDetailDueDateForSave: Date? {
    guard taskDetailHasDueDate else { return nil }
    return taskDetailDueDate.map { PlannedDayBridge.storageDate(forLocalInstant: $0) }
  }

  var taskDetailDueDatePickerDate: Date {
    get { taskDetailDueDate ?? taskDetailStorage.taskDetailDueDatePickerDate }
    set {
      taskDetailStorage.taskDetailDueDatePickerDate = newValue
      taskDetailDueDate = newValue
    }
  }

  /// The defer-until (`available_from`) day to persist: the chosen day
  /// re-anchored from local midnight to UTC for the service layer (a hide-until
  /// date is a day, like the planned date), or `nil` when it is not set.
  var taskDetailAvailableFromForSave: Date? {
    guard taskDetailHasAvailableFrom else { return nil }
    return taskDetailAvailableFrom.map { PlannedDayBridge.storageDate(forLocalInstant: $0) }
  }

  var taskDetailAvailableFromPickerDate: Date {
    get { taskDetailAvailableFrom ?? taskDetailStorage.taskDetailAvailableFromPickerDate }
    set {
      taskDetailStorage.taskDetailAvailableFromPickerDate = newValue
      taskDetailAvailableFrom = newValue
    }
  }

  var taskDetailEstimateIsValid: Bool {
    parsedTaskDetailEstimate != nil
      || taskDetailEstimatedMinutesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// Whether the recurrence interval field holds a savable value: empty (an
  /// omitted interval defaults to 1) or text that parses to a positive integer.
  /// Drives the inline red-tint feedback that explains why Save is disabled.
  var taskDetailRecurrenceIntervalIsValid: Bool {
    parsedTaskDetailRecurrenceInterval != nil
  }

  var taskDetailTitleIsValid: Bool {
    !taskDetailTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var taskDetailRecurrenceCanSave: Bool {
    selectedTask != nil && taskDetailRecurrenceDraft.canSave
  }

  var parsedTaskDetailEstimate: Int? {
    let text = taskDetailEstimatedMinutesText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    guard let value = Int(text),
      (1...Int(ValidationLimits.maxEstimatedMinutes)).contains(value)
    else { return nil }
    return value
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

  var parsedTaskDetailTags: [String] {
    Self.parseListText(taskDetailTagsText)
  }

  var parsedTaskDetailDependencies: [LorvexTask.ID] {
    Self.parseListText(taskDetailDependsOnText)
  }

  private static func parseListText(_ text: String) -> [String] {
    var seen = Set<String>()
    return
      text
      .split(whereSeparator: { character in
        character == "," || character == "\n" || character == "\t"
      })
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .filter { seen.insert($0).inserted }
  }

  func setTaskDetailHasPlannedDate(_ enabled: Bool) {
    taskDetailHasPlannedDate = enabled
    if enabled, taskDetailPlannedDate == nil {
      taskDetailPlannedDate = taskDetailStorage.taskDetailPlannedDatePickerDate
    }
  }

  func setTaskDetailHasDueDate(_ enabled: Bool) {
    taskDetailHasDueDate = enabled
    if enabled, taskDetailDueDate == nil {
      taskDetailDueDate = taskDetailStorage.taskDetailDueDatePickerDate
    }
  }

  func setTaskDetailHasAvailableFrom(_ enabled: Bool) {
    taskDetailHasAvailableFrom = enabled
    if enabled, taskDetailAvailableFrom == nil {
      taskDetailAvailableFrom = taskDetailStorage.taskDetailAvailableFromPickerDate
    }
  }

}
