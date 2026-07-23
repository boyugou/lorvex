import AppIntents

struct BatchMoveLorvexTasksIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.batch.move.title", defaultValue: "Batch Move Lorvex Tasks", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.batch.move.description", defaultValue: "Move multiple Lorvex tasks to a list.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.batch.parameter.tasks", defaultValue: "Tasks", table: "Localizable", bundle: SystemL10n.bundle))
  var tasks: [LorvexTaskEntity]

  @Parameter(
    title: LocalizedStringResource("system.list.parameter.list", defaultValue: "List", table: "Localizable", bundle: SystemL10n.bundle))
  var list: LorvexListEntity

  init() {
    tasks = []
    list = LorvexListEntity(id: "", name: "", openCount: 0, totalCount: 0)
  }

  init(tasks: [LorvexTaskEntity], list: LorvexListEntity) {
    self.tasks = tasks
    self.list = list
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let moved = try await LorvexTaskIntentRunner.batchMoveTasks(
      taskIDs: tasks.map(\.id),
      listID: list.id
    )
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.task.batch.move.dialog_count", defaultValue: "Moved \(moved.count) tasks.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
