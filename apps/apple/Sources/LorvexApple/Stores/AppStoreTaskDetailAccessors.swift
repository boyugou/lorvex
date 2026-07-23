import Foundation
import LorvexCore

extension AppStore {
  var taskDetailTitle: String {
    get { taskDetailStorage.taskDetailTitle }
    set { taskDetailStorage.taskDetailTitle = newValue }
  }

  var taskDetailNotes: String {
    get { taskDetailStorage.taskDetailNotes }
    set { taskDetailStorage.taskDetailNotes = newValue }
  }

  var taskDetailPriority: LorvexTask.Priority {
    get { taskDetailStorage.taskDetailPriority }
    set { taskDetailStorage.taskDetailPriority = newValue }
  }

  var taskDetailEstimatedMinutesText: String {
    get { taskDetailStorage.taskDetailEstimatedMinutesText }
    set { taskDetailStorage.taskDetailEstimatedMinutesText = newValue }
  }

  var taskDetailPlannedDate: Date? {
    get { taskDetailStorage.taskDetailPlannedDate }
    set {
      taskDetailStorage.taskDetailPlannedDate = newValue
      if let newValue {
        taskDetailStorage.taskDetailPlannedDatePickerDate = newValue
      }
    }
  }

  var taskDetailHasPlannedDate: Bool {
    get { taskDetailStorage.taskDetailHasPlannedDate }
    set { taskDetailStorage.taskDetailHasPlannedDate = newValue }
  }

  var taskDetailDueDate: Date? {
    get { taskDetailStorage.taskDetailDueDate }
    set {
      taskDetailStorage.taskDetailDueDate = newValue
      if let newValue {
        taskDetailStorage.taskDetailDueDatePickerDate = newValue
      }
    }
  }

  var taskDetailHasDueDate: Bool {
    get { taskDetailStorage.taskDetailHasDueDate }
    set { taskDetailStorage.taskDetailHasDueDate = newValue }
  }

  var taskDetailAvailableFrom: Date? {
    get { taskDetailStorage.taskDetailAvailableFrom }
    set {
      taskDetailStorage.taskDetailAvailableFrom = newValue
      if let newValue {
        taskDetailStorage.taskDetailAvailableFromPickerDate = newValue
      }
    }
  }

  var taskDetailHasAvailableFrom: Bool {
    get { taskDetailStorage.taskDetailHasAvailableFrom }
    set { taskDetailStorage.taskDetailHasAvailableFrom = newValue }
  }

  var taskDetailTagsText: String {
    get { taskDetailStorage.taskDetailTagsText }
    set { taskDetailStorage.taskDetailTagsText = newValue }
  }

  var taskDetailDependsOnText: String {
    get { taskDetailStorage.taskDetailDependsOnText }
    set { taskDetailStorage.taskDetailDependsOnText = newValue }
  }

  var taskDetailNewChecklistText: String {
    get { taskDetailStorage.taskDetailNewChecklistText }
    set { taskDetailStorage.taskDetailNewChecklistText = newValue }
  }

  var taskDetailChecklistDrafts: [TaskChecklistItem.ID: String] {
    get { taskDetailStorage.taskDetailChecklistDrafts }
    set { taskDetailStorage.taskDetailChecklistDrafts = newValue }
  }

  var taskDetailReminderDate: Date {
    get { taskDetailStorage.taskDetailReminderDate }
    set { taskDetailStorage.taskDetailReminderDate = newValue }
  }

  var taskDetailHasRecurrence: Bool {
    get { taskDetailStorage.taskDetailRecurrenceDraft.isEnabled }
    set { taskDetailStorage.taskDetailRecurrenceDraft.isEnabled = newValue }
  }

  var taskDetailRecurrenceFrequency: TaskRecurrenceRule.Frequency {
    get { taskDetailStorage.taskDetailRecurrenceDraft.frequency }
    set { taskDetailStorage.taskDetailRecurrenceDraft.frequency = newValue }
  }

  var taskDetailRecurrenceIntervalText: String {
    get { taskDetailStorage.taskDetailRecurrenceDraft.intervalText }
    set { taskDetailStorage.taskDetailRecurrenceDraft.intervalText = newValue }
  }

  var taskDetailRecurrenceByDay: Set<String> {
    get { Set(taskDetailStorage.taskDetailRecurrenceDraft.weeklyDays.map(\.rawValue)) }
    set {
      taskDetailStorage.taskDetailRecurrenceDraft.weeklyDays =
        Set(newValue.compactMap(TaskRecurrenceWeekday.init(rawValue:)))
    }
  }

  var taskDetailRecurrenceAnchor: TaskRecurrenceRule.Anchor {
    get { taskDetailStorage.taskDetailRecurrenceDraft.anchor }
    set { taskDetailStorage.taskDetailRecurrenceDraft.anchor = newValue }
  }

  var taskDetailRecurrenceDraft: TaskRecurrenceEditorDraft {
    get { taskDetailStorage.taskDetailRecurrenceDraft }
    set { taskDetailStorage.taskDetailRecurrenceDraft = newValue }
  }

  var isSavingTaskRecurrence: Bool {
    get { taskDetailStorage.isSavingTaskRecurrence }
    set { taskDetailStorage.isSavingTaskRecurrence = newValue }
  }

  var taskDetailDraftTaskID: LorvexTask.ID? {
    get { taskDetailStorage.taskDetailDraftTaskID }
    set { taskDetailStorage.taskDetailDraftTaskID = newValue }
  }
}
