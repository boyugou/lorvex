import Foundation

public struct HabitCatalogSnapshot: Equatable, Sendable {
  public var habits: [LorvexHabit]

  public init(habits: [LorvexHabit]) {
    self.habits = habits
  }
}

/// Cadence detail for a habit, decoupled from `targetCount` (the per-day
/// accumulative goal). Mirrors the `habits` typed columns + `habit_weekdays`
/// child so the UI and MCP surfaces carry cadence as fields rather than a JSON
/// blob. `LorvexCore`-local (no `LorvexDomain` dependency); the storage service
/// bridges it to the domain `HabitCadence`.
///
/// Field meaning by `frequencyType`:
/// - `"daily"` — every day; other fields ignored.
/// - `"weekly"` — pinned to `weekdays` (Monday-first 0=Mon … 6=Sun); an empty
///   or nil set means "every day".
/// - `"monthly"` — once per month; `dayOfMonth` (1–31) is the reminder day.
/// - `"times_per_week"` — `perPeriodTarget` completions per week, no weekday
///   pinning.
public struct HabitCadenceInput: Equatable, Sendable {
  public var frequencyType: String
  public var weekdays: [Int]?
  public var perPeriodTarget: Int?
  public var dayOfMonth: Int?

  public init(
    frequencyType: String,
    weekdays: [Int]? = nil,
    perPeriodTarget: Int? = nil,
    dayOfMonth: Int? = nil
  ) {
    self.frequencyType = frequencyType
    self.weekdays = weekdays
    self.perPeriodTarget = perPeriodTarget
    self.dayOfMonth = dayOfMonth
  }

  /// A plain daily cadence — the default when a caller sets no rhythm.
  public static let daily = HabitCadenceInput(frequencyType: "daily")
}

/// A habit's milestone standing, computed by the storage layer from the habit's
/// cadence-selected metric against the milestone ladder and the optional user
/// target. Carried on `LorvexHabit` so reads (get_habits, the UI card) surface
/// milestone progress without a second query.
///
/// `metric` is `"streak"` for the streak cadences (`daily`, `weekly`) and
/// `"count"` for the cumulative cadences (`monthly`, `times_per_week`); `value`
/// is the current metric reading (streak length, or total completions). The
/// standing fields mirror `LorvexDomain.HabitMilestoneStanding`.
///
/// `justReached` is set ONLY on the habit returned by a completion op
/// (`completeHabit` / `batchCompleteHabits`) — the milestone that completion
/// just crossed, or nil when it crossed none. It is always nil for pure reads.
public struct HabitMilestoneInfo: Equatable, Sendable {
  public var metric: String
  public var value: Int
  public var currentMilestone: Int?
  public var nextMilestone: Int
  public var progressToNext: Double
  public var justReached: Int?

  public init(
    metric: String,
    value: Int,
    currentMilestone: Int?,
    nextMilestone: Int,
    progressToNext: Double,
    justReached: Int? = nil
  ) {
    self.metric = metric
    self.value = value
    self.currentMilestone = currentMilestone
    self.nextMilestone = nextMilestone
    self.progressToNext = progressToNext
    self.justReached = justReached
  }
}

public struct LorvexHabit: Identifiable, Equatable, Sendable {
  public var id: String
  public var name: String
  public var icon: String?
  public var color: String?
  public var cue: String?
  public var frequencyType: String
  /// Weekday set (Monday-first 0=Mon … 6=Sun) for a `weekly` cadence; nil for
  /// every other cadence and for weekly-every-day. Lets the edit sheet pre-fill.
  public var weekdays: [Int]?
  /// Completions-per-week goal for a `times_per_week` cadence; nil otherwise.
  public var perPeriodTarget: Int?
  /// Reminder day-of-month (1–31) for a `monthly` cadence; nil otherwise.
  public var dayOfMonth: Int?
  public var targetCount: Int
  public var completionsToday: Int
  public var totalCompletions: Int
  public var completionRate30d: Double
  public var archived: Bool
  public var position: Int64
  /// Optional user-set milestone goal (a positive count in the cadence's metric);
  /// nil when unset.
  public var milestoneTarget: Int?
  /// Computed milestone standing (metric value, next milestone, progress).
  /// Populated by the storage layer on reads and mutation returns; nil on
  /// value-only constructions (seed data, export fixtures) that don't project it.
  public var milestone: HabitMilestoneInfo?

  public init(
    id: String,
    name: String,
    icon: String?,
    color: String?,
    cue: String?,
    frequencyType: String,
    targetCount: Int,
    completionsToday: Int,
    totalCompletions: Int,
    completionRate30d: Double,
    archived: Bool,
    position: Int64 = 0,
    weekdays: [Int]? = nil,
    perPeriodTarget: Int? = nil,
    dayOfMonth: Int? = nil,
    milestoneTarget: Int? = nil,
    milestone: HabitMilestoneInfo? = nil
  ) {
    self.id = id
    self.name = name
    self.icon = icon
    self.color = color
    self.cue = cue
    self.frequencyType = frequencyType
    self.weekdays = weekdays
    self.perPeriodTarget = perPeriodTarget
    self.dayOfMonth = dayOfMonth
    self.targetCount = targetCount
    self.completionsToday = completionsToday
    self.totalCompletions = totalCompletions
    self.completionRate30d = completionRate30d
    self.archived = archived
    self.position = position
    self.milestoneTarget = milestoneTarget
    self.milestone = milestone
  }

  /// The cadence detail as a reusable input value (e.g. to pre-fill an editor).
  public var cadence: HabitCadenceInput {
    HabitCadenceInput(
      frequencyType: frequencyType, weekdays: weekdays, perPeriodTarget: perPeriodTarget,
      dayOfMonth: dayOfMonth)
  }
}

public struct HabitCompletionEntry: Equatable, Sendable {
  public var habitID: String
  public var completedDate: String
  public var value: Int
  public var note: String?
  public var createdAt: String
  public var updatedAt: String

  public init(
    habitID: String,
    completedDate: String,
    value: Int,
    note: String?,
    createdAt: String,
    updatedAt: String
  ) {
    self.habitID = habitID
    self.completedDate = completedDate
    self.value = value
    self.note = note
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

public struct HabitCompletionsSnapshot: Equatable, Sendable {
  public var habitID: String
  public var days: Int
  public var completions: [HabitCompletionEntry]

  public init(habitID: String, days: Int, completions: [HabitCompletionEntry]) {
    self.habitID = habitID
    self.days = days
    self.completions = completions
  }
}

public struct HabitStats: Equatable, Sendable {
  public var habitID: String
  /// The habit's display name, carried so `get_habit_stats` need not be paired
  /// with `get_habits` to label the habit (parity with the catalog read).
  public var name: String
  public var currentStreak: Int
  public var bestStreak: Int
  public var totalCompletions: Int
  public var completionsToday: Int
  public var completionRate30d: Double
  public var progressKind: String
  /// Completed-day strings (YYYY-MM-DD) within the trailing window, ascending.
  /// Lets a habit card render a real recent-activity strip without a second read.
  public var recentCompletions: [String]
  /// Optional user-set milestone goal; nil when unset.
  public var milestoneTarget: Int?
  /// Which reading the milestone tracks — `"streak"` (streak length, for daily /
  /// weekly cadences) or `"count"` (cumulative completions, for monthly /
  /// times_per_week). Matches the `milestone_metric` `get_habits` carries.
  public var metric: String
  /// Next milestone to aim for in the cadence's metric (streak length or total
  /// completions), and fractional progress `0...1` toward it. Computed against
  /// the milestone ladder + `milestoneTarget`.
  public var nextMilestone: Int
  public var progressToNext: Double

  public init(
    habitID: String,
    name: String = "",
    currentStreak: Int,
    bestStreak: Int,
    totalCompletions: Int,
    completionsToday: Int,
    completionRate30d: Double,
    progressKind: String,
    recentCompletions: [String] = [],
    milestoneTarget: Int? = nil,
    metric: String = "streak",
    nextMilestone: Int = 0,
    progressToNext: Double = 0
  ) {
    self.habitID = habitID
    self.name = name
    self.currentStreak = currentStreak
    self.bestStreak = bestStreak
    self.totalCompletions = totalCompletions
    self.completionsToday = completionsToday
    self.completionRate30d = completionRate30d
    self.progressKind = progressKind
    self.recentCompletions = recentCompletions
    self.milestoneTarget = milestoneTarget
    self.metric = metric
    self.nextMilestone = nextMilestone
    self.progressToNext = progressToNext
  }
}

/// A single concrete habit-reminder firing: one enabled policy paired with the
/// exact instant it should nudge the user.
///
/// Produced by `getDueHabitReminderOccurrences(now:horizonDays:)`, which expands
/// each policy across a rolling horizon and keeps only the days the habit is
/// actually scheduled, whose period is still below its target, and whose fire
/// time is in the future. The local-notification scheduler consumes these as
/// per-occurrence one-shot triggers — the same shape `ScheduledTaskReminder`
/// gives task reminders — so a completed/met period simply produces no
/// occurrence on the next re-plan.
public struct DueHabitReminderOccurrence: Equatable, Sendable {
  public var policy: HabitReminderPolicy
  public var fireDate: Date

  public init(policy: HabitReminderPolicy, fireDate: Date) {
    self.policy = policy
    self.fireDate = fireDate
  }
}

public struct HabitReminderPolicy: Identifiable, Equatable, Sendable {
  public var id: String
  public var habitID: String
  public var habitName: String
  public var reminderTime: String
  public var enabled: Bool
  public var createdAt: String
  public var updatedAt: String

  public init(
    id: String,
    habitID: String,
    habitName: String,
    reminderTime: String,
    enabled: Bool,
    createdAt: String,
    updatedAt: String
  ) {
    self.id = id
    self.habitID = habitID
    self.habitName = habitName
    self.reminderTime = reminderTime
    self.enabled = enabled
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}
