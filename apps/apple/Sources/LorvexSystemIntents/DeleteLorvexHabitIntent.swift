import AppIntents
import LorvexCore

struct DeleteLorvexHabitIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.habit.delete.title", defaultValue: "Delete Lorvex Habit", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.habit.delete.description", defaultValue: "Delete a Lorvex habit from Shortcuts or Siri.", table: "Localizable", bundle: SystemL10n.bundle))

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
    try await requestLorvexDestructiveConfirmation(
      IntentDialog(
        LocalizedStringResource(
          "system.confirm.delete", defaultValue: "Delete this item? This can't be undone.",
          table: "Localizable", bundle: SystemL10n.bundle)))
    _ = try await LorvexTaskIntentRunner.deleteHabit(id: habit.id)
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.habit.delete.dialog", defaultValue: "Deleted habit \(habit.name) from Lorvex.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
