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
  var taskDetailPlannedDate: Date?
  var taskDetailPlannedDatePickerDate = Date()
  var taskDetailHasPlannedDate = false
  /// The task's time on its planned day, in minutes since midnight.
  var taskDetailPlannedTime: Range<Int>?
  var taskDetailDueDate: Date?
  var taskDetailDueDatePickerDate = Date()
  var taskDetailHasDueDate = false
  var taskDetailAvailableFrom: Date?
  var taskDetailAvailableFromPickerDate = Date()
  var taskDetailHasAvailableFrom = false
  var taskDetailTagsText = ""
  var taskDetailDependsOnText = ""
  var taskDetailNewChecklistText = ""
  var taskDetailChecklistDrafts: [TaskChecklistItem.ID: String] = [:]
  var taskDetailReminderDate = AppStoreTaskDetailStorage.defaultReminderDate()
  var taskDetailRecurrenceDraft = TaskRecurrenceEditorDraft()
  var isSavingTaskRecurrence = false
  var taskDetailDraftTaskID: LorvexTask.ID?

  mutating func reset() {
    loadedTasksByID = [:]
    dependencyTitlesByID = [:]
    resetDraft()
  }

  mutating func resetDraft() {
    taskDetailTitle = ""
    taskDetailNotes = ""
    taskDetailPriority = .p2
    taskDetailEstimatedMinutesText = ""
    taskDetailPlannedDate = nil
    taskDetailPlannedDatePickerDate = Date()
    taskDetailHasPlannedDate = false
    taskDetailPlannedTime = nil
    taskDetailDueDate = nil
    taskDetailDueDatePickerDate = Date()
    taskDetailHasDueDate = false
    taskDetailAvailableFrom = nil
    taskDetailAvailableFromPickerDate = Date()
    taskDetailHasAvailableFrom = false
    taskDetailTagsText = ""
    taskDetailDependsOnText = ""
    taskDetailNewChecklistText = ""
    taskDetailChecklistDrafts = [:]
    taskDetailReminderDate = Self.defaultReminderDate()
    taskDetailRecurrenceDraft = TaskRecurrenceEditorDraft()
    isSavingTaskRecurrence = false
    taskDetailDraftTaskID = nil
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
