import AppIntents

struct ReadLorvexSyncStatusIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.status.sync.read.title", defaultValue: "Read Lorvex Sync Status", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.status.sync.read.description", defaultValue: "Read Lorvex sync status from Shortcuts or Siri.", table: "Localizable", bundle: SystemL10n.bundle))

  init() {}

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let sync = try await LorvexTaskIntentRunner.readSyncStatus()
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.status.sync.read.dialog",
          defaultValue:
            "Lorvex sync backend: \(sync.backend). Pending: \(sync.pendingCount), failed: \(sync.failedCount).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
