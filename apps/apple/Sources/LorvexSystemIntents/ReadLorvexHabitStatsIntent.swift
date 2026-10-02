import AppIntents
import LorvexCore

struct ReadLorvexHabitStatsIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.habit.stats.read.title", defaultValue: "Read Lorvex Habit Stats", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.habit.stats.read.description", defaultValue: "Read Lorvex habit streaks and completion stats.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.habit.parameter.habit", defaultValue: "Habit", table: "Localizable", bundle: SystemL10n.bundle))
  var habit: LorvexHabitEntity

  init() {
    habit = LorvexHabitEntity(id: "", name: "", completionsToday: 0, targetCount: 0)
  }

  init(habit: LorvexHabitEntity) {
    self.habit = habit
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let stats = try await LorvexTaskIntentRunner.readHabitStats(id: habit.id)
    return .result(
      dialog: IntentDialog(
        Self.dialog(name: habit.name, frequencyType: habit.frequencyType, stats: stats)))
  }

  /// What Siri says: "Meditate: 12-day streak, 40 completions in all." The
  /// streak counts in the habit's cadence, the way the app labels it: months
  /// for a monthly habit, weeks for a weekly, times-per-week, or custom one,
  /// days otherwise.
  static func dialog(name: String, frequencyType: String, stats: HabitStats) -> LocalizedStringResource {
    let streak = stats.currentStreak
    let total = stats.totalCompletions
    guard streak > 0 else {
      return LocalizedStringResource(
        "system.habit.stats.read.dialog.no_streak",
        defaultValue: "\(name): no current streak, \(total) completions in all.",
        table: "Localizable", bundle: SystemL10n.bundle)
    }
    switch frequencyType {
    case "monthly":
      return LocalizedStringResource(
        "system.habit.stats.read.dialog.months",
        defaultValue: "\(name): \(streak)-month streak, \(total) completions in all.",
        table: "Localizable", bundle: SystemL10n.bundle)
    case "weekly", "times_per_week", "custom":
      return LocalizedStringResource(
        "system.habit.stats.read.dialog.weeks",
        defaultValue: "\(name): \(streak)-week streak, \(total) completions in all.",
        table: "Localizable", bundle: SystemL10n.bundle)
    default:
      return LocalizedStringResource(
        "system.habit.stats.read.dialog.days",
        defaultValue: "\(name): \(streak)-day streak, \(total) completions in all.",
        table: "Localizable", bundle: SystemL10n.bundle)
    }
  }
}
