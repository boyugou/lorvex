import AppIntents

struct ReadLorvexSetupStatusIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.status.setup.read.title", defaultValue: "Read Lorvex Setup Status", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.status.setup.read.description", defaultValue: "Read Lorvex setup status from Shortcuts or Siri.", table: "Localizable", bundle: SystemL10n.bundle))

  init() {}

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let setup = try await LorvexTaskIntentRunner.readSetupStatus()
    let dialog: LocalizedStringResource
    if setup.setupCompleted {
      dialog = LocalizedStringResource(
        "system.status.setup.read.dialog.complete",
        defaultValue:
          "Lorvex setup is complete. Lists: \(setup.listCount), tasks: \(setup.taskCount).",
        table: "Localizable",
        bundle: SystemL10n.bundle)
    } else {
      dialog = LocalizedStringResource(
        "system.status.setup.read.dialog.incomplete",
        defaultValue:
          "Lorvex setup is incomplete. Lists: \(setup.listCount), tasks: \(setup.taskCount).",
        table: "Localizable",
        bundle: SystemL10n.bundle)
    }
    return .result(dialog: IntentDialog(dialog))
  }
}
