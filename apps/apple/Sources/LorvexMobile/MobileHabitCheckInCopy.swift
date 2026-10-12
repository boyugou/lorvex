import Foundation
import LorvexCore

/// What a habit's check-in controls say on the Habits screens, which judge a
/// habit by its period (``LorvexHabitCheckIn/Basis/period``): the period's
/// standing once its plan is met, the count behind a ring, and what a tap on the
/// ring does, for VoiceOver.
enum MobileHabitCheckInCopy {
  /// A period whose plan is met: "Done today", "Done this week", or "Done this
  /// month".
  static func periodDone(_ period: HabitRhythmStrip.Granularity) -> String {
    switch period {
    case .day:
      String(
        localized: "habits.period.done.day", defaultValue: "Done today", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .week:
      String(
        localized: "habits.period.done.week", defaultValue: "Done this week", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .month:
      String(
        localized: "habits.period.done.month", defaultValue: "Done this month",
        table: "Localizable", bundle: MobileL10n.bundle)
    }
  }

  /// The ring's VoiceOver label: the command a tap runs ("Complete Walk",
  /// "Reset Walk"), or the habit's name when a tap does nothing.
  static func ringLabel(for habit: LorvexHabit, action: LorvexHabitCheckIn) -> String {
    switch action {
    case .complete, .addOne:
      String(
        format: String(
          localized: "habits.complete.a11y", defaultValue: "Complete %@", table: "Localizable",
          bundle: MobileL10n.bundle), habit.name)
    case .uncomplete:
      String(
        format: String(
          localized: "habits.reset.a11y", defaultValue: "Reset %@", table: "Localizable",
          bundle: MobileL10n.bundle), habit.name)
    case .none:
      habit.name
    }
  }

  /// The ring's VoiceOver value: that the day is set aside; on the period
  /// basis, the period's standing once its plan is met or its count so far
  /// ("1 of 3 this week"); otherwise today's count ("2/3 today").
  static func ringValue(for habit: LorvexHabit, basis: LorvexHabitCheckIn.Basis) -> String {
    if habit.isSkipped { return MobileHabitSkipCopy.skippedToday }
    guard basis == .period else { return habit.todayProgressText }
    let period = HabitPeriodProgress.period(for: habit)
    let progress = habit.periodProgress
    if progress.isComplete { return periodDone(period) }
    switch period {
    case .day:
      return habit.todayProgressText
    case .week:
      return String(
        localized: "habits.period.count.week",
        defaultValue: "\(progress.completed) of \(progress.required) this week",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .month:
      return String(
        localized: "habits.period.count.month",
        defaultValue: "\(progress.completed) of \(progress.required) this month",
        table: "Localizable", bundle: MobileL10n.bundle)
    }
  }
}
