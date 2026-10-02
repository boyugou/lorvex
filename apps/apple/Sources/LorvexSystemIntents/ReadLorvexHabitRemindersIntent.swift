import AppIntents
import LorvexCore

struct ReadLorvexHabitRemindersIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.habit.reminders.read.title", defaultValue: "Read Lorvex Habit Reminders", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.habit.reminders.read.description", defaultValue: "Read the reminders of a Lorvex habit.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.habit.parameter.habit", defaultValue: "Habit", table: "Localizable", bundle: SystemL10n.bundle))
  var habit: LorvexHabitEntity

  init() {
    habit = LorvexHabitEntity(id: "", name: "", completionsToday: 0, targetCount: 0)
  }

  init(habit: LorvexHabitEntity) {
    self.habit = habit
  }

  func perform() async throws -> some IntentResult & ReturnsValue<[LorvexHabitReminderEntity]> & ProvidesDialog {
    let reminders = try await LorvexTaskIntentRunner.readHabitReminderPolicies(id: habit.id)
      .map(LorvexHabitReminderEntity.init(policy:))
      .sorted { $0.reminderTime < $1.reminderTime }
    return .result(
      value: reminders,
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.habit.reminders.read.dialog_count",
          defaultValue: "\(habit.name) has \(reminders.count) reminders.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
