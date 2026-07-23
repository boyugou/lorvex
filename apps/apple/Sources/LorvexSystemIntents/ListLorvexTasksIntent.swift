import AppIntents

struct ListLorvexTasksIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.list.title", defaultValue: "List Lorvex Tasks", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.list.description", defaultValue: "List Lorvex tasks by status, list, priority, or text.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.status", defaultValue: "Status", table: "Localizable", bundle: SystemL10n.bundle))
  var status: LorvexTaskStatusOption?

  @Parameter(
    title: LocalizedStringResource("system.list.parameter.list", defaultValue: "List", table: "Localizable", bundle: SystemL10n.bundle))
  var list: LorvexListEntity?

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.priority", defaultValue: "Priority", table: "Localizable", bundle: SystemL10n.bundle))
  var priority: Int?

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.text", defaultValue: "Text", table: "Localizable", bundle: SystemL10n.bundle))
  var text: String?

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.limit", defaultValue: "Limit", table: "Localizable", bundle: SystemL10n.bundle))
  var limit: Int?

  init() {
    status = nil
    list = nil
    priority = nil
    text = nil
    limit = nil
  }

  init(
    status: LorvexTaskStatusOption? = nil,
    list: LorvexListEntity? = nil,
    priority: Int? = nil,
    text: String? = nil,
    limit: Int? = nil
  ) {
    self.status = status
    self.list = list
    self.priority = priority
    self.text = text
    self.limit = limit
  }

  func perform() async throws -> some IntentResult & ReturnsValue<[LorvexTaskEntity]> & ProvidesDialog {
    let result = try await LorvexTaskIntentRunner.listTasks(
      status: status?.rawValue,
      listID: list?.id,
      priority: priority,
      text: text,
      limit: limit
    )
    guard !result.tasks.isEmpty else {
      return .result(
        value: [],
        dialog: IntentDialog(
          LocalizedStringResource(
            "system.task.search.no_matches",
            defaultValue: "No matching tasks.",
            table: "Localizable",
            bundle: SystemL10n.bundle)))
    }
    let titles = result.tasks.prefix(5).map(\.title).joined(separator: ", ")
    let dialog: LocalizedStringResource
    if result.totalMatching > 5 {
      dialog = LocalizedStringResource(
        "system.task.list.dialog.more",
        defaultValue:
          "\(result.totalMatching) Lorvex tasks: \(titles), and \(result.totalMatching - 5) more",
        table: "Localizable",
        bundle: SystemL10n.bundle)
    } else {
      dialog = LocalizedStringResource(
        "system.task.list.dialog",
        defaultValue: "\(result.totalMatching) Lorvex tasks: \(titles)",
        table: "Localizable",
        bundle: SystemL10n.bundle)
    }
    return .result(
      value: result.tasks.map(LorvexTaskEntity.init(task:)),
      dialog: IntentDialog(dialog))
  }
}
