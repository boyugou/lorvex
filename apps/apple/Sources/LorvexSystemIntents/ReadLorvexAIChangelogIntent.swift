import AppIntents

struct ReadLorvexAIChangelogIntent: LorvexLocalAuthIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.ai_changelog.read.title", defaultValue: "Read Lorvex AI Changelog", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.ai_changelog.read.description", defaultValue: "Read recent Lorvex AI changelog entries from Shortcuts or Siri.", table: "Localizable", bundle: SystemL10n.bundle))

  init() {}

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let changelog = try await LorvexTaskIntentRunner.readAIChangelog()
    guard let summary = changelog.entries.first?.summary else {
      return .result(
        dialog: IntentDialog(
          LocalizedStringResource(
            "system.ai_changelog.read.empty_summary",
            defaultValue: "No recent AI changelog entries.",
            table: "Localizable",
            bundle: SystemL10n.bundle)))
    }
    let dialog = LocalizedStringResource(
      "system.ai_changelog.read.dialog",
      defaultValue: "\(changelog.entries.count) changelog entries. \(summary)",
      table: "Localizable",
      bundle: SystemL10n.bundle)
    return .result(dialog: IntentDialog(dialog))
  }
}
