import Foundation

/// How a habit's check-ins spread across the days of the week over a recent
/// window: for each weekday from Monday to Sunday, how much of the plan its
/// days met.
///
/// The window runs from the habit's first check-in, or from 84 days before
/// `today` when that is later, through today. Today counts only once its
/// plan is met, so a day still in progress never reads as missed. A day's
/// credit is its check-ins over the per-day target, capped at one, so a habit
/// counted several times a day earns part of a day for part of its count. A
/// weekday's share is its credit summed over its days in the window, divided
/// by those days.
///
/// Only scheduled weekdays carry a share: every day for a daily habit or one
/// done some times a week, the chosen days for a habit on chosen weekdays.
/// A monthly habit, or a habit scheduled on a single weekday, has no rhythm
/// to compare (``make(habit:completions:today:calendar:)`` returns nil).
public struct HabitWeekdayRhythm: Equatable, Sendable {
  public struct Day: Equatable, Sendable {
    /// Monday-first weekday: 0 = Monday … 6 = Sunday.
    public let weekday: Int
    /// The days of this weekday in the window; zero for an unscheduled weekday.
    public let occurrences: Int
    /// Of those days, the ones with at least one check-in.
    public let daysWithCheckIns: Int
    /// The share of the plan met on this weekday, in `0...1`; nil for an
    /// unscheduled weekday.
    public let share: Double?
  }

  /// The seven weekdays, Monday first.
  public let days: [Day]
  /// The window's first day, at the start of that day in the given calendar;
  /// nil for a habit without check-ins.
  public let windowStart: Date?
  /// The window's length in days, today included.
  public let windowDays: Int

  /// The longest window: twelve weeks.
  public static let maximumWindowDays = 84
  /// The shortest window worth comparing: two weeks, so every weekday occurs
  /// at least twice.
  public static let minimumWindowDays = 14
  /// A highest and lowest share closer together than this read as an even
  /// week.
  public static let evenSpread = 0.1
  /// Shares within this of the highest, or of the lowest, tie with it: less
  /// than one day's difference over a twelve-week window. Smaller than half
  /// of ``evenSpread``, so no weekday ties with both ends.
  public static let tieTolerance = 0.04

  /// Whether the window is long enough to compare weekdays.
  public var hasEnoughHistory: Bool { windowDays >= Self.minimumWindowDays }

  /// The scheduled weekdays tied for the highest share (``tieTolerance``),
  /// Monday first; empty while the window is too short to compare or the
  /// week is even (``evenSpread``).
  public var strongestDays: [Int] { extremes.strongest }

  /// The scheduled weekdays tied for the lowest share, Monday first, under
  /// the same conditions as ``strongestDays``.
  public var weakestDays: [Int] { extremes.weakest }

  private var extremes: (strongest: [Int], weakest: [Int]) {
    guard hasEnoughHistory else { return ([], []) }
    let scheduled = days.compactMap { day in day.share.map { (weekday: day.weekday, share: $0) } }
    // The epsilon keeps a spread of exactly `evenSpread` (1.0 against 0.9)
    // from reading as even through floating-point rounding.
    guard scheduled.count >= 2,
      let high = scheduled.map(\.share).max(),
      let low = scheduled.map(\.share).min(),
      high - low >= Self.evenSpread - 1e-9
    else { return ([], []) }
    return (
      scheduled.filter { $0.share >= high - Self.tieTolerance }.map(\.weekday),
      scheduled.filter { $0.share <= low + Self.tieTolerance }.map(\.weekday)
    )
  }

  public init(days: [Day], windowStart: Date?, windowDays: Int) {
    self.days = days
    self.windowStart = windowStart
    self.windowDays = windowDays
  }

  /// The rhythm of `habit` over `completions` (its check-ins, `yyyy-MM-dd`
  /// dates with a count each) as of `today` in `calendar`; nil for a habit
  /// with no weekdays to compare. A habit without check-ins returns a rhythm
  /// with an empty window.
  public static func make(
    habit: LorvexHabit,
    completions: [HabitCompletionEntry],
    today: Date,
    calendar: Calendar
  ) -> HabitWeekdayRhythm? {
    guard let scheduled = scheduledWeekdays(for: habit), scheduled.count >= 2 else { return nil }
    let target = habit.frequencyType == "times_per_week" ? 1 : max(habit.targetCount, 1)
    let todayStart = calendar.startOfDay(for: today)

    var valueByDay: [Date: Int] = [:]
    for entry in completions where entry.value > 0 {
      guard let day = day(from: entry.completedDate, calendar: calendar), day <= todayStart else {
        continue
      }
      valueByDay[day, default: 0] += entry.value
    }

    guard let firstDay = valueByDay.keys.min(),
      let earliest = calendar.date(byAdding: .day, value: -(maximumWindowDays - 1), to: todayStart)
    else {
      return HabitWeekdayRhythm(days: emptyDays(scheduled: scheduled), windowStart: nil, windowDays: 0)
    }
    let start = max(firstDay, earliest)
    let windowDays = (calendar.dateComponents([.day], from: start, to: todayStart).day ?? 0) + 1

    var occurrences = Array(repeating: 0, count: 7)
    var withCheckIns = Array(repeating: 0, count: 7)
    var credit = Array(repeating: 0.0, count: 7)
    for offset in 0..<windowDays {
      guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
      let weekday = mondayFirstWeekday(of: day, calendar: calendar)
      guard scheduled.contains(weekday) else { continue }
      let value = valueByDay[day] ?? 0
      if day == todayStart && value < target { continue }
      occurrences[weekday] += 1
      if value > 0 { withCheckIns[weekday] += 1 }
      credit[weekday] += min(Double(value) / Double(target), 1)
    }

    let days = (0..<7).map { weekday in
      guard scheduled.contains(weekday) else {
        return Day(weekday: weekday, occurrences: 0, daysWithCheckIns: 0, share: nil)
      }
      let count = occurrences[weekday]
      return Day(
        weekday: weekday, occurrences: count, daysWithCheckIns: withCheckIns[weekday],
        share: count > 0 ? credit[weekday] / Double(count) : 0)
    }
    return HabitWeekdayRhythm(days: days, windowStart: start, windowDays: windowDays)
  }

  /// The weekdays `habit` is planned on, Monday-first; nil for a monthly
  /// habit, which is planned on a day of the month instead.
  static func scheduledWeekdays(for habit: LorvexHabit) -> Set<Int>? {
    switch habit.frequencyType {
    case "monthly":
      return nil
    case "weekly":
      let days = Set((habit.weekdays ?? []).filter { (0...6).contains($0) })
      return days.isEmpty ? Set(0...6) : days
    default:
      return Set(0...6)
    }
  }

  private static func emptyDays(scheduled: Set<Int>) -> [Day] {
    (0..<7).map { weekday in
      Day(
        weekday: weekday, occurrences: 0, daysWithCheckIns: 0,
        share: scheduled.contains(weekday) ? 0 : nil)
    }
  }

  /// 0 = Monday … 6 = Sunday, from the calendar's Sunday-first 1…7.
  static func mondayFirstWeekday(of date: Date, calendar: Calendar) -> Int {
    (calendar.component(.weekday, from: date) + 5) % 7
  }

  private static func day(from string: String, calendar: Calendar) -> Date? {
    let parts = string.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3,
      let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    else { return nil }
    return calendar.startOfDay(for: date)
  }
}
