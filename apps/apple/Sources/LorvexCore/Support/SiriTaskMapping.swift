import Foundation
import LorvexDomain

/// How a Lorvex task reads and writes in the shape of the system's reminder
/// actions, the shape Siri works with on macOS 27 and iOS 27.
///
/// A system reminder has one date. A Lorvex task has a planned day, an
/// optional time on that day, and a separate deadline. The reminder's date is
/// the planned day and time: a task reports them when it has a planned day and
/// reports its deadline otherwise, and a date written through this shape sets
/// the planned day and time, never the deadline. A reminder repeats by a
/// `Calendar.RecurrenceRule`; a task repeats by a ``TaskRecurrenceRule``.
public enum SiriTaskMapping {
  /// A stored day and an optional clock time on it.
  public struct Moment: Equatable, Sendable {
    /// The day as stored: UTC midnight of its `yyyy-MM-dd`.
    public var day: Date
    /// Minutes since midnight on `day`; nil for a day without a time.
    public var startMinutes: Int?

    public init(day: Date, startMinutes: Int? = nil) {
      self.day = day
      self.startMinutes = startMinutes
    }
  }

  /// The length a task's time gets when neither the task nor the request
  /// gives one, in minutes.
  public static let defaultTimeLength = 30

  private static let storageCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
  }()

  // MARK: - Date

  /// The one date `task` reports: its planned day and time, or its deadline
  /// when it has no planned day, or nil when it has neither.
  public static func moment(for task: LorvexTask) -> Moment? {
    if let planned = task.plannedDate {
      return Moment(day: planned, startMinutes: task.plannedTime?.lowerBound)
    }
    return task.dueDate.map { Moment(day: $0) }
  }

  /// `moment` as Gregorian date components without a time zone, so the system
  /// reads them in the device's zone the way it reads a reminder's date.
  public static func dateComponents(for moment: Moment) -> DateComponents {
    var parts = storageCalendar.dateComponents([.year, .month, .day], from: moment.day)
    parts.calendar = Calendar(identifier: .gregorian)
    if let minutes = moment.startMinutes {
      parts.hour = minutes / 60
      parts.minute = minutes % 60
    }
    return parts
  }

  /// The day and time `components` name.
  ///
  /// Components that give a year name that day, with a missing month or day
  /// read as the first. Components without a year (a clock time alone, a
  /// weekday, a month and a day) name their next match: a day without a time
  /// is today or the first matching day after it, and a clock time is the next
  /// time the clock shows it after `now`.
  ///
  /// The components' own calendar and time zone are used when they carry
  /// them. Without a calendar they are counted in the Gregorian one, as a
  /// reminder's date is, whatever calendar the device shows; without a zone
  /// they are in `timeZone`, the zone the task's time is shown in.
  ///
  /// A day without a time keeps its date label. A time written in `timeZone`
  /// is kept as written, so a time the clocks skip on a daylight-saving day
  /// stays the time the task holds. A time written in another zone is
  /// converted to the clock of `timeZone`.
  public static func moment(
    from components: DateComponents, now: Date = Date(), timeZone: TimeZone = .current
  ) throws -> Moment {
    let zone = components.timeZone ?? timeZone
    var source = components.calendar ?? Calendar(identifier: .gregorian)
    source.timeZone = zone
    let minutes = try clockMinutes(of: components)

    var parts = DateComponents()
    parts.month = components.month
    parts.day = components.day
    if components.year != nil {
      parts.era = components.era
      parts.year = components.year
      parts.month = components.month ?? 1
      parts.day = components.day ?? 1
      if let minutes, zone.identifier != timeZone.identifier {
        parts.hour = minutes / 60
        parts.minute = minutes % 60
        guard let instant = source.date(from: parts) else { throw unreadableDate }
        return timedMoment(at: instant, timeZone: timeZone)
      }
      // Noon exists on every day in every zone, so it names the day's label
      // even when the written time falls in a daylight-saving gap.
      parts.hour = 12
      guard let noon = source.date(from: parts) else { throw unreadableDate }
      return Moment(
        day: PlannedDayBridge.storageDate(forLocalInstant: noon, timeZone: zone),
        startMinutes: minutes)
    }

    parts.weekday = components.weekday
    guard parts.month != nil || parts.day != nil || parts.weekday != nil || minutes != nil else {
      throw unreadableDate
    }
    if let minutes {
      parts.hour = minutes / 60
      parts.minute = minutes % 60
      guard
        let instant = source.nextDate(after: now, matching: parts, matchingPolicy: .nextTime)
      else { throw unreadableDate }
      return timedMoment(at: instant, timeZone: timeZone)
    }
    // A day without a time can be today, so the search starts just before
    // today began.
    let beforeToday = source.startOfDay(for: now).addingTimeInterval(-1)
    guard
      let instant = source.nextDate(after: beforeToday, matching: parts, matchingPolicy: .nextTime)
    else { throw unreadableDate }
    return Moment(day: PlannedDayBridge.storageDate(forLocalInstant: instant, timeZone: zone))
  }

  /// The clock time `components` name in minutes since midnight, or nil when
  /// they name no hour.
  private static func clockMinutes(of components: DateComponents) throws -> Int? {
    guard let hour = components.hour else { return nil }
    let minute = components.minute ?? 0
    guard (0..<24).contains(hour), (0..<60).contains(minute) else { throw unreadableDate }
    return hour * 60 + minute
  }

  /// The stored day and the clock time `instant` falls on in `timeZone`.
  private static func timedMoment(at instant: Date, timeZone: TimeZone) -> Moment {
    let clock = LorvexDateFormatters.gregorianCalendar(timeZone: timeZone)
      .dateComponents([.hour, .minute], from: instant)
    return Moment(
      day: PlannedDayBridge.storageDate(forLocalInstant: instant, timeZone: timeZone),
      startMinutes: (clock.hour ?? 0) * 60 + (clock.minute ?? 0))
  }

  /// The time a task holds once it starts at `startMinutes`: as long as the
  /// time it had, else its estimate, else ``defaultTimeLength``, and cut short
  /// at midnight so the start stays where it was asked for.
  public static func plannedTime(
    startingAt startMinutes: Int, replacing existing: Range<Int>?, estimatedMinutes: Int?
  ) -> Range<Int> {
    let dayEnd = 24 * 60
    let length = max(existing?.count ?? estimatedMinutes ?? defaultTimeLength, 1)
    let start = min(max(startMinutes, 0), dayEnd - 1)
    return start..<min(start + length, dayEnd)
  }

  private static var unreadableDate: LorvexCoreError {
    .validation(field: "date", message: "The date could not be read.")
  }

  /// The instant a stored ISO-8601 timestamp names, with or without
  /// fractional seconds; nil for no timestamp or one that does not parse.
  public static func instant(fromTimestamp text: String?) -> Date? {
    guard let text else { return nil }
    return LorvexDateFormatters.iso8601Fractional.date(from: text)
      ?? LorvexDateFormatters.iso8601.date(from: text)
  }

  // MARK: - Notes

  /// `notes` with each of `urls` it does not already contain added as a
  /// paragraph of its own. A task has no link field, so a link given with a
  /// reminder is kept in the notes. Notes that get no link come back
  /// unchanged; notes that get one lose only the blank space at their end.
  public static func notes(_ notes: String, appending urls: [URL]) -> String {
    var result = notes
    for url in urls {
      let text = url.absoluteString
      guard !text.isEmpty, !result.contains(text) else { continue }
      while let last = result.last, last.isWhitespace { result.removeLast() }
      result = result.isEmpty ? text : result + "\n\n" + text
    }
    return result
  }

  // MARK: - Repeat rule

  private static let weekdayCodes: [(Locale.Weekday, String)] = [
    (.monday, "MO"), (.tuesday, "TU"), (.wednesday, "WE"), (.thursday, "TH"),
    (.friday, "FR"), (.saturday, "SA"), (.sunday, "SU"),
  ]

  /// Week-start codes by `Calendar.firstWeekday`, which counts Sunday as 1.
  private static let weekStartCodes = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]

  /// The week start a task rule has when it names none.
  private static let defaultWeekStart = "MO"

  /// Calendars whose months and days are the Gregorian ones, so a rule
  /// counted in them means the same days in a task's Gregorian rule.
  private static let gregorianShapedCalendars: Set<Calendar.Identifier> = [
    .gregorian, .iso8601, .buddhist, .japanese, .republicOfChina,
  ]

  /// The task rule that repeats as `rule` does, or a validation failure when
  /// a task cannot repeat that way.
  ///
  /// A task repeats by day, week, month or year, on weekdays (optionally the
  /// nth of the month or year), days of the month, months and set positions,
  /// until a day or for a count. A rule by the hour or the minute, by week
  /// number, by day of the year, in a leap month, or counted in a calendar
  /// whose months are not the Gregorian ones is refused. One hour, minute and
  /// second in the rule is a time of day; a task's time comes from the
  /// reminder's date, so the rule's is left out. Several of them mean more
  /// than one occurrence a day and are refused.
  ///
  /// A weekly rule every two or more weeks keeps the day its calendar starts
  /// the week on, since that day decides which weekdays fall in the same week.
  ///
  /// A task rule lands only on days that exist: one on the 31st skips the
  /// shorter months, and one on 29 February skips the years without it. The
  /// system rule's own policy for a day that does not exist is not carried.
  public static func taskRecurrence(
    from rule: Calendar.RecurrenceRule, timeZone: TimeZone = .current
  ) throws -> TaskRecurrenceRule {
    let frequency: TaskRecurrenceRule.Frequency
    switch rule.frequency {
    case .daily: frequency = .daily
    case .weekly: frequency = .weekly
    case .monthly: frequency = .monthly
    case .yearly: frequency = .yearly
    default: throw unsupportedRepeat
    }
    guard gregorianShapedCalendars.contains(rule.calendar.identifier),
      rule.hours.count <= 1, rule.minutes.count <= 1, rule.seconds.count <= 1,
      rule.daysOfTheYear.isEmpty, rule.weeks.isEmpty, !rule.months.contains(where: \.isLeap)
    else { throw unsupportedRepeat }

    let byDay = try rule.weekdays.map { weekday -> String in
      switch weekday {
      case .every(let day): return try weekdayCode(day)
      case .nth(let position, let day): return "\(position)" + (try weekdayCode(day))
      @unknown default: throw unsupportedRepeat
      }
    }
    var until: String?
    if let end = rule.end.date {
      let day = PlannedDayBridge.storageDate(forLocalInstant: end, timeZone: timeZone)
      until = LorvexDateFormatters.ymdUTC.string(from: day)
    }
    var converted = TaskRecurrenceRule(
      freq: frequency,
      interval: rule.interval > 1 ? rule.interval : nil,
      byDay: byDay.isEmpty ? nil : byDay,
      byMonth: rule.months.isEmpty ? nil : rule.months.map(\.index),
      byMonthDay: rule.daysOfTheMonth.isEmpty ? nil : rule.daysOfTheMonth,
      bySetPos: rule.setPositions.isEmpty ? nil : rule.setPositions,
      until: until,
      count: rule.end.occurrences)
    if dependsOnWeekStart(converted) {
      let start = weekStartCodes[(max(rule.calendar.firstWeekday, 1) - 1) % 7]
      converted.wkst = start == defaultWeekStart ? nil : start
    }
    guard canonicalText(for: converted) != nil else { throw unsupportedRepeat }
    return converted
  }

  /// The system rule that repeats as the task rule `rule` does, counted in the
  /// Gregorian calendar in `timeZone`; nil when the task rule holds a weekday
  /// token this cannot read.
  ///
  /// The rule's calendar starts the week on the task rule's week start, and
  /// the rule matches only days that exist, as a task rule does. A rule that
  /// counts from the day the task is completed is reported by its frequency
  /// and interval alone, since the system's rule has no such anchor.
  public static func recurrence(
    for rule: TaskRecurrenceRule, timeZone: TimeZone = .current
  ) -> Calendar.RecurrenceRule? {
    let frequency: Calendar.RecurrenceRule.Frequency
    switch rule.freq {
    case .daily: frequency = .daily
    case .weekly: frequency = .weekly
    case .monthly: frequency = .monthly
    case .yearly: frequency = .yearly
    }
    var weekdays: [Calendar.RecurrenceRule.Weekday] = []
    for token in rule.byDay ?? [] {
      guard let weekday = weekday(fromToken: token) else { return nil }
      weekdays.append(weekday)
    }
    var end = Calendar.RecurrenceRule.End.never
    if let count = rule.count {
      end = .afterOccurrences(count)
    } else if let until = rule.until, let last = lastInstant(ofUntil: until, timeZone: timeZone) {
      end = .afterDate(last)
    }
    var calendar = LorvexDateFormatters.gregorianCalendar(timeZone: timeZone)
    let weekStart = (rule.wkst ?? defaultWeekStart).uppercased()
    calendar.firstWeekday = (weekStartCodes.firstIndex(of: weekStart) ?? 1) + 1
    var result = Calendar.RecurrenceRule(
      calendar: calendar, frequency: frequency, interval: max(rule.interval ?? 1, 1), end: end,
      matchingPolicy: .strict)
    result.weekdays = weekdays
    result.months = (rule.byMonth ?? []).map { Calendar.RecurrenceRule.Month($0) }
    result.daysOfTheMonth = rule.byMonthDay ?? []
    result.setPositions = rule.bySetPos ?? []
    return result
  }

  /// Whether `first` and `second` repeat on the same days, whatever each
  /// counts from: both are compared in their canonical form with the anchor
  /// left out, and with the week start spelled out where it changes the days
  /// and left out where it does not.
  public static func repeatsOnSameDays(_ first: TaskRecurrenceRule, _ second: TaskRecurrenceRule)
    -> Bool
  {
    guard let firstText = canonicalText(for: comparable(first)),
      let secondText = canonicalText(for: comparable(second))
    else { return false }
    return firstText == secondText
  }

  /// The first stored day on or after `day` that `rule` lands on, or `day`
  /// itself when the rule lands on no day within five years. Days are matched
  /// as a task rule matches them: only days that exist, in weeks that start
  /// where the rule's calendar starts them.
  public static func firstOccurrenceDay(
    of rule: Calendar.RecurrenceRule, onOrAfter day: Date
  ) -> Date {
    var calendar = storageCalendar
    calendar.firstWeekday = rule.calendar.firstWeekday
    var rule = rule
    rule.calendar = calendar
    rule.matchingPolicy = .strict
    rule.end = .never
    rule.hours = []
    rule.minutes = []
    rule.seconds = []
    guard let horizon = storageCalendar.date(byAdding: .year, value: 5, to: day) else { return day }
    return rule.recurrences(of: day, in: day..<horizon).first { _ in true } ?? day
  }

  private static var unsupportedRepeat: LorvexCoreError {
    .validation(
      field: "recurrence",
      message: "A task can repeat by day, week, month or year, but not this way.")
  }

  /// Whether the days `rule` lands on depend on where its week starts: only a
  /// weekly rule every two or more weeks does.
  private static func dependsOnWeekStart(_ rule: TaskRecurrenceRule) -> Bool {
    rule.freq == .weekly && (rule.interval ?? 1) > 1
  }

  /// `rule` with the fields that do not change its days made uniform.
  private static func comparable(_ rule: TaskRecurrenceRule) -> TaskRecurrenceRule {
    var rule = rule
    rule.anchor = .schedule
    rule.wkst = dependsOnWeekStart(rule) ? (rule.wkst ?? defaultWeekStart).uppercased() : nil
    return rule
  }

  /// The canonical text the core's recurrence check gives `rule`, or nil when
  /// the check refuses it.
  private static func canonicalText(for rule: TaskRecurrenceRule) -> String? {
    guard let text = rule.canonicalRecurrenceJSON(),
      case .success(let canonical) = ValidationRecurrence.normalizeTaskRecurrence(text)
    else { return nil }
    return canonical
  }

  private static func weekdayCode(_ weekday: Locale.Weekday) throws -> String {
    guard let code = weekdayCodes.first(where: { $0.0 == weekday })?.1 else {
      throw unsupportedRepeat
    }
    return code
  }

  /// A `BYDAY` token (`MO`, `2FR`, `-1SU`) as a system weekday.
  private static func weekday(fromToken token: String) -> Calendar.RecurrenceRule.Weekday? {
    let text = token.trimmingCharacters(in: .whitespaces).uppercased()
    guard text.count >= 2,
      let day = weekdayCodes.first(where: { $0.1 == String(text.suffix(2)) })?.0
    else { return nil }
    let prefix = text.dropLast(2)
    guard !prefix.isEmpty else { return .every(day) }
    guard let position = Int(prefix), position != 0 else { return nil }
    return .nth(position, day)
  }

  /// The last instant an `UNTIL` value covers: the value itself when it is a
  /// timestamp, the last second of its day in `timeZone` when it is a day.
  private static func lastInstant(ofUntil until: String, timeZone: TimeZone) -> Date? {
    let text = until.trimmingCharacters(in: .whitespaces)
    if text.count > 10, let instant = instant(fromTimestamp: text) {
      return instant
    }
    guard let day = LorvexDateFormatters.ymdUTC.date(from: String(text.prefix(10))) else {
      return nil
    }
    // The next midnight is found by the calendar: a day is 23 or 25 hours long
    // when the clocks change.
    let start = PlannedDayBridge.displayDate(forStorageDate: day, timeZone: timeZone)
    return LorvexDateFormatters.gregorianCalendar(timeZone: timeZone)
      .date(byAdding: .day, value: 1, to: start)?
      .addingTimeInterval(-1)
  }
}
