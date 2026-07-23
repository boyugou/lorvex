import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

extension SwiftLorvexCoreService {
  /// The physical columns each habit read projects. The `weekly` weekday set
  /// lives in `habit_weekdays` (joined per row), not a column here.
  static let habitRowColumns =
    "id, name, icon, color, cue, frequency_type, per_period_target, day_of_month, "
    + "target_count, milestone_target, archived, position"

  static func loadHabitsSnapshot(
    _ db: Database, date: String, archived: Bool = false
  ) throws -> HabitCatalogSnapshot {
    let rows = try Row.fetchAll(
      db,
      sql: """
        SELECT \(habitRowColumns)
        FROM habits WHERE archived = ?
        ORDER BY position ASC, name COLLATE NOCASE ASC, id ASC
        """,
      arguments: [archived ? 1 : 0])
    let habits = try rows.map { try mapHabitRow(db, row: $0, date: date) }
    return HabitCatalogSnapshot(habits: habits)
  }

  static func habitColumnRow(_ db: Database, id: String) throws -> Row? {
    try Row.fetchOne(
      db,
      sql: "SELECT \(habitRowColumns) FROM habits WHERE id = ?",
      arguments: [id])
  }

  /// The `weekly` weekday set for a habit, Monday-first (0=Mon … 6=Sun), sorted
  /// ascending. Empty for every non-weekly cadence and for weekly-every-day.
  static func loadHabitWeekdayInts(_ db: Database, habitId: String) throws -> [Int] {
    try Int64.fetchAll(
      db, sql: "SELECT weekday FROM habit_weekdays WHERE habit_id = ? ORDER BY weekday ASC",
      arguments: [habitId]
    ).map { Int($0) }
  }

  /// Delete-then-insert the `habit_weekdays` rows for one habit. The child is a
  /// local materialization of the habit's `weekly` cadence; an empty set leaves
  /// no rows (the "every day" idiom, and the cleared state for a non-weekly
  /// cadence). Weekday ints are Monday-first (0=Mon … 6=Sun).
  static func replaceHabitWeekdays(
    _ db: Database, habitId: String, weekdays: [WeekDay]
  ) throws {
    try db.execute(sql: "DELETE FROM habit_weekdays WHERE habit_id = ?", arguments: [habitId])
    for day in weekdays {
      try db.execute(
        sql: "INSERT OR IGNORE INTO habit_weekdays (habit_id, weekday) VALUES (?, ?)",
        arguments: [habitId, day.rawValue])
    }
  }

  /// Map a stored `habits` row + `habit_weekdays` set + computed completion
  /// aggregates onto a `LorvexHabit`. `date` is the day used for
  /// `completionsToday`.
  static func mapHabitRow(_ db: Database, row: Row, date: String) throws -> LorvexHabit {
    let id: String = row["id"]
    let targetCount = row["target_count"] as Int64
    let frequencyType: String = row["frequency_type"]
    let weekdays = try loadHabitWeekdayInts(db, habitId: id)
    let cadence = try SwiftLorvexHabitDeserializers.cadence(
      frequencyType: frequencyType, weekdays: weekdays,
      perPeriodTarget: row["per_period_target"] as Int64,
      dayOfMonth: (row["day_of_month"] as Int64?).map { Int($0) })
    let completionsToday = try habitValueOnDate(db, habitId: id, date: date)
    let totalCompletions = try Int.fetchOne(
      db, sql: "SELECT COALESCE(SUM(value), 0) FROM habit_completions WHERE habit_id = ?",
      arguments: [id]) ?? 0
    let rate = try completionRate30d(
      db, habitId: id, cadence: cadence, targetCount: targetCount, today: date)
    let milestoneTarget = (row["milestone_target"] as Int64?).map { Int($0) }
    let metric = habitMilestoneMetric(for: cadence)
    let metricValue = try habitMilestoneMetricValue(
      db, habitId: id, metric: metric, cadence: cadence, targetCount: targetCount,
      totalCompletions: totalCompletions, today: date)
    let milestone = HabitMilestoneProjection.info(
      metric: metric, value: metricValue, target: milestoneTarget)
    return SwiftLorvexHabitDeserializers.habit(
      row, weekdays: weekdays, completionsToday: completionsToday,
      totalCompletions: totalCompletions, completionRate30d: rate,
      milestoneTarget: milestoneTarget, milestone: milestone)
  }

  /// The current milestone metric reading for a habit: total completions for the
  /// cumulative cadences (`.count`), or the current streak length for the streak
  /// cadences (`.streak`), computed relative to `today`. The streak matches
  /// `getHabitStats`' `currentStreak` (same domain helper, same inputs).
  static func habitMilestoneMetricValue(
    _ db: Database, habitId: String, metric: HabitMilestoneMetric, cadence: HabitCadence,
    targetCount: Int64, totalCompletions: Int, today: String
  ) throws -> Int {
    switch metric {
    case .count:
      return totalCompletions
    case .streak:
      let dateStrings = try habitMetCompletionDates(
        db, habitId: habitId, cadence: cadence,
        targetCount: targetCount, through: today)
      let dates = dateStrings.compactMap { lorvexDate($0) }
      let todayDate =
        lorvexDate(today) ?? LorvexDate(ymd: IsoDate.YMD(year: 1970, month: 1, day: 1))
      let streak = computeHabitCurrentStreak(
        dates: dates, today: todayDate,
        frequency: HabitStreakFrequency.fromWireString(cadence.toFields().frequencyType),
        targetCount: habitRequiredMetDaysPerStreakPeriod(cadence))
      return Int(streak)
    }
  }

  /// The milestone inputs for a habit, resolved once for a completion op so the
  /// before/after readings share the same cadence + target.
  struct HabitMilestoneContext {
    let cadence: HabitCadence
    let targetCount: Int64
    let milestoneTarget: Int?
    let metric: HabitMilestoneMetric
  }

  /// Resolve the milestone context from a `habitColumnRow` row (its
  /// `milestone_target` + cadence columns) plus the joined `habit_weekdays` set.
  static func habitMilestoneContext(
    _ db: Database, id: String, row: Row
  ) throws -> HabitMilestoneContext {
    let weekdays = try loadHabitWeekdayInts(db, habitId: id)
    let cadence = try SwiftLorvexHabitDeserializers.cadence(
      frequencyType: row["frequency_type"], weekdays: weekdays,
      perPeriodTarget: row["per_period_target"] as Int64,
      dayOfMonth: (row["day_of_month"] as Int64?).map { Int($0) })
    return HabitMilestoneContext(
      cadence: cadence,
      targetCount: row["target_count"] as Int64,
      milestoneTarget: (row["milestone_target"] as Int64?).map { Int($0) },
      metric: habitMilestoneMetric(for: cadence))
  }

  /// The habit's total completion value (SUM of per-day `value`), the `.count`
  /// milestone metric reading.
  static func habitTotalCompletions(_ db: Database, id: String) throws -> Int {
    try Int.fetchOne(
      db, sql: "SELECT COALESCE(SUM(value), 0) FROM habit_completions WHERE habit_id = ?",
      arguments: [id]) ?? 0
  }

  /// Stamp `justReached` on one habit's milestone standing inside a snapshot —
  /// how a completion op reports the milestone it just crossed. A nil `reached`
  /// leaves the snapshot untouched (the standing already carries a nil
  /// `justReached`).
  static func snapshot(
    _ snapshot: HabitCatalogSnapshot, settingJustReached reached: Int?, forHabit id: String
  ) -> HabitCatalogSnapshot {
    guard let reached else { return snapshot }
    var habits = snapshot.habits
    if let index = habits.firstIndex(where: { $0.id == id }), var milestone = habits[index].milestone
    {
      milestone.justReached = reached
      habits[index].milestone = milestone
    }
    return HabitCatalogSnapshot(habits: habits)
  }

  /// The `value` recorded for a habit on `date` (0 when no completion row).
  static func habitValueOnDate(_ db: Database, habitId: String, date: String) throws -> Int {
    Int(
      try Int64.fetchOne(
        db,
        sql: "SELECT value FROM habit_completions WHERE habit_id = ? AND completed_date = ?",
        arguments: [habitId, date]) ?? 0)
  }

  /// Append a `Patch<String>` column to an UPDATE SET clause (skip on `.unset`,
  /// SQL NULL on `.clear`, value on `.set`).
  static func appendPatch(
    _ setClauses: inout [String], _ args: inout [DatabaseValueConvertible?],
    column: String, patch: Patch<String>
  ) {
    switch patch {
    case .unset: return
    case .clear:
      setClauses.append("\(column) = ?"); args.append(nil)
    case .set(let value):
      setClauses.append("\(column) = ?"); args.append(value)
    }
  }
}
