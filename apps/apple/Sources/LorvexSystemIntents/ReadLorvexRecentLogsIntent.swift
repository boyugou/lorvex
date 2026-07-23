import AppIntents

struct ReadLorvexRecentLogsIntent: LorvexLocalAuthIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.logs.recent.read.title", defaultValue: "Read Lorvex Recent Logs", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.logs.recent.read.description", defaultValue: "Read recent Lorvex diagnostic logs from Shortcuts or Siri.", table: "Localizable", bundle: SystemL10n.bundle))

  init() {}

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let logs = try await LorvexTaskIntentRunner.readRecentLogs()
    guard let summary = logs.entries.first?.summary else {
      return .result(
        dialog: IntentDialog(
          LocalizedStringResource(
            "system.logs.recent.read.empty_summary",
            defaultValue: "No recent diagnostic logs.",
            table: "Localizable",
            bundle: SystemL10n.bundle)))
    }
    let dialog = LocalizedStringResource(
      "system.logs.recent.read.dialog",
      defaultValue: "\(logs.entries.count) recent logs. \(summary)",
      table: "Localizable",
      bundle: SystemL10n.bundle)
    return .result(dialog: IntentDialog(dialog))
  }
}
