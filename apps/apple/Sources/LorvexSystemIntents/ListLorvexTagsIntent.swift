import AppIntents

struct ListLorvexTagsIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.tag.list.title", defaultValue: "List Lorvex Tags", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.tag.list.description", defaultValue: "List all Lorvex task tags from Shortcuts or Siri.", table: "Localizable", bundle: SystemL10n.bundle))

  init() {}

  func perform() async throws -> some IntentResult & ReturnsValue<[String]> & ProvidesDialog {
    let tags = try await LorvexTaskIntentRunner.listAllTags()
    guard !tags.isEmpty else {
      return .result(
        value: [],
        dialog: IntentDialog(
          LocalizedStringResource(
            "system.tag.list.empty_summary",
            defaultValue: "No tags in Lorvex.",
            table: "Localizable",
            bundle: SystemL10n.bundle)))
    }
    let summary = SystemIntentListSummary.names(tags, total: tags.count, shown: tags.count)
    let dialog = LocalizedStringResource(
      "system.tag.list.dialog",
      defaultValue: "\(tags.count) Lorvex tags: \(summary)",
      table: "Localizable",
      bundle: SystemL10n.bundle)
    return .result(value: tags, dialog: IntentDialog(dialog))
  }
}
