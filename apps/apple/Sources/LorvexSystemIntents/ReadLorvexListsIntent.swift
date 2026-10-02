import AppIntents

struct ReadLorvexListsIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.list.read.title", defaultValue: "Read Lorvex Lists", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.list.read.description", defaultValue: "Read Lorvex list catalog from Shortcuts or Siri.", table: "Localizable", bundle: SystemL10n.bundle))

  init() {}

  func perform() async throws -> some IntentResult & ReturnsValue<[LorvexListEntity]> & ProvidesDialog {
    let lists = try await LorvexTaskIntentRunner.readLists().lists
    let names = SystemIntentListSummary.names(lists.map(\.displayName), total: lists.count)
    return .result(
      value: lists.map(LorvexListEntity.init(list:)),
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.list.read.names_dialog",
          defaultValue: "\(lists.count) Lorvex lists: \(names)",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
