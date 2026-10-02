import LorvexCore
import SwiftUI

/// The value each word of the task's property sentence shows, derived from the
/// *draft* rather than the stored task.
///
/// Reading the draft is what makes the sentence feel direct: an edit made in a
/// word's popover shows up in the word the moment it is made, without waiting
/// for the save to land and a snapshot to come back. Every value is a short
/// phrase written for its place in the sentence, so a day that follows other
/// words reads "tomorrow", not "Tomorrow" (``LorvexDayPhrase``).
///
/// A `nil` summary means the field is unset, and the sentence offers it as a
/// dashed addition instead of a word.
extension AppStore {
  /// When the task is to be worked on: the planned day, and the task's time
  /// on it when it has one ("Today, 9:45 – 10:30 AM"). It opens the sentence.
  /// Without a planned day the field is unset. The time stays whole, so a
  /// value too wide for the inspector wraps after the day.
  var taskDetailDoOnSummary: String? {
    guard taskDetailHasPlannedDate else { return nil }
    let day = LorvexDayPhrase.phrase(
      for: taskDetailPlannedDatePickerDate, logicalDay: logicalTodayDateString, position: .leading)
    guard let time = taskDetailPlannedTime else { return day }
    let range = lorvexWholeSpan(
      lorvexClockRangeLabel(startMinutes: time.lowerBound, endMinutes: time.upperBound))
    return String(
      localized: "task_detail.do_on.day_time", defaultValue: "\(day), \(range)",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }

  /// `due_date` as the Due row's value: the day on its own ("today",
  /// "Fri, Oct 2"), never relative to the planned day, since the row stands
  /// alone. Once the deadline has gone by it carries how late it is; the
  /// lateness is the fact the user has to act on, so it rides in the value
  /// rather than only in the tint.
  var taskDetailDueSummary: String? {
    guard taskDetailHasDueDate else { return nil }
    return LorvexDayPhrase.due(
      taskDetailDueDatePickerDate, plannedDay: nil, logicalDay: logicalTodayDateString)
  }

  var taskDetailDueIsOverdue: Bool {
    guard taskDetailHasDueDate,
      let offset = lorvexDayOffset(from: logicalTodayDateString, to: taskDetailDueDatePickerDate)
    else { return false }
    return offset < 0
  }

  /// `available_from` — hidden from day surfaces until this day. It follows
  /// "Hidden until". A day that has arrived hides nothing, so it reads as
  /// unset and the sentence offers the field again.
  var taskDetailHideUntilSummary: String? {
    guard taskDetailHasAvailableFrom,
      (lorvexDayOffset(from: logicalTodayDateString, to: taskDetailAvailableFromPickerDate) ?? 1) > 0
    else { return nil }
    return LorvexDayPhrase.phrase(
      for: taskDetailAvailableFromPickerDate, logicalDay: logicalTodayDateString, position: .inline)
  }

  var taskDetailEstimateSummary: String? {
    guard let minutes = LorvexNumberInput.integer(from: taskDetailEstimatedMinutesText),
      minutes > 0
    else { return nil }
    return LorvexDurationFormat.minutes(minutes)
  }

  var taskDetailRepeatSummary: String? {
    guard taskDetailHasRecurrence, let rule = taskDetailDraftRecurrenceRule else { return nil }
    return rule.localizedCadence
  }

  func taskDetailRemindersSummary(task: LorvexTask) -> String? {
    task.reminders.isEmpty ? nil : lorvexReminderCountLabel(task.reminders.count)
  }

  func taskDetailListSummary(task: LorvexTask) -> String? {
    guard let listID = task.listID,
      let list = lists?.lists.first(where: { $0.id == listID })
    else { return nil }
    return list.displayName
  }

  var taskDetailTagsSummary: String? {
    let tags = taskDetailTagsText
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
    return tags.isEmpty ? nil : tags.joined(separator: " · ")
  }

  /// What this task is waiting on. The reverse direction (what it blocks) is not
  /// summarized here: it needs the whole dependency graph, which the row would
  /// have to load to render, and the editor behind the row shows both.
  var taskDetailDependencySummary: String? {
    let waitsOn = taskDetailDependencies.count
    return waitsOn > 0 ? lorvexWaitsOnLabel(count: waitsOn) : nil
  }
}

// MARK: - Phrases

func lorvexReminderCountLabel(_ count: Int) -> String {
  String(
    localized: "task_detail.reminders.count", defaultValue: "\(count) reminders",
    table: "Localizable", bundle: LorvexL10n.bundle)
}

func lorvexWaitsOnLabel(count: Int) -> String {
  String(
    localized: "task_detail.dependencies.waits_on", defaultValue: "Waits on \(count)",
    table: "Localizable", bundle: LorvexL10n.bundle)
}
