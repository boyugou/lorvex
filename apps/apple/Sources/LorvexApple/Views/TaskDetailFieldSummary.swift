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
  /// Without a planned day the field is unset.
  var taskDetailDoOnSummary: String? {
    guard taskDetailHasPlannedDate else { return nil }
    let day = LorvexDayPhrase.phrase(
      for: taskDetailPlannedDatePickerDate, logicalDay: logicalTodayDateString, position: .leading)
    guard let time = taskDetailPlannedTime else { return day }
    let range = lorvexClockRangeLabel(startMinutes: time.lowerBound, endMinutes: time.upperBound)
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
    guard let minutes = Int(taskDetailEstimatedMinutesText.trimmingCharacters(in: .whitespaces)),
      minutes > 0
    else { return nil }
    return lorvexMinutesLabel(minutes)
  }

  var taskDetailRepeatSummary: String? {
    guard taskDetailHasRecurrence, let rule = taskDetailDraftRecurrenceRule else { return nil }
    return lorvexRecurrenceLabel(rule)
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

/// Short phrase for a recurrence rule — "Every week · Mon", "Every 3 months".
/// Long enough to be unambiguous, short enough to stay on one row; the editor
/// behind the row carries the full rule.
func lorvexRecurrenceLabel(_ rule: TaskRecurrenceRule) -> String {
  let interval = rule.interval ?? 1
  let unit: String
  switch rule.freq {
  case .daily:
    unit =
      interval == 1
      ? String(localized: "recurrence.every_day", defaultValue: "Every day", table: "Localizable", bundle: LorvexL10n.bundle)
      : String(localized: "recurrence.every_n_days", defaultValue: "Every \(interval) days", table: "Localizable", bundle: LorvexL10n.bundle)
  case .weekly:
    unit =
      interval == 1
      ? String(localized: "recurrence.every_week", defaultValue: "Every week", table: "Localizable", bundle: LorvexL10n.bundle)
      : String(localized: "recurrence.every_n_weeks", defaultValue: "Every \(interval) weeks", table: "Localizable", bundle: LorvexL10n.bundle)
  case .monthly:
    unit =
      interval == 1
      ? String(localized: "recurrence.every_month", defaultValue: "Every month", table: "Localizable", bundle: LorvexL10n.bundle)
      : String(localized: "recurrence.every_n_months", defaultValue: "Every \(interval) months", table: "Localizable", bundle: LorvexL10n.bundle)
  case .yearly:
    unit =
      interval == 1
      ? String(localized: "recurrence.every_year", defaultValue: "Every year", table: "Localizable", bundle: LorvexL10n.bundle)
      : String(localized: "recurrence.every_n_years", defaultValue: "Every \(interval) years", table: "Localizable", bundle: LorvexL10n.bundle)
  }
  guard let byDay = rule.byDay, !byDay.isEmpty else { return unit }
  return "\(unit) · \(byDay.map(lorvexWeekdayShortLabel).joined(separator: " "))"
}

/// Two-letter RFC-5545 weekday code to the platform's own short weekday name, so
/// a recurrence reads in the user's language rather than in the wire format.
func lorvexWeekdayShortLabel(_ code: String) -> String {
  let order = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
  guard let index = order.firstIndex(of: code.uppercased()) else { return code }
  var calendar = Calendar(identifier: .gregorian)
  calendar.locale = .autoupdatingCurrent
  let symbols = calendar.shortWeekdaySymbols
  return index < symbols.count ? symbols[index] : code
}
