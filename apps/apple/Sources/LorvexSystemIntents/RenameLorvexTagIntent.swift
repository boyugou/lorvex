import AppIntents

struct RenameLorvexTagIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.tag.rename.title", defaultValue: "Rename Lorvex Tag", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.tag.rename.description", defaultValue: "Rename a Lorvex task tag from Shortcuts or Siri.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.tag.parameter.old_tag", defaultValue: "Old Tag", table: "Localizable", bundle: SystemL10n.bundle))
  var oldTag: String

  @Parameter(
    title: LocalizedStringResource("system.tag.parameter.new_tag", defaultValue: "New Tag", table: "Localizable", bundle: SystemL10n.bundle))
  var newTag: String

  init() {
    oldTag = ""
    newTag = ""
  }

  init(oldTag: String, newTag: String) {
    self.oldTag = oldTag
    self.newTag = newTag
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let renamed = try await LorvexTaskIntentRunner.renameTag(oldTag: oldTag, newTag: newTag)
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.tag.rename.dialog", defaultValue: "Renamed Lorvex tag to \(renamed).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
