import Foundation
import LorvexCore

/// The words on the iPhone and iPad Today page and its schedule, sharing the
/// macOS keys and wording. Every sentence is computed from ``LorvexCalmToday``
/// or the schedule beside it, so the facts line, the chips, and the decision
/// never disagree with the rows beneath them.
enum MobileTodayCalmCopy {
  // MARK: - Facts

  /// The facts under the date, in reading order: tasks left, the estimated
  /// work, and meetings still ahead ("7 tasks left", "about 5 hr of work",
  /// "2 events"), drawn by ``LorvexFactsLine``. A day with nothing left says
  /// so in one sentence instead. `workIsStated` leaves the estimated work out
  /// when the page states it elsewhere (the overbooked well's title), so one
  /// figure is not read twice.
  static func facts(_ facts: LorvexCalmToday.Facts, workIsStated: Bool = false) -> [String] {
    switch facts {
    case .empty:
      return [emptySentence]
    case .allDone:
      return [allDoneSentence]
    case .day(let tasks, let workMinutes, let meetings):
      var parts = [tasksLeft(tasks)]
      if !workIsStated, let workMinutes, workMinutes > 0 {
        let length = lorvexUnbreakable(LorvexDurationFormat.hoursAndMinutes(roundedWork(workMinutes)))
        parts.append(
          String(
            localized: "today.list.work", defaultValue: "about \(length) of work",
            table: "Localizable", bundle: MobileL10n.bundle))
      }
      if meetings > 0 { parts.append(meetingsText(meetings)) }
      return parts
    }
  }

  private static var emptySentence: String {
    String(
      localized: "today.calm.headline.empty", defaultValue: "Nothing planned. The day is yours.",
      table: "Localizable", bundle: MobileL10n.bundle)
  }

  private static var allDoneSentence: String {
    String(
      localized: "today.calm.headline.all_done", defaultValue: "Everything planned is done.",
      table: "Localizable", bundle: MobileL10n.bundle)
  }

  private static func tasksLeft(_ count: Int) -> String {
    guard count > 0 else {
      return String(
        localized: "today.list.none_left", defaultValue: "No tasks left", table: "Localizable",
        bundle: MobileL10n.bundle)
    }
    return String(
      localized: "today.list.left", defaultValue: "\(count) tasks left", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  private static func meetingsText(_ count: Int) -> String {
    String(
      localized: "today.calm.headline.meetings", defaultValue: "\(count) events",
      table: "Localizable", bundle: MobileL10n.bundle)
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
        table: "Localizable", bundle: MobileL10n.bundle)
    }
    let free = lorvexUnbreakable(LorvexDurationFormat.hoursAndMinutes(roundedWork(overbooked.freeMinutes)))
    return String(
      localized: "today.overbooked.title", defaultValue: "About \(work) of work, \(free) free",
      table: "Localizable", bundle: MobileL10n.bundle)
  }

  /// The well's reason: the tasks the move would take off today, by name, and
  /// the time that frees. Without candidates it points at the two ways out. The
  /// sentence ends in one period even where the duration's last unit is an
  /// abbreviation that carries its own ("11 godz.").
  static func overbookedMessage(_ overbooked: LorvexCalmToday.Overbooked) -> String {
    let candidates = overbooked.candidates
    guard let first = candidates.first?.title else {
      return String(
        localized: "today.overbooked.none",
        defaultValue: "Defer what can wait, or ask your assistant to plan the day.",
        table: "Localizable", bundle: MobileL10n.bundle)
    }
    let minutes = candidates.reduce(0) { $0 + max($1.estimatedMinutes ?? 0, 0) }
    let freed = lorvexUnbreakable(LorvexDurationFormat.hoursAndMinutes(roundedWork(minutes)))
    let message: String
    switch candidates.count {
    case 1:
      message = String(
        localized: "today.overbooked.move.one",
        defaultValue: "Moving “\(first)” to tomorrow frees about \(freed).",
        table: "Localizable", bundle: MobileL10n.bundle)
    case 2:
      let second = candidates[1].title
      message = String(
        localized: "today.overbooked.move.two",
        defaultValue: "Moving “\(first)” and “\(second)” to tomorrow frees about \(freed).",
        table: "Localizable", bundle: MobileL10n.bundle)
    default:
      let second = candidates[1].title
      let more = candidates.count - 2
      message = String(
        localized: "today.overbooked.move.more",
        defaultValue: "Moving “\(first)”, “\(second)”, and \(more) more to tomorrow frees about \(freed).",
        table: "Localizable", bundle: MobileL10n.bundle)
    }
    return lorvexSingleFinalPeriod(message)
  }

  static var overbookedAction: String {
    String(
      localized: "today.overbooked.action", defaultValue: "Move to Tomorrow", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  // MARK: - Rows

  /// The time of a task whose time is running ("Until 3:00 PM"): only the end
  /// matters while it runs.
  static func untilLabel(end: Int) -> String {
    let time = clockLabel(end)
    return String(
      localized: "today.row.until", defaultValue: "Until \(time)", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  /// The chip on a task pushed off at least three times ("Pushed 4 times").
  static func pushedChip(_ count: Int) -> String {
    String(
      localized: "today.list.pushed", defaultValue: "Pushed \(count) times", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  /// A task's time ("2:00 – 3:00 PM"), or its start alone.
  static func timeRange(start: Int, end: Int?) -> String {
    guard let end, end > start else { return clockLabel(start) }
    return lorvexClockRangeLabel(startMinutes: start, endMinutes: end)
  }

  static var openDetails: String {
    String(
      localized: "today.calm.now.open", defaultValue: "Open Details", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  static var sunStart: String { clockLabel(7 * 60) }
  static var sunEnd: String { clockLabel(19 * 60) }

  /// A minutes-since-midnight value as a locale-aware clock label.
  static func clockLabel(_ minutes: Int) -> String { lorvexClockTimeLabel(minutes: minutes) }

  /// The product day as a spelled-out date ("Tuesday, September 22"), the
  /// title of a page: its weekday takes a capital in the languages that write
  /// it in lowercase.
  static func dateLine(logicalDay: String) -> String {
    lorvexDayLine(logicalDay: logicalDay, position: .leading)
  }

  static var doneTitle: String {
    String(
      localized: "today.list.done", defaultValue: "Done", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  static var briefingMore: String {
    String(
      localized: "today.list.briefing.more", defaultValue: "Show more", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  static var briefingLess: String {
    String(
      localized: "today.list.briefing.less", defaultValue: "Show less", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  static var briefingLabel: String {
    String(
      localized: "today.list.briefing.label", defaultValue: "Assistant’s briefing",
      table: "Localizable", bundle: MobileL10n.bundle)
  }

  // MARK: - Schedule

  static var scheduleTitle: String {
    String(
      localized: "today.calm.schedule.title", defaultValue: "Schedule", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  /// Heads the day's times while suggested times wait above them, so the same
  /// tasks at two sets of times read as two versions of the day.
  static var currentScheduleTitle: String {
    String(
      localized: "today.schedule.current", defaultValue: "Current Schedule", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  static var suggestTimes: String {
    String(
      localized: "today.schedule.suggest", defaultValue: "Suggest Times", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  static var clearTimes: String {
    String(
      localized: "today.schedule.clear", defaultValue: "Clear Times", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  static var suggestionTitle: String {
    String(
      localized: "today.schedule.suggestion.title", defaultValue: "Suggested Times",
      table: "Localizable", bundle: MobileL10n.bundle)
  }

  static var useSuggestion: String {
    String(
      localized: "today.schedule.suggestion.use", defaultValue: "Use These Times",
      table: "Localizable", bundle: MobileL10n.bundle)
  }

  static var dismissSuggestion: String {
    String(
      localized: "today.schedule.suggestion.dismiss", defaultValue: "Dismiss",
      table: "Localizable", bundle: MobileL10n.bundle)
  }

  /// The time column of a task the suggestion could not place.
  static var wontFit: String {
    String(
      localized: "today.schedule.wont_fit", defaultValue: "Won’t fit", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  /// A calendar event the suggestion may describe only as busy time.
  static var busy: String {
    String(
      localized: "today.schedule.busy", defaultValue: "Busy", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  /// The suggestion's caption when no working time is left for any task. The
  /// sentence ends in one period even where the clock's last mark is one ("5:00 p.m.").
  static func noTimeLeft(workingHours: Range<Int>) -> String {
    let end = clockLabel(workingHours.upperBound)
    return lorvexSingleFinalPeriod(
      String(
        localized: "today.schedule.no_time_left",
        defaultValue: "No time is left today for these tasks. Your day hours end at \(end).",
        table: "Localizable", bundle: MobileL10n.bundle))
  }

  /// The pane's line when today has tasks but none of them has a time.
  static var scheduleUntimedHint: String {
    String(
      localized: "today.schedule.untimed",
      defaultValue: "None of today’s tasks has a time. Suggest Times fits them around your calendar.",
      table: "Localizable", bundle: MobileL10n.bundle)
  }

  /// The pane's line when nothing is on the calendar and no task has a time.
  static var scheduleEmpty: String {
    String(
      localized: "today.calm.schedule.empty",
      defaultValue: "Nothing on the calendar and no timed work yet.",
      table: "Localizable", bundle: MobileL10n.bundle)
  }

  /// The Suggest Times action's label while a suggestion is being drawn.
  static var suggestingTimes: String {
    String(
      localized: "today.schedule.suggesting", defaultValue: "Suggesting Times",
      table: "Localizable", bundle: MobileL10n.bundle)
  }

  static var scheduleMenuLabel: String {
    String(
      localized: "today.schedule.menu.a11y", defaultValue: "Schedule actions",
      table: "Localizable", bundle: MobileL10n.bundle)
  }

  /// Clearing the day's times asks first on iPhone and iPad, which have no
  /// Edit menu to undo it from.
  static var clearTimesConfirmTitle: String {
    String(
      localized: "today.schedule.clear.confirm.title", defaultValue: "Clear today’s times?",
      table: "Localizable", bundle: MobileL10n.bundle)
  }

  static var clearTimesConfirmMessage: String {
    String(
      localized: "today.schedule.clear.confirm.message",
      defaultValue: "Today’s unfinished tasks lose their times and stay on today.",
      table: "Localizable", bundle: MobileL10n.bundle)
  }

  static var cancel: String {
    String(
      localized: "common.cancel", defaultValue: "Cancel", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  /// The schedule sheet's closing button.
  static var done: String {
    String(
      localized: "today.calm.schedule.done", defaultValue: "Done", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  static var habitsLabel: String {
    String(
      localized: "today.calm.habits", defaultValue: "Habits", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  /// The label of a done task's check, which reopens it.
  static var reopen: String {
    String(
      localized: "today.list.reopen", defaultValue: "Reopen", table: "Localizable",
      bundle: MobileL10n.bundle)
  }
}
