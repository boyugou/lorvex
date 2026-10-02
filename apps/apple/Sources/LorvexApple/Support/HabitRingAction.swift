import LorvexCore

/// What clicking a habit's check-in ring does — the ring on its card and the
/// one in its inspector's header — read against the period progress the ring
/// draws (``HabitPeriodProgress``), so the click always agrees with what the
/// ring shows.
///
/// A habit counted several times a day adds one check-in per click until the
/// day's count is met. A habit checked in once a day checks in, or clears
/// today's check-in once the period is met; when earlier days met the period
/// (a weekly or monthly habit) and today holds no check-in, the click does
/// nothing, since a check-in today would only over-log the period and there is
/// no check-in to clear. Clearing an accumulated count is the explicit Reset
/// Today command, never a ring click.
enum HabitRingAction: Equatable {
  case addOne
  case checkIn
  case undoToday
  case none

  static func action(habit: LorvexHabit, progress: HabitPeriodProgress.Value) -> HabitRingAction {
    if habit.targetCount > 1 { return progress.isComplete ? .none : .addOne }
    guard progress.isComplete else { return .checkIn }
    return habit.completionsToday > 0 ? .undoToday : .none
  }

  /// The ring's help tag and VoiceOver label: the action it takes, or the
  /// period's state when it takes none ("Done today", "Done this week").
  func label(for habit: LorvexHabit) -> String {
    switch self {
    case .addOne:
      String(localized: "habits.row.add_one", defaultValue: "Add one", table: "Localizable", bundle: LorvexL10n.bundle)
    case .checkIn:
      String(localized: "habits.row.complete_today", defaultValue: "Complete today", table: "Localizable", bundle: LorvexL10n.bundle)
    case .undoToday:
      String(localized: "habits.row.reset_today", defaultValue: "Reset today", table: "Localizable", bundle: LorvexL10n.bundle)
    case .none:
      HabitDisplayText.periodDoneLabel(HabitPeriodProgress.period(for: habit))
    }
  }

  /// The card ring's accessibility identifier, one per action.
  var cardIdentifier: String {
    switch self {
    case .addOne: "habit.action.increment"
    case .checkIn: "habit.action.complete"
    case .undoToday: "habit.action.reset"
    case .none: "habit.action.done"
    }
  }
}
