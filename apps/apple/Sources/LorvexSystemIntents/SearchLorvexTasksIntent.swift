import AppIntents

struct SearchLorvexTasksIntent: LorvexLocalAuthIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.search.title", defaultValue: "Search Lorvex Tasks", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.search.description", defaultValue: "Search Lorvex tasks by text.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.query", defaultValue: "Query", table: "Localizable", bundle: SystemL10n.bundle))
  var query: String

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.status", defaultValue: "Status", table: "Localizable", bundle: SystemL10n.bundle))
  var status: LorvexTaskStatusOption?

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.limit", defaultValue: "Limit", table: "Localizable", bundle: SystemL10n.bundle))
  var limit: Int?

  init() {
    query = ""
    status = nil
    limit = nil
  }

  init(query: String, status: LorvexTaskStatusOption? = nil, limit: Int? = nil) {
    self.query = query
    self.status = status
    self.limit = limit
  }

  func perform() async throws -> some IntentResult & ReturnsValue<[LorvexTaskEntity]> & ProvidesDialog {
    let result = try await LorvexTaskIntentRunner.searchTasks(
      query: query,
      status: status?.rawValue,
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
        "system.task.search.dialog.more",
        defaultValue:
          "\(result.totalMatching) matching Lorvex tasks: \(titles), and \(result.totalMatching - 5) more",
        table: "Localizable",
        bundle: SystemL10n.bundle)
    } else {
      dialog = LocalizedStringResource(
        "system.task.search.dialog",
        defaultValue: "\(result.totalMatching) matching Lorvex tasks: \(titles)",
        table: "Localizable",
        bundle: SystemL10n.bundle)
    }
    return .result(
      value: result.tasks.map(LorvexTaskEntity.init(task:)),
      dialog: IntentDialog(dialog))
  }
}
