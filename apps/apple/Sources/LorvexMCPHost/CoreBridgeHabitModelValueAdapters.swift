import Foundation
import LorvexCore
import MCP

/// Maps the `LorvexCore` habit model types onto the MCP `Value` JSON shapes the
/// habit tool handlers return. Field names and shapes mirror the contract
/// expected by existing MCP clients, so external integrations see stable
/// objects while the implementation stays pure Swift.
extension CoreBridgeClient {
  static func habitValue(from habit: LorvexHabit) -> Value {
    .object([
      "id": .string(habit.id),
      "name": .string(habit.name),
      "cue": habit.cue.map(Value.string) ?? .null,
      "icon": habit.icon.map(Value.string) ?? .null,
      "color": habit.color.map(Value.string) ?? .null,
      "frequency_type": .string(habit.frequencyType),
      // Typed cadence detail: `weekdays` (Monday-first 0=Mon … 6=Sun) for a
      // weekly habit, `per_period_target` for a times-per-week habit,
      // `day_of_month` for a monthly habit. Each is null for the cadences that
      // don't own it.
      "weekdays": habit.weekdays.map { .array($0.map(Value.int)) } ?? .null,
      "per_period_target": habit.perPeriodTarget.map(Value.int) ?? .null,
      "day_of_month": habit.dayOfMonth.map(Value.int) ?? .null,
      "target_count": .int(habit.targetCount),
      "completions_today": .int(habit.completionsToday),
      "total_completions": .int(habit.totalCompletions),
      "archived": .bool(habit.archived),
      // Milestone standing: `milestone_metric` says which reading `milestone_value`
      // holds (streak length vs cumulative count); `next_milestone` +
      // `progress_to_next` track the run toward the next ladder rung / user target.
      "milestone_target": habit.milestoneTarget.map(Value.int) ?? .null,
      "milestone_metric": .string(habit.milestone?.metric ?? "streak"),
      "milestone_value": .int(habit.milestone?.value ?? 0),
      "next_milestone": .int(habit.milestone?.nextMilestone ?? 0),
      "progress_to_next": .double(habit.milestone?.progressToNext ?? 0),
    ])
  }

  /// The habit object for a completion response: the full habit plus
  /// `reached_milestone` — the milestone this completion just crossed, or null
  /// when it crossed none. Carried from the model's `milestone.justReached`,
  /// which the completion op stamps.
  static func habitCompletionValue(from habit: LorvexHabit) -> Value {
    guard case .object(var dict) = habitValue(from: habit) else { return habitValue(from: habit) }
    dict["reached_milestone"] = habit.milestone?.justReached.map(Value.int) ?? .null
    return .object(dict)
  }

  /// The habit object enriched with the streak/rate fields `get_habit_stats`
  /// computes — `current_streak`, `best_streak`, `completion_rate_30d`, and
  /// `progress_kind` — for `get_habits(include_stats: true)`. Only the
  /// stats-only fields are layered on; the milestone/count fields ``habitValue``
  /// already carries are left unchanged, so a habit read either way agrees on
  /// every shared key.
  static func habitValue(from habit: LorvexHabit, stats: HabitStats) -> Value {
    guard case .object(var dict) = habitValue(from: habit) else { return habitValue(from: habit) }
    dict["current_streak"] = .int(stats.currentStreak)
    dict["best_streak"] = .int(stats.bestStreak)
    dict["completion_rate_30d"] = .double(stats.completionRate30d)
    dict["progress_kind"] = .string(stats.progressKind)
    return .object(dict)
  }

  static func habitReminderPolicyValue(from policy: HabitReminderPolicy) -> Value {
    .object([
      "id": .string(policy.id),
      "habit_id": .string(policy.habitID),
      "habit_name": .string(policy.habitName),
      "reminder_time": .string(policy.reminderTime),
      "enabled": .bool(policy.enabled),
      "created_at": .string(policy.createdAt),
      "updated_at": .string(policy.updatedAt),
    ])
  }

  /// Render a habit-completions page inside the shared pagination envelope.
  ///
  /// The caller fetches `limit + 1` rows so truncation is real: if the snapshot
  /// holds more than `limit`, the extra row is dropped, `truncated` is true, and
  /// `total_matching` is `null` (an honest "unknown, more exist" rather than a
  /// fabricated total). `days` reflects the returned page, not the full history.
  static func habitCompletionsValue(
    from snapshot: HabitCompletionsSnapshot, limit: Int
  ) -> Value {
    let truncated = snapshot.completions.count > limit
    let page = Array(snapshot.completions.prefix(limit))
    let entries: [Value] = page.map { entry in
      .object([
        "habit_id": .string(entry.habitID),
        "completed_date": .string(entry.completedDate),
        "value": .int(entry.value),
        "note": entry.note.map(Value.string) ?? .null,
        "created_at": .string(entry.createdAt),
        "updated_at": .string(entry.updatedAt),
      ])
    }
    return MCPPagination.object(
      domain: [
        "habit_id": .string(snapshot.habitID),
        "days": .int(page.count),
        "completions": .array(entries),
      ],
      totalMatching: truncated ? nil : page.count,
      returned: page.count,
      limit: limit,
      offset: 0,
      nextOffset: nil,
      truncated: truncated)
  }

  static func habitStatsValue(from stats: HabitStats) -> Value {
    .object([
      "habit_id": .string(stats.habitID),
      "name": .string(stats.name),
      "current_streak": .int(stats.currentStreak),
      "best_streak": .int(stats.bestStreak),
      "total_completions": .int(stats.totalCompletions),
      "completions_today": .int(stats.completionsToday),
      "completion_rate_30d": .double(stats.completionRate30d),
      "progress_kind": .string(stats.progressKind),
      "milestone_target": stats.milestoneTarget.map(Value.int) ?? .null,
      // Milestone standing, mirroring the fields `get_habits` carries:
      // `milestone_metric` names the reading, `milestone_value` is the current
      // reading (streak length for streak cadences, cumulative count otherwise).
      "milestone_metric": .string(stats.metric),
      "milestone_value": .int(stats.metric == "count" ? stats.totalCompletions : stats.currentStreak),
      "next_milestone": .int(stats.nextMilestone),
      "progress_to_next": .double(stats.progressToNext),
    ])
  }
}
