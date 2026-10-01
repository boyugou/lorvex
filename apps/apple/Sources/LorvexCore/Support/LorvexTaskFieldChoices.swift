import Foundation

/// The choices the task-detail field pickers offer on macOS and iPhone, so the
/// length and day words edit the same way on both. Wording stays with each
/// platform's copy table; this holds only the values.
public enum LorvexTaskFieldChoices {
  /// The common lengths offered as one-tap choices, in minutes.
  public static let lengthPresets = [15, 30, 45, 60, 90, 120]
  /// How far one press of a length stepper moves, in minutes.
  public static let lengthStep = 15
  /// The length at which the length ring is full, in minutes.
  public static let lengthRingFull = 120

  /// How full the length ring is for `minutes`, from 0 to 1.
  public static func lengthFraction(_ minutes: Int) -> Double {
    min(max(Double(minutes) / Double(lengthRingFull), 0), 1)
  }

  /// The minutes a draft's length text holds; 0 when it is empty or not a number.
  public static func minutes(fromText text: String) -> Int {
    Int(text.trimmingCharacters(in: .whitespaces)) ?? 0
  }

  /// The draft text for `minutes`; empty for no length.
  public static func text(forMinutes minutes: Int) -> String {
    minutes > 0 ? String(minutes) : ""
  }

  /// The time a task's When picker proposes when the user adds one, in
  /// minutes since midnight: from the next half hour when the day is today
  /// and the clock is known, else from 9:00, for `length` minutes (30 when
  /// the task has no estimate), kept inside the day.
  public static func newTime(length: Int?, nowMinutes: Int?, isToday: Bool) -> Range<Int> {
    let minutes = min(max(length ?? 30, 5), 24 * 60)
    let proposed = isToday ? nowMinutes.map { ($0 / 30 + 1) * 30 } ?? 9 * 60 : 9 * 60
    let start = min(proposed, 24 * 60 - minutes)
    return start..<(start + minutes)
  }

  /// `time` with its start moved to `start`, keeping its length the way a
  /// calendar event moves, and kept inside the day.
  public static func time(_ time: Range<Int>, movingStartTo start: Int) -> Range<Int> {
    let begin = min(max(start, 0), 24 * 60 - time.count)
    return begin..<(begin + time.count)
  }

  /// `time` with its end set to `end`. A picked 0:00 is midnight at the close
  /// of the day, and an end at or before the start becomes fifteen minutes
  /// after it.
  public static func time(_ time: Range<Int>, settingEndTo end: Int) -> Range<Int> {
    let close = end == 0 ? 24 * 60 : end
    return time.lowerBound..<(close > time.lowerBound ? close : min(time.lowerBound + 15, 24 * 60))
  }

  /// A named day a day picker offers as a one-click choice.
  public enum DayPreset: Sendable, Hashable, CaseIterable {
    case today
    case tomorrow
    /// The coming Saturday; none while today is already Saturday or Sunday.
    case thisWeekend
    /// The first Monday after today.
    case nextMonday
    /// The first day of next month.
    case nextMonth
  }

  /// The local midnight `preset` names, seen from `now`; nil for a preset
  /// that does not apply today (``DayPreset/thisWeekend`` on a weekend).
  /// Weekdays are Gregorian (Saturday 7, Monday 2) whatever the calendar's
  /// first weekday.
  public static func date(
    for preset: DayPreset, from now: Date = .now, calendar: Calendar = .autoupdatingCurrent
  ) -> Date? {
    let today = calendar.startOfDay(for: now)
    switch preset {
    case .today:
      return today
    case .tomorrow:
      return calendar.date(byAdding: .day, value: 1, to: today)
    case .thisWeekend:
      let weekday = calendar.component(.weekday, from: today)
      guard weekday != 7, weekday != 1 else { return nil }
      return calendar.date(byAdding: .day, value: 7 - weekday, to: today)
    case .nextMonday:
      let weekday = calendar.component(.weekday, from: today)
      let days = (9 - weekday) % 7
      return calendar.date(byAdding: .day, value: days == 0 ? 7 : days, to: today)
    case .nextMonth:
      let month = calendar.dateComponents([.year, .month], from: today)
      return calendar.date(from: month).flatMap { calendar.date(byAdding: .month, value: 1, to: $0) }
    }
  }

  /// Today and the next two days as local midnights, each with its offset from
  /// today (0, 1, 2) so a platform can word "Today", "Tomorrow", then a weekday.
  public static func quickDays(
    from now: Date = .now, calendar: Calendar = .autoupdatingCurrent
  ) -> [(offset: Int, date: Date)] {
    let today = calendar.startOfDay(for: now)
    return (0..<3).compactMap { offset in
      calendar.date(byAdding: .day, value: offset, to: today).map { (offset, $0) }
    }
  }
}
