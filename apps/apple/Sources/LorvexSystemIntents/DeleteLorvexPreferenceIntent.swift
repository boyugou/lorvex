import AppIntents

struct DeleteLorvexPreferenceIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.preference.delete.title", defaultValue: "Delete Lorvex Preference", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.preference.delete.description", defaultValue: "Remove one Lorvex preference by key.", table: "Localizable", bundle: SystemL10n.bundle))

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
    try await requestLorvexDestructiveConfirmation(
      IntentDialog(
        LocalizedStringResource(
          "system.confirm.delete", defaultValue: "Delete this item? This can't be undone.",
          table: "Localizable", bundle: SystemL10n.bundle)))
    try await LorvexTaskIntentRunner.deletePreference(key: key)
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.preference.delete.dialog", defaultValue: "Preference removed.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
