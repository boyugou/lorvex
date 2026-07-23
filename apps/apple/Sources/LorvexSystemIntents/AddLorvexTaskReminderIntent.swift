import AppIntents

struct AddLorvexTaskReminderIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.reminder.add.title", defaultValue: "Add Lorvex Task Reminder", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.reminder.add.description", defaultValue: "Add one reminder timestamp to a Lorvex task.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.task", defaultValue: "Task", table: "Localizable", bundle: SystemL10n.bundle))
  var task: LorvexTaskEntity

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.reminder_timestamp", defaultValue: "Reminder Timestamp", table: "Localizable", bundle: SystemL10n.bundle))
  var reminderAt: String

  init() {
    task = LorvexTaskEntity(id: "", title: "", status: "")
    reminderAt = ""
  }

  init(task: LorvexTaskEntity, reminderAt: String) {
    self.task = task
    self.reminderAt = reminderAt
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let updated = try await LorvexTaskIntentRunner.addTaskReminder(
      taskID: task.id,
      reminderAt: reminderAt
    )
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.task.reminder.add.dialog",
          defaultValue: "Added reminder to \(updated.title).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
