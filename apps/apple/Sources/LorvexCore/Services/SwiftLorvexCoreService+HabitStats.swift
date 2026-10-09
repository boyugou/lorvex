import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

/// Habit streak and completion-rate statistics over the pure-Swift core.
///
/// `getHabitStats` reads the completion history for a habit and derives current
/// and longest streaks via `LorvexDomain`'s `computeHabitCurrentStreak` /
/// `computeHabitLongestStreak`, plus today's value, total completions, and the
/// trailing-30-day completion rate. A day counts as "completed" when its
/// `habit_completions.value >= target_count`.
/// `completionRate30d` is completed units over the cadence's scheduled
/// occurrences due across the habit's active window — the trailing 30 days, or
/// fewer for a habit younger than 30 days (see
/// ``completionRate30d(_:habitId:cadence:targetCount:today:)``).
///
/// Days the user skipped a daily or weekly habit are excused: they neither add to
/// nor end a streak and are not counted as due in the rate (see
/// ``habitExcusedDates(_:habitId:cadence:from:through:)``).
extension SwiftLorvexCoreService {

  public func getHabitStats(id: LorvexHabit.ID) async throws -> HabitStats {
    try read { db in
      guard let habitRow = try Row.fetchOne(
        db,
        sql: "SELECT name, frequency_type, per_period_target, day_of_month, target_count, "
          + "milestone_target FROM habits WHERE id = ?",
        arguments: [id])
      else { throw LorvexCoreError.notFound(entity: .habit, id: id) }

      let name: String = habitRow["name"]
      let frequencyType: String = habitRow["frequency_type"]
      let targetCount = habitRow["target_count"] as Int64
      let milestoneTarget = (habitRow["milestone_target"] as Int64?).map { Int($0) }
      let weekdays = try Self.loadHabitWeekdayInts(db, habitId: id)
      let cadence = try SwiftLorvexHabitDeserializers.cadence(
        frequencyType: frequencyType, weekdays: weekdays,
        perPeriodTarget: habitRow["per_period_target"] as Int64,
        dayOfMonth: (habitRow["day_of_month"] as Int64?).map { Int($0) })

      let todayStr = try WorkflowTimezone.todayYmdForConn(db)
      let dateStrings = try Self.habitMetCompletionDates(
        db, habitId: id, cadence: cadence, targetCount: targetCount, through: todayStr)
      let dates = dateStrings.compactMap { Self.lorvexDate($0) }
      let today = Self.lorvexDate(todayStr)
        ?? LorvexDate(ymd: IsoDate.YMD(year: 1970, month: 1, day: 1))
      let excused = try Self.habitExcusedDates(
        db, habitId: id, cadence: cadence, through: todayStr
      ).compactMap { Self.lorvexDate($0) }
      let streakFreq = HabitStreakFrequency.fromWireString(frequencyType)
      let requiredPerPeriod = habitRequiredMetDaysPerStreakPeriod(cadence)
      let current = computeHabitCurrentStreak(
        dates: dates, today: today, frequency: streakFreq, targetCount: requiredPerPeriod,
        excused: excused)
      let best = computeHabitLongestStreak(
        dates: dates, frequency: streakFreq, targetCount: requiredPerPeriod, excused: excused)

      let totalCompletions = try Int.fetchOne(
        db, sql: "SELECT COALESCE(SUM(value), 0) FROM habit_completions WHERE habit_id = ?",
        arguments: [id]) ?? 0
      let completionsToday = try Self.habitValueOnDate(db, habitId: id, date: todayStr)
      let rate = try Self.completionRate30d(
        db, habitId: id, cadence: cadence, targetCount: targetCount, today: todayStr)
      // Completed days covering the current and previous five whole calendar
      // months, ascending, for the card's activity strip. A fixed day count is
      // insufficient: on a long-month boundary it can drop March 1 while the
      // six-cell monthly strip still displays March.
      let recentCutoff = Self.habitVisualizationHistoryCutoff(today: todayStr)
      let recentCompletions = dateStrings.filter { $0 >= recentCutoff && $0 <= todayStr }.sorted()
      // Skipped days reach back a year, as far as the longest history grid.
      let recentSkips = try Self.habitSkipDates(
        db, habitId: id,
        from: LorvexDateFormatters.ymdUTCAddingDays(todayStr, days: -371) ?? recentCutoff,
        through: todayStr)

      // The milestone metric reading is the streak length for streak cadences,
      // the total completion count for cumulative cadences — the same split
      // `get_habits` surfaces.
      let metric = habitMilestoneMetric(for: cadence)
      let metricValue = metric == .count ? totalCompletions : Int(current)
      let standing = habitMilestoneStanding(
        value: metricValue, target: milestoneTarget, metric: metric)

      return HabitStats(
        habitID: id,
        name: name,
        currentStreak: Int(current),
        bestStreak: Int(best),
        totalCompletions: totalCompletions,
        completionsToday: completionsToday,
        completionRate30d: rate,
        progressKind: habitProgressKind(targetCount: targetCount).rawValue,
        recentCompletions: recentCompletions,
        recentSkips: recentSkips,
        milestoneTarget: milestoneTarget,
        metric: HabitMilestoneProjection.metricString(for: metric),
        nextMilestone: standing.nextMilestone,
        progressToNext: standing.progressToNext)
    }
  }

  /// Canonical streak input: one scheduled date per day whose completion value
  /// reached the habit's per-day target, bounded by the caller's
  /// configured-timezone today. The bound keeps clock-skewed, imported, or
  /// deliberately future rows from creating either a current or historical
  /// streak before that day arrives; cadence filtering prevents an off-schedule
  /// pinned-weekday completion from satisfying the week.
  static func habitMetCompletionDates(
    _ db: Database, habitId: String, cadence: HabitCadence,
    targetCount: Int64, through today: String
  ) throws -> [String] {
    let candidates = try String.fetchAll(
      db,
      sql: """
        SELECT completed_date FROM habit_completions
        WHERE habit_id = ? AND value >= ? AND completed_date <= ?
        """,
      arguments: [habitId, targetCount, today])
    return candidates.filter { raw in
      guard let date = lorvexDate(raw) else { return false }
      return isHabitScheduledOnDay(cadence, date)
    }
  }

  /// The dates in `from...through` the user skipped a habit, ascending, whatever
  /// its cadence. A day that also holds a check-in is left out: the check-in
  /// outranks the skip, so the day reads as kept.
  static func habitSkipDates(
    _ db: Database, habitId: String, from: String, through: String
  ) throws -> [String] {
    try String.fetchAll(
      db,
      sql: """
        SELECT s.skipped_date FROM habit_skips s
        WHERE s.habit_id = ?1 AND s.skipped_date >= ?2 AND s.skipped_date <= ?3
          AND NOT EXISTS (
            SELECT 1 FROM habit_completions c
            WHERE c.habit_id = s.habit_id AND c.completed_date = s.skipped_date
              AND c.value > 0)
        ORDER BY s.skipped_date ASC
        """,
      arguments: [habitId, from, through])
  }

  /// The skipped dates that excuse a streak or the adherence rate: those of
  /// ``habitSkipDates(_:habitId:from:through:)`` on which a daily or weekly habit
  /// was scheduled. A monthly or times-per-week habit excuses nothing, since its
  /// quota belongs to a period and a skip only sets the habit aside for the day.
  /// `from` nil reaches back to the habit's first skip.
  static func habitExcusedDates(
    _ db: Database, habitId: String, cadence: HabitCadence,
    from: String? = nil, through today: String
  ) throws -> [String] {
    switch cadence {
    case .daily, .weekly: break
    case .monthly, .timesPerWeek: return []
    }
    return try habitSkipDates(
      db, habitId: habitId, from: from ?? "0000-01-01", through: today
    ).filter { raw in
      guard let date = lorvexDate(raw) else { return false }
      return isHabitScheduledOnDay(cadence, date)
    }
  }

  /// Whether the habit has a skip row for `date`.
  static func habitIsSkipped(_ db: Database, habitId: String, date: String) throws -> Bool {
    try Int.fetchOne(
      db,
      sql: "SELECT 1 FROM habit_skips WHERE habit_id = ? AND skipped_date = ?",
      arguments: [habitId, date]) != nil
  }

  static func habitVisualizationHistoryCutoff(today: String) -> String {
    guard let ymd = IsoDate.parse(today) else { return today }
    var year = ymd.year
    var month = ymd.month - 5
    if month <= 0 {
      year -= 1
      month += 12
    }
    return IsoDate.YMD(year: year, month: month, day: 1).canonicalString
  }

  /// Fraction of the cadence's scheduled occurrences met over the habit's active
  /// window ending on `today`, clamped to `[0, 1]`. The numerator is the SUM of
  /// completion `value`s in the window; the denominator is
  /// ``LorvexDomain/habitScheduledOccurrencesDue(_:targetCount:from:to:)`` — the
  /// occurrences the cadence's schedule actually made due in the window,
  /// respecting which weekdays / which day-of-month are pinned, rather than a
  /// linear pro-rate of a per-period quota.
  ///
  /// The active window is the later of `today-29` and the habit's creation day,
  /// so a habit younger than 30 days is scored only over the days it has been
  /// active; a habit older than 30 days keeps the full 30-day window. Scoring a
  /// 2-day-old perfect daily habit over its 2 active days reports ~100% rather
  /// than ~7% against a full 30-day expectation.
  ///
  /// When no scheduled occurrence has come due in the window — a pinned-weekday
  /// or monthly habit created before its first scheduled day — nothing was due,
  /// so nothing has been missed and the rate is a full `1.0` rather than a
  /// spurious `0`. Daily, weekly-every-day, and `times_per_week` habits always
  /// have at least one due occurrence in a non-empty window, so this only applies
  /// to schedule-pinned cadences whose first occurrence has not yet come round.
  /// A day the user skipped a daily or weekly habit is not due, so a skip is not
  /// counted as a miss; a window whose every due day was skipped reads `1.0` the
  /// same way.
  static func completionRate30d(
    _ db: Database, habitId: String, cadence: HabitCadence, targetCount: Int64, today: String
  ) throws -> Double {
    // Both window bounds must use the configured timezone. Deriving the lower
    // bound from a device-local Calendar made the window 29 or 31 days when the
    // configured timezone differed from the device's across a day boundary,
    // while the upper bound (`today`) already comes from the configured tz.
    // `>= today-29` is the inclusive 30-day window.
    let windowStart = try WorkflowTimezone.datePlusDaysYmdForConn(db, days: -29)
    let fromStr = try Self.adherenceWindowStart(
      db, habitId: habitId, windowStart: windowStart, today: today)
    let completedValue = try Int.fetchOne(
      db,
      sql: """
        SELECT COALESCE(SUM(value), 0) FROM habit_completions
        WHERE habit_id = ? AND completed_date >= ? AND completed_date <= ?
        """,
      arguments: [habitId, fromStr, today]) ?? 0
    guard
      let fromDate = Self.lorvexDate(fromStr),
      let toDate = Self.lorvexDate(today)
    else { return 0 }
    let excused = try Self.habitExcusedDates(
      db, habitId: habitId, cadence: cadence, from: fromStr, through: today
    ).compactMap { Self.lorvexDate($0) }
    let expected = habitScheduledOccurrencesDue(
      cadence, targetCount: targetCount, from: fromDate, to: toDate, excused: excused)
    guard expected > 0 else { return 1.0 }
    return min(1.0, Double(completedValue) / expected)
  }

  /// Inclusive lower bound (`YYYY-MM-DD`) of the adherence window: the later of
  /// the trailing-30-day `windowStart` and the habit's creation day, projected
  /// into the configured timezone and clamped to `today`. A future-dated
  /// `created_at` (peer clock skew) collapses to `today` — a one-day window —
  /// rather than opening a window before it. Falls back to `windowStart` when
  /// the habit row or its `created_at` is unreadable, preserving the full
  /// 30-day window.
  static func adherenceWindowStart(
    _ db: Database, habitId: String, windowStart: String, today: String
  ) throws -> String {
    guard
      let createdRaw = try String.fetchOne(
        db, sql: "SELECT created_at FROM habits WHERE id = ?", arguments: [habitId]),
      let created = SyncTimestamp.parse(createdRaw)
    else { return windowStart }
    let createdYmd = try WorkflowTimezone.ymdForConn(db, instant: created.date)
    // Canonical zero-padded `YYYY-MM-DD` strings order chronologically under
    // lexicographic compare, so min/max on the strings is calendar min/max.
    let effectiveCreated = min(createdYmd, today)
    return max(windowStart, effectiveCreated)
  }

  static func lorvexDate(_ ymd: String) -> LorvexDate? {
    if case .success(let d) = LorvexDate.parse(ymd) { return d }
    return nil
  }
}
