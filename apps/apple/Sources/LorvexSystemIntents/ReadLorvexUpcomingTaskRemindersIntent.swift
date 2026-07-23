import AppIntents

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

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let reminders = try await LorvexTaskIntentRunner.readUpcomingTaskReminders(
      hoursAhead: hoursAhead,
      limit: limit
    )
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.task.reminders.upcoming.read.dialog_count",
          defaultValue: "\(reminders.count) upcoming reminders.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
