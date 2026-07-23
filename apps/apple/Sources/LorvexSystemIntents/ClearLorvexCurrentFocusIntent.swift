import AppIntents
import LorvexCore

struct ClearLorvexCurrentFocusIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.focus.current.clear.title", defaultValue: "Clear Lorvex Current Focus", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.focus.current.clear.description", defaultValue: "Clear the Lorvex focus plan for today or a specific date from Shortcuts or Siri.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.date", defaultValue: "Date", table: "Localizable", bundle: SystemL10n.bundle),
    description: LocalizedStringResource("system.task.parameter.date.optional_today.description", defaultValue: "Optional date in YYYY-MM-DD format. Leave blank for today.", table: "Localizable", bundle: SystemL10n.bundle))
  var date: String?

  init() {
    date = nil
  }

  init(date: String?) {
    self.date = date
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    try await requestLorvexDestructiveConfirmation(
      IntentDialog(
        LocalizedStringResource(
          "system.confirm.clear_focus", defaultValue: "Clear the current focus plan?",
          table: "Localizable", bundle: SystemL10n.bundle)))
    let clearedDate = try await LorvexTaskIntentRunner.clearCurrentFocus(date: date)
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.focus.current.clear.dialog", defaultValue: "Cleared Lorvex focus for \(clearedDate).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
