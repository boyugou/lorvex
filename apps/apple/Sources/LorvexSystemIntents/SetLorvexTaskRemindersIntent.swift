import AppIntents

struct SetLorvexTaskRemindersIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.reminders.set.title", defaultValue: "Set Lorvex Task Reminders", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.reminders.set.description", defaultValue: "Replace a Lorvex task's reminder timestamps from Shortcuts or Siri.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.task", defaultValue: "Task", table: "Localizable", bundle: SystemL10n.bundle))
  var task: LorvexTaskEntity

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.reminder_timestamps", defaultValue: "Reminder Timestamps", table: "Localizable", bundle: SystemL10n.bundle),
    description: LocalizedStringResource("system.task.parameter.reminder_timestamps.iso_list.description", defaultValue: "Comma or newline separated ISO timestamps.", table: "Localizable", bundle: SystemL10n.bundle))
  var reminders: String

  init() {
    task = LorvexTaskEntity(id: "", title: "", status: "")
    reminders = ""
  }

  init(task: LorvexTaskEntity, reminders: String) {
    self.task = task
    self.reminders = reminders
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let updated = try await LorvexTaskIntentRunner.setTaskReminders(
      id: task.id,
      remindersText: reminders
    )
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.task.reminders.set.dialog",
          defaultValue: "Set \(updated.reminders.count) reminders for \(updated.title).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
