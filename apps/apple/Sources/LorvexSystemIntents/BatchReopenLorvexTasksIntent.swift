import AppIntents

struct BatchReopenLorvexTasksIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.batch.reopen.title", defaultValue: "Batch Reopen Lorvex Tasks", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.batch.reopen.description", defaultValue: "Reopen multiple Lorvex tasks by ID.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.batch.parameter.tasks", defaultValue: "Tasks", table: "Localizable", bundle: SystemL10n.bundle))
  var tasks: [LorvexTaskEntity]

  init() {
    tasks = []
  }

  init(tasks: [LorvexTaskEntity]) {
    self.tasks = tasks
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let result = try await LorvexTaskIntentRunner.batchReopenTasks(taskIDs: tasks.map(\.id))
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.task.batch.reopen.dialog",
          defaultValue:
            "Reopened \(result.changedIDs.count) tasks; skipped \(result.skipped.count) tasks.",
          table: "Localizable",
          bundle: SystemL10n.bundle)))
  }
}
