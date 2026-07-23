import Foundation
import LorvexDomain

/// Bridges the pure `LorvexDomain` milestone logic into the `LorvexCore`
/// `HabitMilestoneInfo` model. Both storage backends (on-disk and in-memory)
/// funnel milestone standings through here so the metric/ladder mapping lives in
/// one place.
enum HabitMilestoneProjection {
  /// The milestone metric for a habit cadence, as the model's wire string
  /// (`"streak"` for daily/weekly, `"count"` for monthly/times_per_week).
  static func metricString(for metric: HabitMilestoneMetric) -> String {
    switch metric {
    case .streak: return "streak"
    case .count: return "count"
    }
  }

  /// Project a milestone standing for a `metric` reading (`value`) against an
  /// optional positive `target`. `justReached`, when non-nil, is the milestone
  /// the producing completion op just crossed (nil for pure reads).
  static func info(
    metric: HabitMilestoneMetric, value: Int, target: Int?, justReached: Int? = nil
  ) -> HabitMilestoneInfo {
    let standing = habitMilestoneStanding(value: value, target: target, metric: metric)
    return HabitMilestoneInfo(
      metric: metricString(for: metric),
      value: value,
      currentMilestone: standing.currentMilestone,
      nextMilestone: standing.nextMilestone,
      progressToNext: standing.progressToNext,
      justReached: justReached)
  }
}
