import Foundation

/// A compact, localized minutes label ("90m" / "90 Min." / "90分") for task
/// estimates and focus-schedule durations. The single localized minutes form
/// shared by task rows, the task table, and the focus schedule.
func lorvexMinutesLabel(_ minutes: Int) -> String {
  String(
    format: String(localized: "common.duration.minutes_short", defaultValue: "%lldm", table: "Localizable", bundle: LorvexL10n.bundle),
    minutes
  )
}

/// A compact, localized day-count label ("18d" / "18 T." / "18日") for habit
/// streaks. The single localized day-count form shared by the habit row and the
/// streak stat lines.
func lorvexDaysLabel(_ days: Int) -> String {
  String(
    format: String(localized: "common.duration.days_short", defaultValue: "%lldd", table: "Localizable", bundle: LorvexL10n.bundle),
    days
  )
}

/// A streak length labeled in the habit's own cadence unit: days for daily,
/// weeks for weekly / custom (specific-day or N-times-a-week) habits, months for
/// monthly. The streak *count* is already computed per cadence by the core, so a
/// weekly habit's "2" means two weeks — this picks the matching unit so the card
/// doesn't render it as "2d".
func lorvexHabitStreakLabel(_ count: Int, frequencyType: String) -> String {
  switch frequencyType {
  case "monthly":
    return String(
      format: String(localized: "common.duration.months_short", defaultValue: "%lldmo", table: "Localizable", bundle: LorvexL10n.bundle),
      count)
  case "weekly", "times_per_week", "custom":
    return String(
      format: String(localized: "common.duration.weeks_short", defaultValue: "%lldw", table: "Localizable", bundle: LorvexL10n.bundle),
      count)
  default:
    return lorvexDaysLabel(count)
  }
}
