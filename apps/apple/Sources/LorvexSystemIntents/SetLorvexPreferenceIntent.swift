import AppIntents

struct SetLorvexPreferenceIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.preference.set.title", defaultValue: "Set Lorvex Preference", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.preference.set.description", defaultValue: "Set one Lorvex preference value.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.preference.parameter.key", defaultValue: "Key", table: "Localizable", bundle: SystemL10n.bundle))
  var key: String

  @Parameter(
    title: LocalizedStringResource("system.preference.parameter.value", defaultValue: "Value", table: "Localizable", bundle: SystemL10n.bundle))
  var value: String

  init() {
    key = ""
    value = ""
  }

  init(key: String, value: String) {
    self.key = key
    self.value = value
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    _ = try await LorvexTaskIntentRunner.setPreference(key: key, value: value)
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.preference.set.dialog", defaultValue: "Preference updated.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
