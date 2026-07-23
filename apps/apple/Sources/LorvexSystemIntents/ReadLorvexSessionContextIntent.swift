import AppIntents

struct ReadLorvexSessionContextIntent: LorvexLocalAuthIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.status.session_context.read.title", defaultValue: "Read Lorvex Session Context", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.status.session_context.read.description", defaultValue: "Read Lorvex's current date and sync status.", table: "Localizable", bundle: SystemL10n.bundle))

  init() {}

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let context = try await LorvexTaskIntentRunner.readSessionContext()
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.status.session_context.read.dialog",
          defaultValue: "\(context.date), sync backend \(context.syncBackend).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
