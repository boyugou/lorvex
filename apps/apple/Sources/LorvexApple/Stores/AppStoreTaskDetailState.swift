import Foundation
import LorvexCore
import LorvexDomain

/// The inspector's scalar draft fields, as a set of the ones that differ from a
/// task record.
private struct TaskDetailEditedFields: OptionSet {
  let rawValue: Int

  static let title = TaskDetailEditedFields(rawValue: 1 << 0)
  static let notes = TaskDetailEditedFields(rawValue: 1 << 1)
  static let priority = TaskDetailEditedFields(rawValue: 1 << 2)
  static let estimate = TaskDetailEditedFields(rawValue: 1 << 3)
  static let plannedDay = TaskDetailEditedFields(rawValue: 1 << 4)
  static let plannedTime = TaskDetailEditedFields(rawValue: 1 << 5)
  static let dueDay = TaskDetailEditedFields(rawValue: 1 << 6)
  static let availableFrom = TaskDetailEditedFields(rawValue: 1 << 7)
  static let tags = TaskDetailEditedFields(rawValue: 1 << 8)
  static let dependencies = TaskDetailEditedFields(rawValue: 1 << 9)
}

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
    return taskDetailDraftHasChanges(comparedTo: taskDetailDraftBaseline(for: task))
  }

  /// Any unsaved editor state in the task inspector, including checklist-row
  /// text and the new-item field that the scalar draft comparison intentionally
  /// does not persist. Invalidation reloads use this broader predicate so an
  /// out-of-band write can never erase half-typed checklist text.
  var selectedTaskHasUnsavedEditorState: Bool {
    guard let task = selectedTask else { return false }
    let baseline = taskDetailDraftBaseline(for: task)
    if taskDetailDraftHasChanges(comparedTo: baseline) { return true }
    if taskDetailRecurrenceDraft.hasChanges { return true }
    if !taskDetailNewChecklistText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return true
    }
    return baseline.checklistItems.contains { item in
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
      taskDetailPlannedTime.map { "\($0.lowerBound)-\($0.upperBound)" } ?? "",
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
    return taskDetailDraftHasChanges(comparedTo: taskDetailDraftBaseline(for: task))
  }

  /// The record the draft of `task` is measured against: the one the draft was
  /// last filled from, which stays fixed while the stored task changes. A draft
  /// then counts as edited only when the user changed it. Measured against the
  /// live task, an untouched draft would read as edited after any change made
  /// elsewhere (a defer from a menu, a batch action, another device, the
  /// assistant), and the inspector's autosave would write its old values back
  /// over that change. A draft with no recorded source falls back to `task`.
  private func taskDetailDraftBaseline(for task: LorvexTask) -> LorvexTask {
    guard let source = taskDetailStorage.taskDetailDraftSource, source.id == task.id else {
      return task
    }
    return source
  }

  private func taskDetailDraftHasChanges(comparedTo task: LorvexTask) -> Bool {
    !taskDetailEditedFields(comparedTo: task).isEmpty
  }

  /// The scalar draft fields whose values differ from `task`. With the record
  /// the draft was filled from as `task`, these are the fields the user edited.
  /// Empty when the draft belongs to another task. Estimate text that is not a
  /// valid number never counts, because saving leaves the estimate as it is.
  private func taskDetailEditedFields(comparedTo task: LorvexTask) -> TaskDetailEditedFields {
    guard taskDetailDraftTaskID == task.id else { return [] }
    var edited: TaskDetailEditedFields = []
    if taskDetailTitle != task.title { edited.insert(.title) }
    if taskDetailNotes != task.notes { edited.insert(.notes) }
    if taskDetailPriority != task.priority { edited.insert(.priority) }
    if taskDetailEstimateIsValid, parsedTaskDetailEstimate != task.estimatedMinutes {
      edited.insert(.estimate)
    }
    if taskDetailPlannedDateForSave != task.plannedDate { edited.insert(.plannedDay) }
    if taskDetailPlannedTimeForSave != task.plannedTime { edited.insert(.plannedTime) }
    if taskDetailDueDateForSave != task.dueDate { edited.insert(.dueDay) }
    if taskDetailAvailableFromForSave != task.availableFrom { edited.insert(.availableFrom) }
    if parsedTaskDetailTags != task.tags { edited.insert(.tags) }
    if parsedTaskDetailDependencies != task.dependsOn { edited.insert(.dependencies) }
    return edited
  }

  /// The update that saves the inspector's draft of task `id`, or nil when the
  /// user changed nothing. It carries only the fields the user edited, measured
  /// against the record the draft was filled from, so the core applies them on
  /// top of the task as stored now: a change made elsewhere to a field the user
  /// left alone (the assistant re-prioritizing the task, another device moving
  /// its day) survives the save. A day's time belongs to its day: it is written
  /// when it changed and whenever the day changes while the draft keeps a time,
  /// because moving a task to another day would otherwise clear the time.
  func taskDetailUpdateDraft(id: LorvexTask.ID) -> TaskUpdateDraft? {
    guard let stored = taskForDetailDraft(id: id) else { return nil }
    let edited = taskDetailEditedFields(comparedTo: taskDetailDraftBaseline(for: stored))
    guard !edited.isEmpty else { return nil }
    let time = taskDetailPlannedTimeForSave
    let timePatch: Patch<Range<Int>>
    if let time, edited.contains(.plannedTime) || edited.contains(.plannedDay) {
      timePatch = .set(time)
    } else if time == nil, edited.contains(.plannedTime) {
      timePatch = .clear
    } else {
      timePatch = .unset
    }
    return TaskUpdateDraft(
      id: id,
      title: edited.contains(.title) ? taskDetailTitle : nil,
      notes: edited.contains(.notes) ? taskDetailNotes : nil,
      priority: edited.contains(.priority) ? taskDetailPriority : nil,
      estimatedMinutes: edited.contains(.estimate)
        ? Self.setOrClear(parsedTaskDetailEstimate) : .unset,
      dueDate: edited.contains(.dueDay) ? Self.setOrClear(taskDetailDueDateForSave) : .unset,
      plannedDate: edited.contains(.plannedDay)
        ? Self.setOrClear(taskDetailPlannedDateForSave) : .unset,
      plannedTime: timePatch,
      availableFrom: edited.contains(.availableFrom)
        ? Self.setOrClear(taskDetailAvailableFromForSave) : .unset,
      tags: edited.contains(.tags) ? parsedTaskDetailTags : nil,
      dependsOn: edited.contains(.dependencies) ? parsedTaskDetailDependencies : nil)
  }

  /// A draft field as a patch that writes it: its value, or a clear.
  private static func setOrClear<T: Sendable>(_ value: T?) -> Patch<T> {
    value.map { .set($0) } ?? .clear
  }

  func taskForDetailDraft(id: LorvexTask.ID) -> LorvexTask? {
    today.inProgressTasks.first { $0.id == id }
      ?? today.tasks.first { $0.id == id }
      ?? selectedListDetail?.tasks.first { $0.id == id }
      ?? taskWorkspaceTask(id: id)
      ?? taskDetailStorage.loadedTasksByID[id]
  }

  var taskDetailPlannedDateForSave: Date? {
    guard taskDetailHasPlannedDate else { return nil }
    // The picker hands back local-midnight instants; the service layer
    // formats in UTC, so re-anchor or an east-of-UTC save lands on the
    // previous day.
    return taskDetailPlannedDate.map { PlannedDayBridge.storageDate(forLocalInstant: $0) }
  }

  /// The time to persist: the draft's time while the draft has a planned day,
  /// since a time belongs to its day; nil otherwise.
  var taskDetailPlannedTimeForSave: Range<Int>? {
    taskDetailHasPlannedDate ? taskDetailPlannedTime : nil
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

  var taskDetailTitleIsValid: Bool {
    !taskDetailTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var taskDetailRecurrenceCanSave: Bool {
    selectedTask != nil && taskDetailRecurrenceDraft.canSave
  }

  var parsedTaskDetailEstimate: Int? {
    let text = taskDetailEstimatedMinutesText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    guard let value = LorvexNumberInput.integer(from: text),
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
    LorvexListText.entries(in: taskDetailTagsText)
  }

  var parsedTaskDetailDependencies: [LorvexTask.ID] {
    LorvexListText.entries(in: taskDetailDependsOnText)
  }

  /// Turning the planned day off also drops the draft's time, which has no
  /// meaning without its day.
  func setTaskDetailHasPlannedDate(_ enabled: Bool) {
    taskDetailHasPlannedDate = enabled
    if enabled, taskDetailPlannedDate == nil {
      taskDetailPlannedDate = taskDetailStorage.taskDetailPlannedDatePickerDate
    }
    if !enabled { taskDetailPlannedTime = nil }
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
