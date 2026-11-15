import Foundation
import LorvexCore

/// Holds runtime state for the task-detail editing surface: all editable fields
/// for the currently selected task and its checklist draft state.
struct AppStoreTaskDetailStorage {
  var loadedTasksByID: [LorvexTask.ID: LorvexTask] = [:]
  /// The title of the task the draft waits on, by its id, as the detail last
  /// read it, so the Waits on row can name a task none of the loaded lists
  /// holds.
  var dependencyTitlesByID: [LorvexTask.ID: String] = [:]
  var taskDetailTitle = ""
  var taskDetailNotes = ""
  var taskDetailPriority: LorvexTask.Priority = .p2
  var taskDetailEstimatedMinutesText = ""
  /// The draft's planned, due, and hide-until days in the storage frame: the
  /// stored day's UTC midnight, as `LorvexTask` holds them. A day picker's
  /// local midnight would name another day once the device's zone changed
  /// under an open draft, so the picker converts at its own edge
  /// (``AppStore/taskDetailPlannedDatePickerDate``).
  var taskDetailPlannedDate: Date?
  /// The last planned day the draft held, kept while the field is off so
  /// turning it back on restores it; nil starts it at the planner's today.
  var taskDetailPlannedDayStash: Date?
  var taskDetailHasPlannedDate = false
  /// The task's time on its planned day, in minutes since midnight.
  var taskDetailPlannedTime: Range<Int>?
  var taskDetailDueDate: Date?
  var taskDetailDueDayStash: Date?
  var taskDetailHasDueDate = false
  var taskDetailAvailableFrom: Date?
  var taskDetailAvailableFromDayStash: Date?
  var taskDetailHasAvailableFrom = false
  /// The zone the inspector's day pickers lay their days out in: this
  /// device's, followed as it changes. Not part of the draft; a test pins it.
  var taskDetailPickerTimeZone: TimeZone = .autoupdatingCurrent
  var taskDetailTagsText = ""
  var taskDetailDependsOnText = ""
  var taskDetailNewChecklistText = ""
  var taskDetailChecklistDrafts: [TaskChecklistItem.ID: String] = [:]
  var taskDetailReminderDate = AppStoreTaskDetailStorage.defaultReminderDate()
  var taskDetailRecurrenceDraft = TaskRecurrenceEditorDraft()
  var isSavingTaskRecurrence = false
  var taskDetailDraftTaskID: LorvexTask.ID?
  /// The task record the draft's fields were last filled from. The draft counts
  /// as edited when it differs from this record, never from the live task: a
  /// change made elsewhere moves the live task out from under an untouched
  /// draft, which would then read as the user's own edit.
  var taskDetailDraftSource: LorvexTask?

  mutating func reset() {
    loadedTasksByID = [:]
    dependencyTitlesByID = [:]
    resetDraft()
  }

  /// Takes the editor's fields from `other`, keeping this storage's loaded
  /// records: what puts back a draft whose write failed.
  mutating func restoreDraft(from other: AppStoreTaskDetailStorage) {
    let loaded = loadedTasksByID
    let titles = dependencyTitlesByID
    self = other
    loadedTasksByID = loaded
    dependencyTitlesByID = titles
    isSavingTaskRecurrence = false
  }

  mutating func resetDraft() {
    taskDetailTitle = ""
    taskDetailNotes = ""
    taskDetailPriority = .p2
    taskDetailEstimatedMinutesText = ""
    taskDetailPlannedDate = nil
    taskDetailPlannedDayStash = nil
    taskDetailHasPlannedDate = false
    taskDetailPlannedTime = nil
    taskDetailDueDate = nil
    taskDetailDueDayStash = nil
    taskDetailHasDueDate = false
    taskDetailAvailableFrom = nil
    taskDetailAvailableFromDayStash = nil
    taskDetailHasAvailableFrom = false
    taskDetailTagsText = ""
    taskDetailDependsOnText = ""
    taskDetailNewChecklistText = ""
    taskDetailChecklistDrafts = [:]
    taskDetailReminderDate = Self.defaultReminderDate()
    taskDetailRecurrenceDraft = TaskRecurrenceEditorDraft()
    isSavingTaskRecurrence = false
    taskDetailDraftTaskID = nil
    taskDetailDraftSource = nil
  }

  /// A sensible future default for the reminder picker — tomorrow at 9am in
  /// the product timezone.
  /// `Date()` (now) let a single "Add" without touching the chip schedule a
  /// reminder already in the past.
  static func defaultReminderDate(
    now: Date = Date(),
    timeZone: TimeZone = .autoupdatingCurrent
  ) -> Date {
    TaskReminderDateTime.defaultDate(now: now, timeZone: timeZone)
  }
}
