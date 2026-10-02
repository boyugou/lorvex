import Foundation
import LorvexCore

enum HabitDisplayText {
  /// How a habit repeats, as the habit inspector's Repeat row reads it:
  /// "Daily", "6 times a day", "Mon, Wed, Fri", "Mon, Wed, Fri · 2 times a
  /// day", "3 times a week", or "Monthly on day 15". A weekly habit on all
  /// seven days, or on none, reads as daily. Weekdays are stored Monday-first
  /// (0 = Mon … 6 = Sun) and listed from the first day of the user's week.
  static func repeatSummary(_ habit: LorvexHabit) -> String {
    let count = max(habit.targetCount, 1)
    switch habit.frequencyType {
    case "times_per_week":
      return String(
        localized: "habit_detail.repeat.times_per_week",
        defaultValue: "\(habit.perPeriodTarget ?? count) times a week",
        table: "Localizable", bundle: LorvexL10n.bundle)
    case "monthly":
      return String(
        localized: "habit_detail.repeat.monthly",
        defaultValue: "Monthly on day \(habit.dayOfMonth ?? 1)",
        table: "Localizable", bundle: LorvexL10n.bundle)
    case "weekly":
      if let days = weekdaySummary(habit.weekdays) {
        guard count > 1 else { return days }
        return String(
          localized: "habit_detail.repeat.days_count",
          defaultValue: "\(days) · \(count) times a day",
          table: "Localizable", bundle: LorvexL10n.bundle)
      }
      return dailySummary(count: count)
    default:
      return dailySummary(count: count)
    }
  }

  // MARK: - Period progress

  /// A habit's current period once its plan is met: "Done today", "Done this
  /// week", or "Done this month".
  static func periodDoneLabel(_ period: HabitRhythmStrip.Granularity) -> String {
    switch period {
    case .day:
      String(localized: "habits.meter.done.day", defaultValue: "Done today", table: "Localizable", bundle: LorvexL10n.bundle)
    case .week:
      String(localized: "habits.meter.done.week", defaultValue: "Done this week", table: "Localizable", bundle: LorvexL10n.bundle)
    case .month:
      String(localized: "habits.meter.done.month", defaultValue: "Done this month", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  /// A habit's current period before its plan is met, for a plan of one
  /// check-in: "Not done yet today", "Not done yet this week", or "Not done
  /// yet this month".
  static func periodNotYetLabel(_ period: HabitRhythmStrip.Granularity) -> String {
    switch period {
    case .day:
      String(localized: "habit_detail.status.not_yet.day", defaultValue: "Not done yet today", table: "Localizable", bundle: LorvexL10n.bundle)
    case .week:
      String(localized: "habit_detail.status.not_yet.week", defaultValue: "Not done yet this week", table: "Localizable", bundle: LorvexL10n.bundle)
    case .month:
      String(localized: "habit_detail.status.not_yet.month", defaultValue: "Not done yet this month", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  /// A habit's progress through its current period's plan: "3 of 8 today",
  /// "1 of 3 this week", or "2 of 4 this month".
  static func periodCountLabel(completed: Int, required: Int, period: HabitRhythmStrip.Granularity)
    -> String
  {
    switch period {
    case .day:
      String(
        localized: "habit_detail.status.count.day",
        defaultValue: "\(completed) of \(required) today",
        table: "Localizable", bundle: LorvexL10n.bundle)
    case .week:
      String(
        localized: "habit_detail.status.count.week",
        defaultValue: "\(completed) of \(required) this week",
        table: "Localizable", bundle: LorvexL10n.bundle)
    case .month:
      String(
        localized: "habit_detail.status.count.month",
        defaultValue: "\(completed) of \(required) this month",
        table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  // MARK: - Milestones

  /// The next milestone as a short phrase in the reading's own unit, for a
  /// habit row that shows the reading beside it: "Next at 14 days", "Next at 4
  /// weeks", "Next at 3 months", "Next at 50 completions". The unit keeps the
  /// number from reading as a bare count. `next` is
  /// `HabitMilestoneInfo.nextMilestone`; `metric` and `frequencyType` select
  /// the unit as in ``milestoneValueLabel(metric:value:frequencyType:)``.
  static func milestoneNextLabel(metric: String, next: Int, frequencyType: String) -> String {
    guard metric == "streak" else {
      return String(
        localized: "habits.milestone.next.count", defaultValue: "Next at \(next) completions",
        table: "Localizable", bundle: LorvexL10n.bundle)
    }
    switch frequencyType {
    case "monthly":
      return String(
        localized: "habits.milestone.next.months", defaultValue: "Next at \(next) months",
        table: "Localizable", bundle: LorvexL10n.bundle)
    case "weekly", "times_per_week", "custom":
      return String(
        localized: "habits.milestone.next.weeks", defaultValue: "Next at \(next) weeks",
        table: "Localizable", bundle: LorvexL10n.bundle)
    default:
      return String(
        localized: "habits.milestone.next.days", defaultValue: "Next at \(next) days",
        table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  /// A milestone-metric value as a labeled phrase, per metric and cadence:
  /// "12-day streak" / "3-week streak" / "6-month streak" for the streak
  /// cadences, "18 completions" for the cumulative cadences. A zero reading,
  /// which a habit with a milestone goal shows before its first streak or
  /// completion, reads "No streak yet" / "No completions yet". The same phrase
  /// names a rung ("Next milestone: 14-day streak"), and a rung is never zero.
  /// `metric` is the `HabitMilestoneInfo.metric` wire string (`"streak"` /
  /// `"count"`); `frequencyType` selects the streak unit.
  static func milestoneValueLabel(metric: String, value: Int, frequencyType: String)
    -> String
  {
    guard metric == "streak" else {
      if value == 0 {
        return String(
          localized: "habits.milestone.value.count_none",
          defaultValue: "No completions yet",
          table: "Localizable",
          bundle: LorvexL10n.bundle)
      }
      return String(
        localized: "habits.milestone.value.count",
        defaultValue: "\(value) completions",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
    }
    if value == 0 {
      return String(
        localized: "habits.milestone.value.streak_none",
        defaultValue: "No streak yet",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
    }
    switch frequencyType {
    case "monthly":
      return String(
        localized: "habits.milestone.value.streak_months", defaultValue: "\(value)-month streak",
        table: "Localizable", bundle: LorvexL10n.bundle)
    case "weekly", "times_per_week", "custom":
      return String(
        localized: "habits.milestone.value.streak_weeks", defaultValue: "\(value)-week streak",
        table: "Localizable", bundle: LorvexL10n.bundle)
    default:
      return String(
        localized: "habits.milestone.value.streak_days", defaultValue: "\(value)-day streak",
        table: "Localizable", bundle: LorvexL10n.bundle)
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

  // MARK: - Repeat summary helpers

  private static func dailySummary(count: Int) -> String {
    guard count > 1 else {
      return String(localized: "habits.frequency.daily", defaultValue: "Daily", table: "Localizable", bundle: LorvexL10n.bundle)
    }
    return String(
      localized: "habit_detail.repeat.daily_count", defaultValue: "\(count) times a day",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }

  /// A weekday set (Monday-first 0=Mon … 6=Sun) named as a task's repeat
  /// names its weekdays ("Mon, Wed, Fri", from the first day of the user's
  /// week); `nil` when the set is empty, absent, or all seven days.
  private static func weekdaySummary(_ weekdays: [Int]?) -> String? {
    guard let indices = weekdays.map({ Set($0.filter { (0...6).contains($0) }) }), !indices.isEmpty,
      indices.count < 7
    else {
      return nil
    }
    return LorvexRecurrenceWeekdays.summary(mondayFirst: Array(indices))
  }
}
