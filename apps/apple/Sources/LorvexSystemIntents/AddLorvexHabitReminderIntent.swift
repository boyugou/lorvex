import AppIntents
import LorvexCore

struct AddLorvexHabitReminderIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.habit.reminder.add.title", defaultValue: "Add Lorvex Habit Reminder", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.habit.reminder.add.description", defaultValue: "Add a reminder to a Lorvex habit.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.habit.parameter.habit", defaultValue: "Habit", table: "Localizable", bundle: SystemL10n.bundle))
  var habit: LorvexHabitEntity

  @Parameter(
    title: LocalizedStringResource("system.habit.parameter.reminder_time", defaultValue: "Reminder Time", table: "Localizable", bundle: SystemL10n.bundle),
    kind: .time)
  var reminderTime: Date

  init() {
    habit = LorvexHabitEntity(id: "", name: "", completionsToday: 0, targetCount: 0)
    reminderTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
  }

  init(habit: LorvexHabitEntity, reminderTime: Date) {
    self.habit = habit
    self.reminderTime = reminderTime
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let policy = try await LorvexTaskIntentRunner.upsertHabitReminderPolicy(
      id: habit.id,
      reminderTime: IntentDateText.time(reminderTime),
      enabled: true
    )
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.habit.reminder.set.dialog",
          defaultValue: "Set \(habit.name) reminder at \(lorvexClockTimeLabel(policy.reminderTime)).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
