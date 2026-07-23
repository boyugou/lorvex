import AppIntents

struct ReadLorvexGuideIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.guide.read.title", defaultValue: "Read Lorvex Guide", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.guide.read.description", defaultValue: "Read contextual Lorvex guidance from Shortcuts or Siri.", table: "Localizable", bundle: SystemL10n.bundle))

  init() {}

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let guide = try await LorvexTaskIntentRunner.readGuide()
    let nextAction = guide.suggestedActions.first.map { " \($0)" } ?? ""
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.guide.read.dialog", defaultValue: "\(guide.topic): \(guide.summary)\(nextAction)",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
