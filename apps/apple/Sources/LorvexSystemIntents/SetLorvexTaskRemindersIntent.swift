import AppIntents

struct SetLorvexTaskRemindersIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.reminders.set.title", defaultValue: "Set Lorvex Task Reminders", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.reminders.set.description", defaultValue: "Replace a Lorvex task’s reminders from Shortcuts or Siri.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.task", defaultValue: "Task", table: "Localizable", bundle: SystemL10n.bundle))
  var task: LorvexTaskEntity

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.reminder_times", defaultValue: "Reminder Times", table: "Localizable", bundle: SystemL10n.bundle),
    kind: .dateTime)
  var reminders: [Date]

  init() {
    task = LorvexTaskEntity(id: "", title: "", status: "")
    reminders = []
  }

  init(task: LorvexTaskEntity, reminders: [Date]) {
    self.task = task
    self.reminders = reminders
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    guard !reminders.isEmpty else { throw $reminders.needsValueError() }
    let updated = try await LorvexTaskIntentRunner.setTaskReminders(
      id: task.id,
      reminderAts: reminders.map(IntentDateText.timestamp)
    )
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.task.reminders.set.dialog",
          defaultValue: "Set \(updated.reminders.count) reminders for \(updated.title).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
