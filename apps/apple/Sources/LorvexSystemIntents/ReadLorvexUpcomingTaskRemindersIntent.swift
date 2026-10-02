import AppIntents
import LorvexCore

struct ReadLorvexUpcomingTaskRemindersIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.reminders.upcoming.read.title", defaultValue: "Read Lorvex Upcoming Task Reminders", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.reminders.upcoming.read.description", defaultValue: "Read pending Lorvex task reminders coming up soon.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.hours_ahead", defaultValue: "Hours Ahead", table: "Localizable", bundle: SystemL10n.bundle))
  var hoursAhead: Int?

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.limit", defaultValue: "Limit", table: "Localizable", bundle: SystemL10n.bundle))
  var limit: Int?

  init() {}

  init(hoursAhead: Int? = nil, limit: Int? = nil) {
    self.hoursAhead = hoursAhead
    self.limit = limit
  }

  /// Returns the upcoming reminders, soonest first, each titled by its time
  /// with its task underneath; Siri names their tasks.
  func perform() async throws -> some IntentResult & ReturnsValue<[LorvexTaskReminderEntity]> & ProvidesDialog {
    let core = LorvexCoreRuntimeFactory.makeForAppIntent()
    let reminders = try await LorvexTaskIntentRunner.readUpcomingTaskReminders(
      hoursAhead: hoursAhead,
      limit: limit,
      core: core
    )
    let entities = try await LorvexTaskReminderEntityQuery.entities(from: reminders, core: core)
    guard !entities.isEmpty else {
      return .result(
        value: [],
        dialog: IntentDialog(
          LocalizedStringResource(
            "system.task.reminders.upcoming.read.none_dialog",
            defaultValue: "No upcoming reminders.",
            table: "Localizable", bundle: SystemL10n.bundle)))
    }
    let titles = SystemIntentListSummary.names(entities.map(\.taskTitle), total: entities.count)
    return .result(
      value: entities,
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.task.reminders.upcoming.read.names_dialog",
          defaultValue: "\(entities.count) upcoming reminders: \(titles)",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
