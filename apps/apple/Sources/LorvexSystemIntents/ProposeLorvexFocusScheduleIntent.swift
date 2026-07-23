import AppIntents
import LorvexCore

struct ProposeLorvexFocusScheduleIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.focus.schedule.propose.title", defaultValue: "Propose Lorvex Focus Schedule", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.focus.schedule.propose.description", defaultValue: "Propose a Lorvex focus schedule for today or a specific date.", table: "Localizable", bundle: SystemL10n.bundle))

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
    let schedule = try await LorvexTaskIntentRunner.proposeFocusSchedule(date: date)
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.focus.schedule.propose.dialog_count",
          defaultValue: "Proposed \(schedule.blocks.count) focus blocks for \(schedule.date).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
