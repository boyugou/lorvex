import AppIntents
import LorvexCore

struct ReadLorvexDueTaskRemindersIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.reminders.due.read.title", defaultValue: "Read Lorvex Due Task Reminders", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.reminders.due.read.description", defaultValue: "Read pending Lorvex task reminders that are due.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.as_of", defaultValue: "As Of", table: "Localizable", bundle: SystemL10n.bundle),
    kind: .dateTime)
  var asOf: Date?

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.limit", defaultValue: "Limit", table: "Localizable", bundle: SystemL10n.bundle))
  var limit: Int?

  init() {}

  init(asOf: Date? = nil, limit: Int? = nil) {
    self.asOf = asOf
    self.limit = limit
  }

  /// Returns the due reminders, each titled by its time with its task
  /// underneath; Siri names their tasks.
  func perform() async throws -> some IntentResult & ReturnsValue<[LorvexTaskReminderEntity]> & ProvidesDialog {
    let core = LorvexCoreRuntimeFactory.makeForAppIntent()
    let reminders = try await LorvexTaskIntentRunner.readDueTaskReminders(
      asOf: asOf.map(IntentDateText.timestamp),
      limit: limit,
      core: core
    )
    let entities = try await LorvexTaskReminderEntityQuery.entities(from: reminders, core: core)
    guard !entities.isEmpty else {
      return .result(
        value: [],
        dialog: IntentDialog(
          LocalizedStringResource(
            "system.task.reminders.due.read.none_dialog",
            defaultValue: "No reminders are due.",
            table: "Localizable", bundle: SystemL10n.bundle)))
    }
    let titles = SystemIntentListSummary.names(entities.map(\.taskTitle), total: entities.count)
    return .result(
      value: entities,
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.task.reminders.due.read.names_dialog",
          defaultValue: "\(entities.count) due reminders: \(titles)",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
