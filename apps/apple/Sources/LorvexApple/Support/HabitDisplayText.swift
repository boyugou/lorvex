import Foundation
import LorvexCore

enum HabitDisplayText {
  /// One-line cadence + requirement summary for the inspector's lead chip, e.g.
  /// "Daily · 6×/day", "Mon · Wed · Fri", "3×/week", or "Day 1". Unlike
  /// ``frequency(_:)`` (which names only the rhythm) this folds in the weekday
  /// set / per-week count / monthly day and the per-day `targetCount`, so the
  /// chip states exactly what completing the habit requires. Reads the typed
  /// cadence fields directly (weekdays Monday-first 0=Mon … 6=Sun).
  static func requirementSummary(_ habit: LorvexHabit) -> String {
    let count = max(habit.targetCount, 1)
    switch habit.frequencyType {
    case "weekly":
      if let days = weekdaySummary(habit.weekdays) {
        return count > 1 ? "\(days) · \(perDay(count))" : days
      }
      return count > 1 ? "\(everyDay()) · \(perDay(count))" : everyDay()
    case "times_per_week":
      return perWeek(habit.perPeriodTarget ?? count)
    case "monthly":
      let base = habit.dayOfMonth.map(monthDay) ?? monthlyLabel()
      return count > 1 ? "\(base) · \(perMonth(count))" : base
    default:
      return count > 1 ? "\(everyDay()) · \(perDay(count))" : everyDay()
    }
  }

  // MARK: - Milestones

  /// The current milestone-metric reading as a labeled phrase, per metric and
  /// cadence: "12-day streak" / "3-week streak" / "6-month streak" for the
  /// streak cadences, "18 completions" for the cumulative cadences. `metric` is
  /// the `HabitMilestoneInfo.metric` wire string (`"streak"` / `"count"`);
  /// `frequencyType` selects the streak unit.
  static func milestoneValueLabel(metric: String, value: Int, frequencyType: String)
    -> String
  {
    guard metric == "streak" else {
      return String(
        localized: "habits.milestone.value.count",
        defaultValue: "\(value) completions",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
    }
    switch frequencyType {
    case "monthly":
      return String(
        format: String(
          localized: "habits.milestone.value.streak_months", defaultValue: "%lld-month streak",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        value)
    case "weekly", "times_per_week", "custom":
      return String(
        format: String(
          localized: "habits.milestone.value.streak_weeks", defaultValue: "%lld-week streak",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        value)
    default:
      return String(
        format: String(
          localized: "habits.milestone.value.streak_days", defaultValue: "%lld-day streak",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        value)
    }
  }

  /// The celebratory one-line subtitle for a reached milestone: the crossed
  /// value labeled per metric plus the habit name, e.g. "7-day streak · Morning
  /// meditation". `milestone` is the crossed value; the label reuses
  /// ``milestoneValueLabel(metric:value:frequencyType:)`` for the metric phrasing.
  static func milestoneReachedSubtitle(
    milestone: Int, metric: String, frequencyType: String, habitName: String
  ) -> String {
    let phrase = milestoneValueLabel(metric: metric, value: milestone, frequencyType: frequencyType)
    return String(
      format: String(
        localized: "habits.milestone.reached_subtitle", defaultValue: "%1$@ · %2$@",
        table: "Localizable",
        bundle: LorvexL10n.bundle),
      phrase, habitName)
  }

  // MARK: - Requirement summary helpers

  private static func everyDay() -> String {
    String(localized: "habits.frequency.daily", defaultValue: "Daily", table: "Localizable", bundle: LorvexL10n.bundle)
  }

  private static func monthlyLabel() -> String {
    String(localized: "habits.frequency.monthly", defaultValue: "Monthly", table: "Localizable", bundle: LorvexL10n.bundle)
  }

  private static func perDay(_ n: Int) -> String {
    String(format: String(
      localized: "habits.requirement.per_day", defaultValue: "%lld×/day",
      table: "Localizable",
      bundle: LorvexL10n.bundle), n)
  }

  private static func perWeek(_ n: Int) -> String {
    String(format: String(
      localized: "habits.requirement.per_week", defaultValue: "%lld×/week",
      table: "Localizable",
      bundle: LorvexL10n.bundle), n)
  }

  private static func perMonth(_ n: Int) -> String {
    String(format: String(
      localized: "habits.requirement.per_month", defaultValue: "%lld×/month",
      table: "Localizable",
      bundle: LorvexL10n.bundle), n)
  }

  private static func monthDay(_ day: Int) -> String {
    String(format: String(
      localized: "habits.requirement.month_day", defaultValue: "Day %lld",
      table: "Localizable",
      bundle: LorvexL10n.bundle), day)
  }

  /// Localized "Mon · Wed · Fri" for a weekday set (Monday-first 0=Mon … 6=Sun);
  /// "Daily" when all seven are present; `nil` when the set is empty/absent.
  private static func weekdaySummary(_ weekdays: [Int]?) -> String? {
    guard let indices = weekdays?.filter({ (0...6).contains($0) }).sorted(), !indices.isEmpty else {
      return nil
    }
    if indices.count == 7 { return everyDay() }
    let symbols = Calendar.current.shortWeekdaySymbols
    let names = indices.compactMap { idx -> String? in
      let i = (idx + 1) % 7
      return symbols.indices.contains(i) ? symbols[i] : nil
    }
    return names.joined(separator: " · ")
  }
}
