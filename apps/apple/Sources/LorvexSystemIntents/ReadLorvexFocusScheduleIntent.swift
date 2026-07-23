import AppIntents
import LorvexCore

struct ReadLorvexFocusScheduleIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.focus.schedule.read.title", defaultValue: "Read Lorvex Focus Schedule", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.focus.schedule.read.description", defaultValue: "Read the saved Lorvex focus schedule for today or a specific date.", table: "Localizable", bundle: SystemL10n.bundle))

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
    let schedule = try await LorvexTaskIntentRunner.readFocusSchedule(date: date)
    guard let schedule else {
      return .result(
        dialog: IntentDialog(
          LocalizedStringResource(
            "system.focus.schedule.read.none_dialog", defaultValue: "No Lorvex focus schedule found.",
            table: "Localizable", bundle: SystemL10n.bundle)))
    }
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.focus.schedule.read.dialog_count",
          defaultValue: "\(schedule.blocks.count) scheduled blocks for \(schedule.date).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
