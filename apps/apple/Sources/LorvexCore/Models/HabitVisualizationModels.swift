import Foundation

/// Pure, deterministic computation for the habit completion heatmap.
///
/// All time inputs are explicit parameters so results are reproducible and
/// testable; callers decide the reference end date and calendar.
public enum HabitHeatmapModel {
  public enum Intensity: Equatable, Hashable, Sendable {
    case absent
    case none
    case partial
    case met
  }

  public struct Cell: Equatable, Identifiable, Sendable {
    public var date: String
    public var intensity: Intensity
    public var value: Int
    public var slot: Int
    /// Graded fill step for the heatmap ramp: 0 = no activity, 4 = met, 1…3 =
    /// partial days bucketed by completion ratio. Finer than ``intensity`` (which
    /// stays a coarse none/partial/met classification); a graded surface reads
    /// this while a two-tone one can still read ``intensity``.
    public var level: Int

    public var id: Int { slot }

    public init(date: String, intensity: Intensity, value: Int, slot: Int, level: Int = 0) {
      self.date = date
      self.intensity = intensity
      self.value = value
      self.slot = slot
      self.level = level
    }
  }

  public struct Grid: Equatable, Sendable {
    public var columns: [[Cell]]
    public var monthLabels: [String?]

    public static let empty = Grid(columns: [], monthLabels: [])

    public init(columns: [[Cell]], monthLabels: [String?]) {
      self.columns = columns
      self.monthLabels = monthLabels
    }
  }

  /// The heatmap's `weeks` columns, oldest first, ending with the week of
  /// `endDate`. `calendar` lays out the weeks (its first weekday starts a
  /// column) and writes the day keys the completions are matched on. A
  /// column's month label is set where a month of `locale`'s own calendar
  /// begins, on or before `endDate`, and names that month the way `locale`
  /// abbreviates it: Gregorian months in most regions, Hijri months where the
  /// locale's calendar is Islamic, as every other date in the app is shown.
  public static func makeGrid(
    completions: [HabitCompletionEntry],
    targetCount: Int,
    weeks: Int,
    endDate: Date,
    calendar: Calendar,
    locale: Locale = LorvexClockFormat.displayLocale
  ) -> Grid {
    guard weeks > 0 else { return .empty }
    let target = max(1, targetCount)

    var valueByDate: [String: Int] = [:]
    for entry in completions {
      valueByDate[entry.completedDate, default: 0] += entry.value
    }

    let formatter = dayKeyFormatter(calendar: calendar)
    let endDay = calendar.startOfDay(for: endDate)
    guard
      let endWeekStart = calendar.dateInterval(of: .weekOfYear, for: endDay)?.start,
      let gridStart = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: endWeekStart)
    else {
      return .empty
    }

    var columns: [[Cell]] = []
    var monthLabels: [String?] = []
    let monthCalendar = LorvexDateFormatters.displayCalendar(timeZone: calendar.timeZone, locale: locale)

    for week in 0..<weeks {
      guard let weekStart = calendar.date(byAdding: .weekOfYear, value: week, to: gridStart) else {
        continue
      }
      var column: [Cell] = []
      var label: String?
      for dayOffset in 0..<7 {
        let slot = week * 7 + dayOffset
        guard let day = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) else {
          column.append(Cell(date: "", intensity: .absent, value: 0, slot: slot))
          continue
        }
        if day > endDay {
          column.append(Cell(date: "", intensity: .absent, value: 0, slot: slot))
          continue
        }
        let key = formatter.string(from: day)
        let value = valueByDate[key] ?? 0
        let intensity: Intensity
        if value >= target {
          intensity = .met
        } else if value > 0 {
          intensity = .partial
        } else {
          intensity = .none
        }
        column.append(
          Cell(
            date: key, intensity: intensity, value: value, slot: slot,
            level: level(value: value, target: target)))

        if monthCalendar.component(.day, from: day) == 1 {
          label = LorvexDateFormatters.string(
            day, template: "MMM", timeZone: calendar.timeZone, locale: locale)
        }
      }
      columns.append(column)
      monthLabels.append(label)
    }

    return Grid(columns: columns, monthLabels: monthLabels)
  }

  /// Graded fill step for a day's summed completions against the habit's target,
  /// giving the heatmap a GitHub-style five-shade scale rather than a coarse
  /// met/partial split: 0 = no activity, 4 = met (target reached or exceeded),
  /// and 1…3 = partial days bucketed by the completion ratio (`< 1/3`, `< 2/3`,
  /// else). A binary habit (target 1) therefore only ever renders 0 or 4 — a day
  /// is done or not — while an accumulative habit fills the intermediate steps.
  public static func level(value: Int, target: Int) -> Int {
    guard value > 0 else { return 0 }
    let clampedTarget = max(1, target)
    guard value < clampedTarget else { return 4 }
    let ratio = Double(value) / Double(clampedTarget)
    switch ratio {
    case ..<(1.0 / 3.0): return 1
    case ..<(2.0 / 3.0): return 2
    default: return 3
    }
  }

  /// The heatmap's row labels: the very short weekday symbols in `locale`'s
  /// language ("S", "M", … or "日", "一", …), rotated so the first row is
  /// `calendar.firstWeekday`. The grid's calendar carries no locale of its own —
  /// it fixes only the week layout and the date keys — so the language comes
  /// from `locale` while the row order stays the grid's.
  public static func weekdayInitials(calendar: Calendar, locale: Locale = .current) -> [String] {
    var localized = calendar
    localized.locale = locale
    let symbols = localized.veryShortWeekdaySymbols
    let first = calendar.firstWeekday - 1
    guard symbols.count == 7, first >= 0, first < 7 else { return symbols }
    return Array(symbols[first...] + symbols[..<first])
  }

  private static func dayKeyFormatter(calendar: Calendar) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }

  /// Where a heatmap draws its month labels, from each week column's label
  /// width (zero where no month begins) and the x its column starts at (nil
  /// for a column the layout does not show), oldest first.
  ///
  /// A label starts at its column and runs over the weeks after it, but never
  /// past `trailingEdge`, the newest column's end: a month that began in the
  /// last weeks shifts back to end there. Walking from the newest month, a
  /// label that would then come within `gap` of the next newer label shown,
  /// or start before `leadingEdge`, is left out (nil), so the most recent
  /// months keep their names and no two names overlap, however long a
  /// language's month names run.
  public static func monthLabelPositions(
    starts: [CGFloat?], widths: [CGFloat], leadingEdge: CGFloat, trailingEdge: CGFloat,
    gap: CGFloat
  ) -> [CGFloat?] {
    var positions = [CGFloat?](repeating: nil, count: min(starts.count, widths.count))
    var nextShownStart = CGFloat.infinity
    for index in positions.indices.reversed() {
      guard let start = starts[index], widths[index] > 0 else { continue }
      let x = min(start, trailingEdge - widths[index])
      guard x >= leadingEdge, x + widths[index] + gap <= nextShownStart else { continue }
      positions[index] = x
      nextShownStart = x
    }
    return positions
  }
}

public enum HabitRhythmStrip {
  public enum Granularity: Equatable, Sendable { case day, week, month }

  public static func granularity(forFrequencyType frequencyType: String) -> Granularity {
    switch frequencyType {
    case "monthly": return .month
    case "weekly", "times_per_week": return .week
    default: return .day
    }
  }

  public struct Cell: Equatable, Sendable {
    public let filled: Bool
    public let isCurrent: Bool

    public init(filled: Bool, isCurrent: Bool) {
      self.filled = filled
      self.isCurrent = isCurrent
    }
  }

  /// The strip's cells, oldest first: the last 7 days, 8 weeks, or 6 months,
  /// each filled when its met days reach the habit's per-period target.
  /// Periods are Gregorian days, ISO weeks, and months in `timeZone`, the
  /// calendar the completion keys are written in.
  public static func cells(
    completions: Set<String>,
    habit: LorvexHabit,
    today: Date,
    timeZone: TimeZone = .current
  ) -> [Cell] {
    let calendar = habitCalendar(timeZone)
    let granularity = granularity(forFrequencyType: habit.frequencyType)
    let requiredMetDays = requiredMetDaysPerPeriod(habit: habit)
    let count: Int
    switch granularity {
    case .day: count = 7
    case .week: count = 8
    case .month: count = 6
    }
    return (0..<count).map { index in
      let periodsAgo = count - 1 - index
      return Cell(
        filled: completionCount(
          completions: completions, granularity: granularity, periodsAgo: periodsAgo,
          today: today, calendar: calendar) >= requiredMetDays,
        isCurrent: periodsAgo == 0)
    }
  }

  /// Narrow weekday names ("M", "T", "W") under a daily habit's seven cells,
  /// oldest first, ending on the day `today` falls on in `timeZone`, so the
  /// strip reads as this week rather than seven anonymous marks. Empty for a
  /// weekly or monthly strip.
  public static func dayLabels(habit: LorvexHabit, today: Date, timeZone: TimeZone = .current) -> [String] {
    guard granularity(forFrequencyType: habit.frequencyType) == .day else { return [] }
    let calendar = habitCalendar(timeZone)
    var style = Date.FormatStyle().weekday(.narrow)
    style.timeZone = timeZone
    return (0..<7).reversed().compactMap { daysAgo in
      calendar.date(byAdding: .day, value: -daysAgo, to: today)?.formatted(style)
    }
  }

  private static func completionCount(
    completions: Set<String>, granularity: Granularity, periodsAgo: Int, today: Date,
    calendar: Calendar
  ) -> Int {
    switch granularity {
    case .day:
      guard let day = calendar.date(byAdding: .day, value: -periodsAgo, to: today) else {
        return 0
      }
      return completions.contains(ymd(day, calendar)) ? 1 : 0
    case .week:
      var weekCalendar = calendar
      weekCalendar.firstWeekday = 2
      weekCalendar.minimumDaysInFirstWeek = 4
      guard
        let anchor = weekCalendar.date(
          byAdding: .weekOfYear, value: -periodsAgo, to: today),
        let interval = weekCalendar.dateInterval(of: .weekOfYear, for: anchor)
      else { return 0 }
      return completions.reduce(into: 0) { count, string in
        guard let date = date(string, weekCalendar), interval.contains(date) else { return }
        count += 1
      }
    case .month:
      guard let monthDate = calendar.date(byAdding: .month, value: -periodsAgo, to: today) else {
        return 0
      }
      let target = calendar.dateComponents([.year, .month], from: monthDate)
      return completions.reduce(into: 0) { count, string in
        guard let date = date(string, calendar) else { return }
        let comps = calendar.dateComponents([.year, .month], from: date)
        if comps.year == target.year && comps.month == target.month { count += 1 }
      }
    }
  }

  private static func date(_ string: String, _ calendar: Calendar) -> Date? {
    let parts = string.split(separator: "-")
    guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]),
      let day = Int(parts[2])
    else { return nil }
    return calendar.date(from: DateComponents(year: year, month: month, day: day))
  }

  private static func ymd(_ date: Date, _ calendar: Calendar) -> String {
    let comps = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
  }
}

public enum HabitPeriodProgress {
  public struct Value: Equatable, Sendable {
    public let completed: Int
    public let required: Int
    public var isComplete: Bool { completed >= max(required, 1) }

    public init(completed: Int, required: Int) {
      self.completed = completed
      self.required = required
    }
  }

  /// The period ``current(habit:recentCompletions:today:timeZone:)`` counts
  /// over: the day for a habit with a per-day target above one, whatever its
  /// cadence, otherwise the cadence's own day, week, or month.
  public static func period(for habit: LorvexHabit) -> HabitRhythmStrip.Granularity {
    if max(habit.targetCount, 1) > 1 { return .day }
    return HabitRhythmStrip.granularity(forFrequencyType: habit.frequencyType)
  }

  /// The met days of the period `today` falls in, against the habit's target.
  /// Weeks are ISO weeks and months Gregorian months in `timeZone`, the
  /// calendar the completion keys are written in.
  public static func current(
    habit: LorvexHabit,
    recentCompletions: [String],
    today: Date = Date(),
    timeZone: TimeZone = .current
  ) -> Value {
    let calendar = habitCalendar(timeZone)
    let target = max(habit.targetCount, 1)
    switch period(for: habit) {
    case .day:
      return Value(completed: max(habit.completionsToday, 0), required: target)
    case .week:
      return Value(
        completed: completionsInCurrentWeek(recentCompletions, today: today, calendar: calendar),
        required: requiredMetDaysPerPeriod(habit: habit))
    case .month:
      return Value(
        completed: completionsInCurrentMonth(recentCompletions, today: today, calendar: calendar),
        required: target)
    }
  }

  private static func completionsInCurrentWeek(
    _ completions: [String], today: Date, calendar: Calendar
  ) -> Int {
    var weekCalendar = calendar
    weekCalendar.firstWeekday = 2
    weekCalendar.minimumDaysInFirstWeek = 4
    guard let interval = weekCalendar.dateInterval(of: .weekOfYear, for: today) else { return 0 }
    return completions.filter { string in
      guard let date = date(string, weekCalendar) else { return false }
      return interval.contains(date)
    }.count
  }

  private static func completionsInCurrentMonth(
    _ completions: [String], today: Date, calendar: Calendar
  ) -> Int {
    let target = calendar.dateComponents([.year, .month], from: today)
    return completions.filter { string in
      guard let date = date(string, calendar) else { return false }
      let comps = calendar.dateComponents([.year, .month], from: date)
      return comps.year == target.year && comps.month == target.month
    }.count
  }

  private static func date(_ string: String, _ calendar: Calendar) -> Date? {
    let parts = string.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
  }
}

/// The number of independently met dates that completes one displayed cadence
/// period. `recentCompletions` already contains only dates whose per-day
/// `target_count` was reached, so that target must not be multiplied again.
private func requiredMetDaysPerPeriod(habit: LorvexHabit) -> Int {
  switch habit.frequencyType {
  case "weekly":
    guard let weekdays = habit.weekdays, !weekdays.isEmpty else { return 7 }
    return max(Set(weekdays).count, 1)
  case "times_per_week":
    return max(habit.perPeriodTarget ?? 1, 1)
  default:
    return 1
  }
}

/// The Gregorian calendar in `timeZone`, the calendar habit completion keys
/// (`YYYY-MM-DD`) are written in, whatever calendar the user's region uses.
private func habitCalendar(_ timeZone: TimeZone) -> Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = timeZone
  return calendar
}
