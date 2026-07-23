import AppIntents
import LorvexCore

struct ReadLorvexCurrentFocusIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.focus.current.read.title", defaultValue: "Read Lorvex Current Focus", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.focus.current.read.description", defaultValue: "Read the Lorvex focus plan for today or a specific date from Shortcuts or Siri.", table: "Localizable", bundle: SystemL10n.bundle))

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
    let focus = try await LorvexTaskIntentRunner.readCurrentFocus(date: date)
    guard let focus else {
      return .result(
        dialog: IntentDialog(
          LocalizedStringResource(
            "system.focus.current.read.none_dialog", defaultValue: "No Lorvex focus plan found.",
            table: "Localizable", bundle: SystemL10n.bundle)))
    }
    let count = focus.taskIDs.count
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.focus.current.read.dialog_count",
          defaultValue: "\(count) focused tasks for \(focus.date).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
