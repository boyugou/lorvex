import AppIntents

struct BatchDeferLorvexTasksIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.batch.defer.title", defaultValue: "Batch Defer Lorvex Tasks", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.batch.defer.description", defaultValue: "Defer multiple Lorvex tasks to a date.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.batch.parameter.tasks", defaultValue: "Tasks", table: "Localizable", bundle: SystemL10n.bundle))
  var tasks: [LorvexTaskEntity]

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.until", defaultValue: "Until", table: "Localizable", bundle: SystemL10n.bundle),
    kind: .date)
  var until: Date

  init() {
    tasks = []
    until = .now
  }

  init(tasks: [LorvexTaskEntity], until: Date) {
    self.tasks = tasks
    self.until = until
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let result = try await LorvexTaskIntentRunner.batchDeferTasks(
      taskIDs: tasks.map(\.id),
      until: IntentDateText.day(until)
    )
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.task.batch.defer.dialog",
          defaultValue:
            "Deferred \(result.changedIDs.count) tasks; skipped \(result.skipped.count) tasks.",
          table: "Localizable",
          bundle: SystemL10n.bundle)))
  }
}
