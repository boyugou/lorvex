import AppIntents
import LorvexCore

struct ResetLorvexHabitIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.habit.reset.title", defaultValue: "Reset Lorvex Habit", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.habit.reset.description", defaultValue: "Reset today's completion for a Lorvex habit.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.habit.parameter.habit", defaultValue: "Habit", table: "Localizable", bundle: SystemL10n.bundle))
  var habit: LorvexHabitEntity

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.date", defaultValue: "Date", table: "Localizable", bundle: SystemL10n.bundle),
    description: LocalizedStringResource("system.task.parameter.date.optional_today.description", defaultValue: "Optional date in YYYY-MM-DD format. Leave blank for today.", table: "Localizable", bundle: SystemL10n.bundle))
  var date: String?

  init() {
    habit = LorvexHabitEntity(id: "", name: "", completionsToday: 0, targetCount: 0)
    date = nil
  }

  init(habit: LorvexHabitEntity, date: String? = nil) {
    self.habit = habit
    self.date = date
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    try await requestLorvexDestructiveConfirmation(
      IntentDialog(
        LocalizedStringResource(
          "system.confirm.reset_habit",
          defaultValue: "Reset this habit? Logged completions will be cleared.",
          table: "Localizable", bundle: SystemL10n.bundle)))
    let reset = try await LorvexTaskIntentRunner.uncompleteHabit(id: habit.id, date: date)
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.habit.reset.dialog", defaultValue: "Reset \(reset.name) in Lorvex.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
