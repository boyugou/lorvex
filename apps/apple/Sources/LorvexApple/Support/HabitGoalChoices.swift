import LorvexCore

/// The choices a habit's goal editor offers, in the unit the goal counts.
///
/// A habit's goal (its `milestoneTarget`) is a streak length for the streak
/// cadences and a completion count for the cumulative ones, matching the
/// metric its milestones track: days for a daily habit, weeks for a habit on
/// chosen weekdays, completions for a habit done some times a week or on a
/// day each month.
enum HabitGoalChoices {
  enum Unit: Equatable {
    case days, weeks, completions
  }

  /// The unit `habit`'s goal counts in. The milestone metric the core
  /// projects decides streak against count; a habit read without one falls
  /// back to its cadence.
  static func unit(for habit: LorvexHabit) -> Unit {
    let metric =
      habit.milestone?.metric
      ?? (["monthly", "times_per_week"].contains(habit.frequencyType) ? "count" : "streak")
    guard metric == "streak" else { return .completions }
    return habit.frequencyType == "daily" ? .days : .weeks
  }

  /// One-click goals: the streak rungs people aim for (a week, two weeks, a
  /// month, the 66 days a habit takes to settle, a hundred, a year), their
  /// counterparts in weeks, and round completion counts.
  static func presets(for unit: Unit) -> [Int] {
    switch unit {
    case .days: [7, 14, 30, 66, 100, 365]
    case .weeks: [4, 8, 12, 26, 52]
    case .completions: [10, 25, 50, 100, 250, 500]
    }
  }

  /// The goal the + button sets on a habit without one: the smallest preset.
  static func firstGoal(for unit: Unit) -> Int {
    presets(for: unit)[0]
  }

  /// The goal one + click above `value`, on a step that grows with the
  /// number: 1 below 10, 5 below 50, 10 below 200, and 50 from there. The
  /// result lands on a multiple of its step (12 goes to 15, 66 to 70).
  static func increment(_ value: Int) -> Int {
    let step = step(around: value)
    return min((value / step + 1) * step, maximum)
  }

  /// The goal one − click below `value`, on the step of the range it moves
  /// into, landing on a multiple of that step (15 goes to 10, 10 to 9, 66 to
  /// 60). Never below 1.
  static func decrement(_ value: Int) -> Int {
    guard value > 1 else { return 1 }
    let step = step(around: value - 1)
    return max(((value - 1) / step) * step, 1)
  }

  /// The largest goal the editor sets.
  static let maximum = 9_999

  private static func step(around value: Int) -> Int {
    switch value {
    case ..<10: 1
    case ..<50: 5
    case ..<200: 10
    default: 50
    }
  }
}
