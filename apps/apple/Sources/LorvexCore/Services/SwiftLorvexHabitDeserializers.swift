import Foundation
import GRDB
import LorvexDomain
import LorvexWorkflow

/// Maps `habits` / `habit_completions` / `habit_reminder_policies` rows onto the
/// app's habit model types, preserving the stable field shapes
/// (`completions_today`, `total_completions`, `completion_rate_30d`,
/// `progress_kind`, …).
///
/// The pure-Swift core has no habit CRUD/completion repo, so the per-habit
/// aggregates are computed here from `habit_completions` using the domain
/// scheduling helpers (`habitScheduledOccurrencesDue`).
enum SwiftLorvexHabitDeserializers {

  /// Bridge a boundary ``HabitCadenceInput`` into the domain ``HabitCadence``,
  /// used by the create / update / import write paths.
  ///
  /// Malformed cadence input is REJECTED, not silently coerced: an out-of-range
  /// weekday int, an out-of-range `day_of_month`, an unknown `frequency_type`, or
  /// a non-positive `per_period_target` for a `times_per_week` cadence each throw
  /// a clear error (the last two via ``HabitCadence/fromFields(_:)``). A silent
  /// drop would quietly change which days a habit is scheduled on.
  static func cadence(from input: HabitCadenceInput) throws -> HabitCadence {
    let weekdays = try validatedWeekdays(input.weekdays)
    try validateDayOfMonth(input.dayOfMonth)
    return try HabitCadence.fromFields(
      HabitFrequencyFields(
        frequencyType: input.frequencyType,
        weekdays: weekdays,
        perPeriodTarget: input.perPeriodTarget.map { Int64($0) } ?? 1,
        dayOfMonth: input.dayOfMonth))
  }

  /// Convert boundary weekday ints (Monday-first 0=Mon … 6=Sun) to typed
  /// ``WeekDay``s, rejecting any int outside `0...6`. A nil set passes through.
  static func validatedWeekdays(_ weekdays: [Int]?) throws -> [WeekDay]? {
    guard let weekdays else { return nil }
    return try weekdays.map { raw in
      guard let day = WeekDay(rawValue: raw) else {
        throw LorvexCoreError.unsupportedOperation(
          "weekdays entries must be integers 0 (Mon) … 6 (Sun); got \(raw).")
      }
      return day
    }
  }

  /// Reject a supplied `day_of_month` outside `1...31` rather than coercing it to
  /// "unspecified". A nil value passes through (a monthly reminder falls back to
  /// the 1st).
  static func validateDayOfMonth(_ day: Int?) throws {
    guard let day else { return }
    guard (1...31).contains(day) else {
      throw LorvexCoreError.unsupportedOperation(
        "day_of_month must be between 1 and 31; got \(day).")
    }
  }

  /// Decode the cadence from a habit row's typed columns + `habit_weekdays`
  /// child. A stored row that violates the cadence contract — an unknown
  /// `frequency_type`, an out-of-range weekday int, an out-of-range
  /// `day_of_month`, or a non-positive `per_period_target` for `times_per_week`
  /// — throws (via the same validators as the write path) rather than silently
  /// coercing to `.daily`, which would quietly change which days the habit is
  /// scheduled on.
  static func cadence(
    frequencyType: String, weekdays: [Int], perPeriodTarget: Int64, dayOfMonth: Int?
  ) throws -> HabitCadence {
    let days = try validatedWeekdays(weekdays)
    try validateDayOfMonth(dayOfMonth)
    return try HabitCadence.fromFields(
      HabitFrequencyFields(
        frequencyType: frequencyType, weekdays: days, perPeriodTarget: perPeriodTarget,
        dayOfMonth: dayOfMonth))
  }

  /// Map a `habits` row (plus its `habit_weekdays` set and computed completion
  /// aggregates) onto a `LorvexHabit`. `row` carries the stored columns; the
  /// three completion aggregates are computed by the caller from
  /// `habit_completions`. `weekdays` is Monday-first (0=Mon … 6=Sun).
  static func habit(
    _ row: Row,
    weekdays: [Int],
    completionsToday: Int,
    totalCompletions: Int,
    completionRate30d: Double,
    milestoneTarget: Int?,
    milestone: HabitMilestoneInfo?
  ) -> LorvexHabit {
    let frequencyType: String = row["frequency_type"]
    let perPeriodTarget = row["per_period_target"] as Int64
    let dayOfMonth = (row["day_of_month"] as Int64?).map { Int($0) }
    // Surface cadence detail only for the cadence that owns it, so the edit
    // sheet and MCP response never carry a stale weekday set on a daily habit.
    let surfacedWeekdays = frequencyType == "weekly" && !weekdays.isEmpty ? weekdays : nil
    return LorvexHabit(
      id: row["id"],
      name: row["name"],
      icon: row["icon"],
      color: row["color"],
      cue: row["cue"],
      frequencyType: frequencyType,
      targetCount: Int(row["target_count"] as Int64),
      completionsToday: completionsToday,
      totalCompletions: totalCompletions,
      completionRate30d: completionRate30d,
      archived: (row["archived"] as Int64) != 0,
      position: (row["position"] as Int64?) ?? 0,
      weekdays: surfacedWeekdays,
      perPeriodTarget: frequencyType == "times_per_week" ? Int(perPeriodTarget) : nil,
      dayOfMonth: frequencyType == "monthly" ? dayOfMonth : nil,
      milestoneTarget: milestoneTarget,
      milestone: milestone)
  }

  /// Map a `habit_completions` row onto a `HabitCompletionEntry`.
  static func completion(_ row: Row) -> HabitCompletionEntry {
    HabitCompletionEntry(
      habitID: row["habit_id"],
      completedDate: row["completed_date"],
      value: Int(row["value"] as Int64),
      note: row["note"],
      createdAt: row["created_at"],
      updatedAt: row["updated_at"])
  }

  /// Map a core `HabitReminderOps.HabitReminderPolicyRow` (habit name joined in)
  /// onto a `HabitReminderPolicy`.
  static func reminderPolicy(_ row: HabitReminderOps.HabitReminderPolicyRow) -> HabitReminderPolicy {
    HabitReminderPolicy(
      id: row.id,
      habitID: row.habitId,
      habitName: row.habitName,
      reminderTime: row.reminderTime,
      enabled: row.enabled,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt)
  }
}
