import AppIntents
import LorvexCore

struct DeleteLorvexHabitReminderIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.habit.reminder.delete.title", defaultValue: "Delete Lorvex Habit Reminder", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.habit.reminder.delete.description", defaultValue: "Delete one of a Lorvex habit’s reminders.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.habit.parameter.reminder", defaultValue: "Reminder", table: "Localizable", bundle: SystemL10n.bundle))
  var reminder: LorvexHabitReminderEntity

  init() {
    reminder = LorvexHabitReminderEntity(id: "", habitID: "", habitName: "", reminderTime: "", enabled: true)
  }

  init(reminder: LorvexHabitReminderEntity) {
    self.reminder = reminder
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    try await requestLorvexDestructiveConfirmation(
      IntentDialog(
        LocalizedStringResource(
          "system.confirm.delete", defaultValue: "Delete this item? This can’t be undone.",
          table: "Localizable", bundle: SystemL10n.bundle)))
    let removed = try await LorvexTaskIntentRunner.deleteHabitReminderPolicy(policyID: reminder.id)
    guard let removed else {
      return .result(
        dialog: IntentDialog(
          LocalizedStringResource(
            "system.habit.reminder.delete.not_found_dialog",
            defaultValue: "That habit reminder no longer exists.",
            table: "Localizable", bundle: SystemL10n.bundle)))
    }
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.habit.reminder.delete.dialog",
          defaultValue: "Deleted the \(removed.habitName) reminder at \(lorvexClockTimeLabel(removed.reminderTime)).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
