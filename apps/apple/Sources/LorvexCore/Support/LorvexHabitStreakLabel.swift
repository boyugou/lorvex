import Foundation

/// A streak length spelled out in the habit's own cadence unit ("12 days",
/// "3 weeks", "2 months"; "12 天" in Chinese): days for daily, weeks for weekly
/// and custom (specific-day or N-times-a-week) habits, months for monthly.
/// The core already counts the streak per cadence, so a weekly habit's "2"
/// means two weeks and reads that way here. The words come from LorvexCore's
/// catalog so every surface writes the number and its unit the same way.
public func lorvexHabitStreakLabel(_ count: Int, frequencyType: String) -> String {
  switch frequencyType {
  case "monthly":
    String(localized: "habit.streak.months", defaultValue: "\(count) months", table: "Localizable", bundle: CoreL10n.bundle)
  case "weekly", "times_per_week", "custom":
    String(localized: "habit.streak.weeks", defaultValue: "\(count) weeks", table: "Localizable", bundle: CoreL10n.bundle)
  default:
    String(localized: "habit.streak.days", defaultValue: "\(count) days", table: "Localizable", bundle: CoreL10n.bundle)
  }
}
