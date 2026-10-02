import AppIntents

struct RemoveLorvexTaskReminderIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.reminder.remove.title", defaultValue: "Remove Lorvex Task Reminder", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.reminder.remove.description", defaultValue: "Remove one reminder from a Lorvex task.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.reminder", defaultValue: "Reminder", table: "Localizable", bundle: SystemL10n.bundle))
  var reminder: LorvexTaskReminderEntity

  init() {
    reminder = LorvexTaskReminderEntity(
      taskID: "", reminderID: "", reminderAt: "", taskTitle: "", timeZoneIdentifier: "")
  }

  init(reminder: LorvexTaskReminderEntity) {
    self.reminder = reminder
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    try await requestLorvexDestructiveConfirmation(
      IntentDialog(
        LocalizedStringResource(
          "system.confirm.remove", defaultValue: "Remove this item?",
          table: "Localizable", bundle: SystemL10n.bundle)))
    let updated = try await LorvexTaskIntentRunner.removeTaskReminder(
      taskID: reminder.taskID,
      reminderID: reminder.reminderID
    )
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.task.reminder.remove.dialog", defaultValue: "Removed reminder from \(updated.title).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
