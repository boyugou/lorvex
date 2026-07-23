import AppIntents

struct ReadLorvexListHealthIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.list.health.read.title", defaultValue: "Read Lorvex List Health", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.list.health.read.description", defaultValue: "Read Lorvex list health counts.", table: "Localizable", bundle: SystemL10n.bundle))

  init() {}

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let health = try await LorvexTaskIntentRunner.readListHealth()
    let overdue = health.lists.reduce(0) { $0 + $1.overdueOpenCount }
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.list.health.read.dialog",
          defaultValue: "Lists: \(health.totalLists) on \(health.date), overdue tasks: \(overdue).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
