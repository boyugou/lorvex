import AppIntents
import LorvexCore

struct ReadLorvexRuntimeDiagnosticsIntent: LorvexLocalAuthIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.diagnostics.read.title", defaultValue: "Read Lorvex Diagnostics", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.diagnostics.read.description", defaultValue: "Read Lorvex setup and sync diagnostics from Shortcuts or Siri.", table: "Localizable", bundle: SystemL10n.bundle))

  init() {}

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let diagnostics = try await LorvexTaskIntentRunner.readRuntimeDiagnostics()
    let dialog: LocalizedStringResource
    if diagnostics.setup.setupCompleted {
      dialog = LocalizedStringResource(
        "system.diagnostics.read.dialog.complete",
        defaultValue:
          "Lorvex setup is complete. Sync backend: \(diagnostics.sync.backend). Pending: \(diagnostics.sync.pendingCount), failed: \(diagnostics.sync.failedCount).",
        table: "Localizable",
        bundle: SystemL10n.bundle)
    } else {
      dialog = LocalizedStringResource(
        "system.diagnostics.read.dialog.incomplete",
        defaultValue:
          "Lorvex setup is incomplete. Sync backend: \(diagnostics.sync.backend). Pending: \(diagnostics.sync.pendingCount), failed: \(diagnostics.sync.failedCount).",
        table: "Localizable",
        bundle: SystemL10n.bundle)
    }
    return .result(dialog: IntentDialog(dialog))
  }
}
