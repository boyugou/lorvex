import Foundation
import LorvexCore

/// Milestone display strings for the mobile habit surfaces, routed through
/// `MobileL10n` so lookups reach the LorvexMobile catalog. Mirrors the macOS
/// `HabitDisplayText` milestone vocabulary so both platforms label the same
/// standing identically.
enum MobileHabitDisplayText {
  /// A localized display name for a habit's `frequencyType` wire value
  /// ("daily" / "weekly" / "times_per_week" / "monthly" / "custom"), for the
  /// habit-detail "Frequency" metric. Replaces a bare `.capitalized` of the raw
  /// value, which surfaced untranslated, underscore-laden strings like
  /// "Times_Per_Week".
  static func frequencyName(_ frequencyType: String) -> String {
    switch frequencyType {
    case "weekly":
      return String(localized: "habits.frequency.weekly", defaultValue: "Weekly", table: "Localizable", bundle: MobileL10n.bundle)
    case "times_per_week":
      return String(localized: "habits.frequency.times_per_week", defaultValue: "Times per week", table: "Localizable", bundle: MobileL10n.bundle)
    case "monthly":
      return String(localized: "habits.frequency.monthly", defaultValue: "Monthly", table: "Localizable", bundle: MobileL10n.bundle)
    case "custom":
      return String(localized: "habits.frequency.custom", defaultValue: "Custom", table: "Localizable", bundle: MobileL10n.bundle)
    default:
      return String(localized: "habits.frequency.daily", defaultValue: "Daily", table: "Localizable", bundle: MobileL10n.bundle)
    }
  }

  /// The current milestone-metric reading as a labeled phrase, per metric and
  /// cadence: "12-day streak" / "3-week streak" / "6-month streak" for the
  /// streak cadences, "18 completions" for the cumulative cadences. `metric` is
  /// the `HabitMilestoneInfo.metric` wire string (`"streak"` / `"count"`);
  /// `frequencyType` selects the streak unit.
  static func milestoneValueLabel(metric: String, value: Int, frequencyType: String) -> String {
    guard metric == "streak" else {
      return String(
        localized: "habits.milestone.value.count", defaultValue: "\(value) completions",
        table: "Localizable", bundle: MobileL10n.bundle)
    }
    switch frequencyType {
    case "monthly":
      return String(
        format: String(localized: "habits.milestone.value.streak_months", defaultValue: "%lld-month streak", table: "Localizable", bundle: MobileL10n.bundle),
        value)
    case "weekly", "times_per_week", "custom":
      return String(
        format: String(localized: "habits.milestone.value.streak_weeks", defaultValue: "%lld-week streak", table: "Localizable", bundle: MobileL10n.bundle), value)
    default:
      return String(
        format: String(localized: "habits.milestone.value.streak_days", defaultValue: "%lld-day streak", table: "Localizable", bundle: MobileL10n.bundle), value)
    }
  }

  /// The celebratory one-line subtitle for a reached milestone: the crossed
  /// value labeled per metric plus the habit name, e.g. "7-day streak · Morning
  /// meditation". `milestone` is the crossed value.
  static func milestoneReachedSubtitle(
    milestone: Int, metric: String, frequencyType: String, habitName: String
  ) -> String {
    let phrase = milestoneValueLabel(metric: metric, value: milestone, frequencyType: frequencyType)
    return String(
      format: String(localized: "habits.milestone.reached_subtitle", defaultValue: "%1$@ · %2$@", table: "Localizable", bundle: MobileL10n.bundle),
      phrase, habitName)
  }

  /// Cadence-aware hint for the optional milestone-goal field: a streak length
  /// for the streak cadences (daily / weekly), a completion count for the
  /// cumulative cadences (times-a-week / monthly). Both note that the habit does
  /// not stop at the goal — a milestone is a celebration moment, not an end.
  static func milestoneGoalHint(frequencyType: String) -> String {
    switch frequencyType {
    case "times_per_week", "monthly":
      return String(localized: "habits.sheet.field.milestone_goal_hint_count", defaultValue: "Celebrate at this many completions. The habit keeps going after.", table: "Localizable", bundle: MobileL10n.bundle)
    default:
      return String(localized: "habits.sheet.field.milestone_goal_hint_streak", defaultValue: "Celebrate at this streak length. The habit keeps going after.", table: "Localizable", bundle: MobileL10n.bundle)
    }
  }
}
