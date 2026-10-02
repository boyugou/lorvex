import AppIntents
import LorvexCore

struct ReadLorvexOverviewIntent: LorvexLocalAuthIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.status.overview.read.title", defaultValue: "Read Lorvex Overview", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.status.overview.read.description", defaultValue: "Hear how many tasks are open and which come first.", table: "Localizable", bundle: SystemL10n.bundle))

  init() {}

  /// Returns the highest-priority open tasks; Siri says how many tasks are
  /// open in all and names those first few.
  func perform() async throws -> some IntentResult & ReturnsValue<[LorvexTaskEntity]> & ProvidesDialog {
    let overview = try await LorvexTaskIntentRunner.readOverview()
    let topTasks = overview.topTasks.map {
      LorvexTaskEntity(id: $0.id, title: $0.title, status: $0.status)
    }
    let openCount = overview.stats.openCount
    guard openCount > 0, !topTasks.isEmpty else {
      return .result(
        value: topTasks,
        dialog: IntentDialog(
          LocalizedStringResource(
            "system.status.overview.read.empty_dialog",
            defaultValue: "No open tasks.",
            table: "Localizable", bundle: SystemL10n.bundle)))
    }
    let titles = SystemIntentListSummary.names(topTasks.map(\.title), total: topTasks.count)
    return .result(
      value: topTasks,
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.status.overview.read.summary_dialog",
          defaultValue: "\(openCount) open tasks. Most important: \(titles).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
