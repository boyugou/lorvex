import Foundation
import LorvexCore

/// The words on the Today page, its schedule, and the menu bar panel.
/// Every sentence is computed from ``LorvexCalmToday`` or the schedule beside
/// it, so the facts line, the chips, and the decision never disagree with the
/// rows beneath them.
enum TodayCalmCopy {
  // MARK: - Facts

  /// The facts under the date, in reading order: tasks left, the estimated
  /// work, and meetings still ahead ("7 tasks left", "about 5 hr of work",
  /// "2 events"), drawn by ``LorvexFactsLine``. A day with nothing left says
  /// so in one sentence instead.
  static func facts(_ facts: LorvexCalmToday.Facts) -> [String] {
    switch facts {
    case .empty:
      return [emptySentence]
    case .allDone:
      return [allDoneSentence]
    case .day(let tasks, let workMinutes, let meetings):
      var parts = [tasksLeft(tasks)]
      if let workMinutes, workMinutes > 0 {
        let length = lorvexUnbreakable(LorvexDurationFormat.hoursAndMinutes(roundedWork(workMinutes)))
        parts.append(
          String(
            localized: "today.list.work", defaultValue: "about \(length) of work",
            table: "Localizable", bundle: LorvexL10n.bundle))
      }
      if meetings > 0 { parts.append(meetingsText(meetings)) }
      return parts
    }
  }

  /// The facts as one sentence, for the menu bar panel's line under the date:
  /// what is left today, or that the day is open or done.
  static func sentence(_ facts: LorvexCalmToday.Facts) -> String {
    switch facts {
    case .empty:
      return emptySentence
    case .allDone:
      return allDoneSentence
    case .day(let tasks, _, let meetings):
      let taskText = String(
        localized: "today.calm.headline.tasks", defaultValue: "\(tasks) tasks",
        table: "Localizable", bundle: LorvexL10n.bundle)
      guard meetings > 0 else {
        return String(
          localized: "today.calm.headline.left_one", defaultValue: "\(taskText) left today.",
          table: "Localizable", bundle: LorvexL10n.bundle)
      }
      let meetingText = meetingsText(meetings)
      guard tasks > 0 else {
        return String(
          localized: "today.calm.headline.left_one", defaultValue: "\(meetingText) left today.",
          table: "Localizable", bundle: LorvexL10n.bundle)
      }
      return String(
        localized: "today.calm.headline.left_both",
        defaultValue: "\(taskText) and \(meetingText) left today.",
        table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  private static var emptySentence: String {
    String(
      localized: "today.calm.headline.empty", defaultValue: "Nothing planned. The day is yours.",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }

  private static var allDoneSentence: String {
    String(
      localized: "today.calm.headline.all_done", defaultValue: "Everything planned is done.",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }

  private static func tasksLeft(_ count: Int) -> String {
    guard count > 0 else {
      return String(
        localized: "today.list.none_left", defaultValue: "No tasks left", table: "Localizable",
        bundle: LorvexL10n.bundle)
    }
    return String(
      localized: "today.list.left", defaultValue: "\(count) tasks left", table: "Localizable",
      bundle: LorvexL10n.bundle)
  }

  /// The menu bar's Next 7 Days headline: what the seven days after today
  /// hold, counted the way Today's sentence counts its own day.
  static func weekSentence(tasks: Int, events: Int) -> String {
    let taskText = String(
      localized: "today.calm.headline.tasks", defaultValue: "\(tasks) tasks",
      table: "Localizable", bundle: LorvexL10n.bundle)
    let eventText = meetingsText(events)
    switch (tasks > 0, events > 0) {
    case (false, false):
      return String(
        localized: "menubar.week.headline.empty", defaultValue: "Nothing planned for the next 7 days.",
        table: "Localizable", bundle: LorvexL10n.bundle)
    case (true, true):
      return String(
        localized: "menubar.week.headline.both",
        defaultValue: "\(taskText) and \(eventText) in the next 7 days.",
        table: "Localizable", bundle: LorvexL10n.bundle)
    default:
      let only = tasks > 0 ? taskText : eventText
      return String(
        localized: "menubar.week.headline.one", defaultValue: "\(only) in the next 7 days.",
        table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  private static func meetingsText(_ count: Int) -> String {
    String(
      localized: "today.calm.headline.meetings", defaultValue: "\(count) events",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }

  /// Estimated work rounded for a phrase that says "about": to 5 minutes under
  /// an hour and to 15 minutes above, never below one step.
  static func roundedWork(_ minutes: Int) -> Int {
    let step = minutes < 60 ? 5 : 15
    return max(step, Int((Double(minutes) / Double(step)).rounded()) * step)
  }

  // MARK: - Overbooked

  /// The overbooked well's title: the estimated work against the free working
  /// time left ("About 6 hr of work, 4 hr free").
  static func overbookedTitle(_ overbooked: LorvexCalmToday.Overbooked) -> String {
    let work = lorvexUnbreakable(LorvexDurationFormat.hoursAndMinutes(roundedWork(overbooked.workMinutes)))
    guard overbooked.freeMinutes > 0 else {
      return String(
        localized: "today.overbooked.title.no_free",
        defaultValue: "About \(work) of work and no free time left",
        table: "Localizable", bundle: LorvexL10n.bundle)
    }
    let free = lorvexUnbreakable(LorvexDurationFormat.hoursAndMinutes(roundedWork(overbooked.freeMinutes)))
    return String(
      localized: "today.overbooked.title", defaultValue: "About \(work) of work, \(free) free",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }

  /// The well's reason: the tasks the move would take off today, by name, and
  /// the time that frees. Without candidates it points at the two ways out.
  static func overbookedMessage(_ overbooked: LorvexCalmToday.Overbooked) -> String {
    let candidates = overbooked.candidates
    guard let first = candidates.first?.title else {
      return String(
        localized: "today.overbooked.none",
        defaultValue: "Defer what can wait, or ask your assistant to plan the day.",
        table: "Localizable", bundle: LorvexL10n.bundle)
    }
    let minutes = candidates.reduce(0) { $0 + max($1.estimatedMinutes ?? 0, 0) }
    let freed = lorvexUnbreakable(LorvexDurationFormat.hoursAndMinutes(roundedWork(minutes)))
    switch candidates.count {
    case 1:
      return String(
        localized: "today.overbooked.move.one",
        defaultValue: "Moving “\(first)” to tomorrow frees about \(freed).",
        table: "Localizable", bundle: LorvexL10n.bundle)
    case 2:
      let second = candidates[1].title
      return String(
        localized: "today.overbooked.move.two",
        defaultValue: "Moving “\(first)” and “\(second)” to tomorrow frees about \(freed).",
        table: "Localizable", bundle: LorvexL10n.bundle)
    default:
      let second = candidates[1].title
      let more = candidates.count - 2
      return String(
        localized: "today.overbooked.move.more",
        defaultValue: "Moving “\(first)”, “\(second)”, and \(more) more to tomorrow frees about \(freed).",
        table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  static var overbookedAction: String {
    String(
      localized: "today.overbooked.action", defaultValue: "Move to Tomorrow", table: "Localizable",
      bundle: LorvexL10n.bundle)
  }

  // MARK: - Rows

  /// The time of a task whose time is running ("Until 3:00 PM"): only the end
  /// matters while it runs.
  static func untilLabel(end: Int) -> String {
    let time = clockLabel(end)
    return String(
      localized: "today.row.until", defaultValue: "Until \(time)", table: "Localizable",
      bundle: LorvexL10n.bundle)
  }

  /// The chip on a task pushed off at least three times ("Pushed 4 times").
  static func pushedChip(_ count: Int) -> String {
    String(
      localized: "today.list.pushed", defaultValue: "Pushed \(count) times", table: "Localizable",
      bundle: LorvexL10n.bundle)
  }

  /// A task's time ("2:00 – 3:00 PM"), or its start alone.
  static func timeRange(start: Int, end: Int?) -> String {
    guard let end, end > start else { return clockLabel(start) }
    return lorvexClockRangeLabel(startMinutes: start, endMinutes: end)
  }

  /// The line under the lead task in the menu bar panel: the time still
  /// running ("Until 3:00 PM"), a time ahead or passed ("2:00 – 3:00 PM"),
  /// "Started", or the estimate ("About 30 min"); nil when the task has none
  /// of these.
  static func leadDetail(_ item: LorvexCalmToday.Item) -> String? {
    if let time = item.time {
      return item.isRunning
        ? untilLabel(end: time.upperBound) : timeRange(start: time.lowerBound, end: time.upperBound)
    }
    if item.task.status == .inProgress {
      return String(
        localized: "task.row.started", defaultValue: "Started", table: "Localizable",
        bundle: LorvexL10n.bundle)
    }
    if let minutes = item.task.estimatedMinutes, minutes > 0 {
      return String(
        localized: "today.calm.estimate",
        defaultValue: "About \(LorvexDurationFormat.minutes(minutes))",
        table: "Localizable", bundle: LorvexL10n.bundle)
    }
    return nil
  }

  static func doneToday(_ count: Int) -> String {
    String(
      localized: "today.calm.done_today", defaultValue: "\(count) done today", table: "Localizable",
      bundle: LorvexL10n.bundle)
  }

  static var complete: String {
    String(
      localized: "today.calm.now.complete", defaultValue: "Mark as done", table: "Localizable",
      bundle: LorvexL10n.bundle)
  }

  static var openDetails: String {
    String(
      localized: "today.calm.now.open", defaultValue: "Open Details", table: "Localizable",
      bundle: LorvexL10n.bundle)
  }

  static var sunStart: String { clockLabel(7 * 60) }
  static var sunEnd: String { clockLabel(19 * 60) }

  /// A minutes-since-midnight value as a locale-aware clock label.
  static func clockLabel(_ minutes: Int) -> String { lorvexClockTimeLabel(minutes: minutes) }

  /// The product day as a spelled-out date ("Tuesday, September 22").
  static func dateLine(logicalDay: String) -> String { lorvexDayLine(logicalDay: logicalDay) }

  static var doneTitle: String {
    String(
      localized: "today.list.done", defaultValue: "Done", table: "Localizable",
      bundle: LorvexL10n.bundle)
  }

  static var briefingMore: String {
    String(
      localized: "today.list.briefing.more", defaultValue: "Show more", table: "Localizable",
      bundle: LorvexL10n.bundle)
  }

  static var briefingLess: String {
    String(
      localized: "today.list.briefing.less", defaultValue: "Show less", table: "Localizable",
      bundle: LorvexL10n.bundle)
  }

  static var briefingLabel: String {
    String(
      localized: "today.list.briefing.label", defaultValue: "Assistant’s briefing",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }

  // MARK: - Schedule

  static var scheduleTitle: String {
    String(
      localized: "today.calm.schedule.title", defaultValue: "Schedule", table: "Localizable",
      bundle: LorvexL10n.bundle)
  }

  /// Heads the day's times while suggested times wait above them, so the same
  /// tasks at two sets of times read as two versions of the day.
  static var currentScheduleTitle: String {
    String(
      localized: "today.schedule.current", defaultValue: "Current Schedule", table: "Localizable",
      bundle: LorvexL10n.bundle)
  }

  static var suggestTimes: String {
    String(
      localized: "today.schedule.suggest", defaultValue: "Suggest Times", table: "Localizable",
      bundle: LorvexL10n.bundle)
  }

  /// The Suggest Times tooltip, naming the working hours the suggestion fills
  /// when they have loaded.
  static func suggestTimesHelp(workingHours: Range<Int>?) -> String {
    guard let workingHours else {
      return String(
        localized: "today.schedule.suggest.help",
        defaultValue: "Lays today’s tasks into your free time, around your calendar.",
        table: "Localizable", bundle: LorvexL10n.bundle)
    }
    let hours = lorvexClockRangeLabel(
      startMinutes: workingHours.lowerBound, endMinutes: workingHours.upperBound)
    return String(
      localized: "today.schedule.suggest.help_hours",
      defaultValue: "Lays today’s tasks into your free time (\(hours)), around your calendar.",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }

  static var clearTimes: String {
    String(
      localized: "today.schedule.clear", defaultValue: "Clear Times", table: "Localizable",
      bundle: LorvexL10n.bundle)
  }

  static var suggestionTitle: String {
    String(
      localized: "today.schedule.suggestion.title", defaultValue: "Suggested Times",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }

  static var useSuggestion: String {
    String(
      localized: "today.schedule.suggestion.use", defaultValue: "Use These Times",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }

  static var dismissSuggestion: String {
    String(
      localized: "today.schedule.suggestion.dismiss", defaultValue: "Dismiss",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }

  /// The time column of a task the suggestion could not place.
  /// The tooltip of the suggestion's Move to Tomorrow button.
  static func moveUnscheduledHelp(_ count: Int) -> String {
    String(
      localized: "today.suggestion.move_unscheduled.help",
      defaultValue: "Move the \(count) tasks that don’t fit today to tomorrow",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }

  static var wontFit: String {
    String(
      localized: "today.schedule.wont_fit", defaultValue: "Won’t fit", table: "Localizable",
      bundle: LorvexL10n.bundle)
  }

  /// A calendar event the suggestion may describe only as busy time.
  static var busy: String {
    String(
      localized: "today.schedule.busy", defaultValue: "Busy", table: "Localizable",
      bundle: LorvexL10n.bundle)
  }

  /// The suggestion's caption when no working time is left for any task.
  static func noTimeLeft(workingHours: Range<Int>) -> String {
    let end = clockLabel(workingHours.upperBound)
    return String(
      localized: "today.schedule.no_time_left",
      defaultValue: "No time is left today for these tasks. Your day hours end at \(end).",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }

  /// Heads the tasks under Today's schedule: the ones without a time.
  static var tasksTitle: String {
    String(
      localized: "today.section.tasks", defaultValue: "Tasks", table: "Localizable",
      bundle: LorvexL10n.bundle)
  }

  /// An all-day event's time in the schedule.
  static var allDay: String {
    String(
      localized: "calendar.all_day_short", defaultValue: "All day", table: "Localizable",
      bundle: LorvexL10n.bundle)
  }

  /// The Edit menu's names for undoing a change to the day's times.
  static var undoSuggestedTimes: String {
    String(
      localized: "today.schedule.undo.use", defaultValue: "Use Suggested Times",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }
}
