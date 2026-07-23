import AppIntents

struct RemoveLorvexTaskReminderIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.reminder.remove.title", defaultValue: "Remove Lorvex Task Reminder", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.reminder.remove.description", defaultValue: "Remove one reminder from a Lorvex task.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.task", defaultValue: "Task", table: "Localizable", bundle: SystemL10n.bundle))
  var task: LorvexTaskEntity

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.reminder_id", defaultValue: "Reminder ID", table: "Localizable", bundle: SystemL10n.bundle))
  var reminderID: String

  init() {
    task = LorvexTaskEntity(id: "", title: "", status: "")
    reminderID = ""
  }

  init(task: LorvexTaskEntity, reminderID: String) {
    self.task = task
    self.reminderID = reminderID
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    try await requestLorvexDestructiveConfirmation(
      IntentDialog(
        LocalizedStringResource(
          "system.confirm.remove", defaultValue: "Remove this item?",
          table: "Localizable", bundle: SystemL10n.bundle)))
    let updated = try await LorvexTaskIntentRunner.removeTaskReminder(
      taskID: task.id,
      reminderID: reminderID
    )
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.task.reminder.remove.dialog", defaultValue: "Removed reminder from \(updated.title).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
