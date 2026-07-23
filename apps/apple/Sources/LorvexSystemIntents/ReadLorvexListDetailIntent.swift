import AppIntents

struct ReadLorvexListDetailIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.list.detail.read.title", defaultValue: "Read Lorvex List Detail", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.list.detail.read.description", defaultValue: "Read a Lorvex list and its tasks.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.list.parameter.list", defaultValue: "List", table: "Localizable", bundle: SystemL10n.bundle))
  var list: LorvexListEntity

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.limit", defaultValue: "Limit", table: "Localizable", bundle: SystemL10n.bundle))
  var limit: Int?

  @Parameter(
    title: LocalizedStringResource("system.list.parameter.offset", defaultValue: "Offset", table: "Localizable", bundle: SystemL10n.bundle))
  var offset: Int?

  init() {
    list = LorvexListEntity(id: "", name: "", openCount: 0, totalCount: 0)
    limit = nil
    offset = nil
  }

  init(list: LorvexListEntity, limit: Int? = nil, offset: Int? = nil) {
    self.list = list
    self.limit = limit
    self.offset = offset
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let detail = try await LorvexTaskIntentRunner.readListDetail(
      id: list.id,
      limit: limit,
      offset: offset
    )
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.list.detail.read.dialog",
          defaultValue: "\(detail.list.name) has \(detail.totalMatching) matching tasks.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
