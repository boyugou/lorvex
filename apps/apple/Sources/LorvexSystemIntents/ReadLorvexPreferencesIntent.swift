import AppIntents

struct ReadLorvexPreferencesIntent: LorvexLocalAuthIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.preference.read_all.title", defaultValue: "Read Lorvex Preferences", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.preference.read_all.description", defaultValue: "Read the Lorvex preference map.", table: "Localizable", bundle: SystemL10n.bundle))

  init() {}

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let preferences = try await LorvexTaskIntentRunner.readPreferences()
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.preference.read_all.dialog",
          defaultValue: "\(preferences.values.count) preferences.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
