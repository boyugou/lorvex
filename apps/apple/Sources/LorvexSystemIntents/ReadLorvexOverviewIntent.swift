import AppIntents

struct ReadLorvexOverviewIntent: LorvexLocalAuthIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.status.overview.read.title", defaultValue: "Read Lorvex Overview", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.status.overview.read.description", defaultValue: "Read the compact Lorvex overview.", table: "Localizable", bundle: SystemL10n.bundle))

  init() {}

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let overview = try await LorvexTaskIntentRunner.readOverview()
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.status.overview.read.dialog",
          defaultValue: "\(overview.stats.openCount) open tasks for \(overview.date).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
