import AppIntents

struct ReadLorvexListsIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.list.read.title", defaultValue: "Read Lorvex Lists", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.list.read.description", defaultValue: "Read Lorvex list catalog from Shortcuts or Siri.", table: "Localizable", bundle: SystemL10n.bundle))

  init() {}

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let snapshot = try await LorvexTaskIntentRunner.readLists()
    let openCount = snapshot.lists.reduce(0) { $0 + $1.openCount }
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.list.read.dialog",
          defaultValue: "Lists: \(snapshot.lists.count), open tasks: \(openCount).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
