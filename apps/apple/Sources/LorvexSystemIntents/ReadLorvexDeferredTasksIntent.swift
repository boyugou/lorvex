import AppIntents

struct ReadLorvexDeferredTasksIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.deferred.read.title", defaultValue: "Read Lorvex Deferred Tasks", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.deferred.read.description", defaultValue: "Read Lorvex tasks that have been deferred.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.list.parameter.list", defaultValue: "List", table: "Localizable", bundle: SystemL10n.bundle))
  var list: LorvexListEntity?

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.limit", defaultValue: "Limit", table: "Localizable", bundle: SystemL10n.bundle))
  var limit: Int?

  init() {
    list = nil
    limit = nil
  }

  init(list: LorvexListEntity? = nil, limit: Int? = nil) {
    self.list = list
    self.limit = limit
  }

  func perform() async throws -> some IntentResult & ReturnsValue<[LorvexTaskEntity]> & ProvidesDialog {
    let result = try await LorvexTaskIntentRunner.readDeferredTasks(
      listID: list?.id,
      limit: limit
    )
    return .result(
      value: result.tasks.map(LorvexTaskEntity.init(task:)),
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.task.deferred.read.dialog",
          defaultValue: "\(result.totalMatching) deferred Lorvex tasks.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
