import AppIntents

struct ReadLorvexDueTaskRemindersIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.reminders.due.read.title", defaultValue: "Read Lorvex Due Task Reminders", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.reminders.due.read.description", defaultValue: "Read pending Lorvex task reminders that are due.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.as_of", defaultValue: "As Of", table: "Localizable", bundle: SystemL10n.bundle))
  var asOf: String?

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.limit", defaultValue: "Limit", table: "Localizable", bundle: SystemL10n.bundle))
  var limit: Int?

  init() {}

  init(asOf: String? = nil, limit: Int? = nil) {
    self.asOf = asOf
    self.limit = limit
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let reminders = try await LorvexTaskIntentRunner.readDueTaskReminders(
      asOf: asOf,
      limit: limit
    )
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.task.reminders.due.read.dialog_count",
          defaultValue: "\(reminders.count) due reminders.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
