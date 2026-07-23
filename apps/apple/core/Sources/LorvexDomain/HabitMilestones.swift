// MARK: - Habit milestones

/// Which progress metric a habit's milestones track, chosen by cadence.
public enum HabitMilestoneMetric: Sendable, Equatable, Hashable {
  /// Length of the current consecutive-period streak. Used by the streak
  /// cadences (`daily`, `weekly`), where the reward is an unbroken run.
  case streak
  /// Cumulative completion count. Used by the count cadences (`times_per_week`,
  /// `monthly`), where the reward is a running total rather than an unbroken
  /// chain.
  case count
}

/// The milestone metric for a cadence: `.streak` for `daily` and `weekly` (both
/// reward consecutive periods), `.count` for `timesPerWeek` and `monthly` (both
/// reward cumulative totals).
public func habitMilestoneMetric(for cadence: HabitCadence) -> HabitMilestoneMetric {
  switch cadence {
  case .daily, .weekly:
    return .streak
  case .monthly, .timesPerWeek:
    return .count
  }
}

/// Fixed low end of the streak ladder; beyond it every rung adds another 365.
private let streakMilestoneLadderPrefix = [7, 14, 30, 66, 100, 180, 365]
/// The 1 / 2.5 / 5 shape repeated up each power-of-ten decade for the count
/// ladder (10, 25, 50, then 100, 250, 500, then 1000, …).
private let countMilestoneDecadeSteps = [10, 25, 50]

/// The `index`-th milestone rung (0-based) on the unbounded ladder for `metric`.
///
/// - Streak: `7, 14, 30, 66, 100, 180, 365`, then `+365` per step (`730, 1095,
///   …`).
/// - Count: `10, 25, 50, 100, 250, 500, 1000, …` — `countMilestoneDecadeSteps`
///   scaled by successive powers of ten.
public func habitMilestoneRung(index: Int, for metric: HabitMilestoneMetric) -> Int {
  precondition(index >= 0, "milestone rung index must be non-negative")
  switch metric {
  case .streak:
    if index < streakMilestoneLadderPrefix.count {
      return streakMilestoneLadderPrefix[index]
    }
    // Prefix last (index 6) is 365; each further step adds a year, so index 7 →
    // 730, index 8 → 1095, …
    return 365 * (index - streakMilestoneLadderPrefix.count + 2)
  case .count:
    let decade = index / countMilestoneDecadeSteps.count
    let step = countMilestoneDecadeSteps[index % countMilestoneDecadeSteps.count]
    var scale = 1
    for _ in 0..<decade { scale *= 10 }
    return step * scale
  }
}

/// Largest ladder rung `<= value`, or `nil` when `value` is below the first rung.
private func milestoneRungAtOrBelow(_ value: Int, metric: HabitMilestoneMetric) -> Int? {
  guard value >= habitMilestoneRung(index: 0, for: metric) else { return nil }
  var index = 0
  while habitMilestoneRung(index: index + 1, for: metric) <= value {
    index += 1
  }
  return habitMilestoneRung(index: index, for: metric)
}

/// Smallest ladder rung strictly greater than `value`. Always exists (the ladder
/// is unbounded).
private func nextMilestoneRungAbove(_ value: Int, metric: HabitMilestoneMetric) -> Int {
  var index = 0
  while habitMilestoneRung(index: index, for: metric) <= value {
    index += 1
  }
  return habitMilestoneRung(index: index, for: metric)
}

/// A habit's milestone standing for a metric value against the ladder + an
/// optional user target.
public struct HabitMilestoneStanding: Sendable, Equatable, Hashable {
  /// Highest milestone already reached: the largest ladder rung `<= value`,
  /// raised to the user target once `value` meets it. `nil` when `value` is
  /// below the first ladder rung and no target has been reached.
  public var currentMilestone: Int?
  /// Next milestone to aim for: the user target when set and not yet reached,
  /// otherwise the next ladder rung strictly above `value`. Always present — the
  /// ladder is unbounded, so a further rung exists once any target is met.
  public var nextMilestone: Int
  /// Fractional progress in `0...1` from `currentMilestone` (or 0) toward
  /// `nextMilestone`.
  public var progressToNext: Double

  public init(currentMilestone: Int?, nextMilestone: Int, progressToNext: Double) {
    self.currentMilestone = currentMilestone
    self.nextMilestone = nextMilestone
    self.progressToNext = progressToNext
  }
}

/// Milestone standing for a metric `value` (negative values clamp to 0) against
/// an optional positive `target`.
///
/// - A set `target` above `value` becomes `nextMilestone`; ladder rungs already
///   passed still show as `currentMilestone`.
/// - Once `value` reaches a set `target`, the target counts as reached (folded
///   into `currentMilestone`) and `nextMilestone` keeps climbing the ladder
///   above `value`.
/// - With no target (or a non-positive one), the standing is read straight off
///   the ladder.
public func habitMilestoneStanding(
  value: Int, target: Int?, metric: HabitMilestoneMetric
) -> HabitMilestoneStanding {
  let value = max(value, 0)
  let ladderBelow = milestoneRungAtOrBelow(value, metric: metric)
  let ladderAbove = nextMilestoneRungAbove(value, metric: metric)

  let current: Int?
  let next: Int
  if let target, target > 0, value < target {
    current = ladderBelow
    next = target
  } else if let target, target > 0 {
    // target reached (value >= target): fold it into the reached milestone and
    // keep laddering above the current value.
    current = max(target, ladderBelow ?? target)
    next = ladderAbove
  } else {
    current = ladderBelow
    next = ladderAbove
  }

  let base = current ?? 0
  let span = next - base
  let progress = span <= 0 ? 1.0 : min(max(Double(value - base) / Double(span), 0.0), 1.0)
  return HabitMilestoneStanding(
    currentMilestone: current, nextMilestone: next, progressToNext: progress)
}

/// The milestone crossed when the metric moves `prev` → `new`: the largest
/// milestone strictly greater than `prev` and at most `new`, considering both
/// the ladder rungs and a set positive `target`. `nil` when the move crosses no
/// milestone — including any non-increasing move (`new <= prev`). When a single
/// jump clears several milestones, the highest one reached is returned.
public func justReachedHabitMilestone(
  prev: Int, new: Int, target: Int?, metric: HabitMilestoneMetric
) -> Int? {
  guard new > prev else { return nil }
  var crossed: Int? = nil
  if let rung = milestoneRungAtOrBelow(new, metric: metric), rung > prev {
    crossed = rung
  }
  if let target, target > 0, target > prev, target <= new {
    crossed = max(crossed ?? Int.min, target)
  }
  return crossed
}
