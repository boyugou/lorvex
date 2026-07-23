import AppIntents

struct ReadLorvexPreferenceIntent: LorvexLocalAuthIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.preference.read_one.title", defaultValue: "Read Lorvex Preference", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.preference.read_one.description", defaultValue: "Read one Lorvex preference by key.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.preference.parameter.key", defaultValue: "Key", table: "Localizable", bundle: SystemL10n.bundle))
  var key: String

  init() {
    key = ""
  }

  init(key: String) {
    self.key = key
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let value = try await LorvexTaskIntentRunner.readPreference(key: key)
    if value == nil {
      return .result(
        dialog: IntentDialog(
          LocalizedStringResource(
            "system.preference.read_one.not_found_dialog", defaultValue: "No preference found.",
            table: "Localizable", bundle: SystemL10n.bundle)))
    }
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.preference.read_one.found_dialog", defaultValue: "Preference found.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
