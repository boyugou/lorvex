import AppIntents

struct ReadLorvexUpcomingTasksIntent: LorvexLocalAuthIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.upcoming.read.title", defaultValue: "Read Lorvex Upcoming Tasks", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.upcoming.read.description", defaultValue: "Read upcoming Lorvex tasks.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.days_ahead", defaultValue: "Days Ahead", table: "Localizable", bundle: SystemL10n.bundle))
  var daysAhead: Int?

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.limit", defaultValue: "Limit", table: "Localizable", bundle: SystemL10n.bundle))
  var limit: Int?

  init() {
    daysAhead = nil
    limit = nil
  }

  init(daysAhead: Int? = nil, limit: Int? = nil) {
    self.daysAhead = daysAhead
    self.limit = limit
  }

  func perform() async throws -> some IntentResult & ReturnsValue<[LorvexTaskEntity]> & ProvidesDialog {
    let tasks = try await LorvexTaskIntentRunner.readUpcomingTasks(
      daysAhead: daysAhead,
      limit: limit
    )
    return .result(
      value: tasks.map(LorvexTaskEntity.init(task:)),
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.task.upcoming.read.dialog", defaultValue: "\(tasks.count) upcoming Lorvex tasks.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
