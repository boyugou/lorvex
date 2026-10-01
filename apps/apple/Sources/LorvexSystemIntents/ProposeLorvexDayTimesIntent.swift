import AppIntents
import LorvexCore

struct ProposeLorvexDayTimesIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.day_times.propose.title", defaultValue: "Suggest Lorvex Times", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.day_times.propose.description", defaultValue: "Suggest times for today’s Lorvex tasks, or a specific date’s, around your calendar. Nothing is saved.", table: "Localizable", bundle: SystemL10n.bundle))

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
    let proposal = try await LorvexTaskIntentRunner.proposeDayTimes(date: date)
    if proposal.placements.isEmpty, proposal.unscheduled.isEmpty {
      return .result(
        dialog: IntentDialog(
          LocalizedStringResource(
            "system.day_times.nothing_to_place_dialog",
            defaultValue: "Nothing on \(proposal.date) needs a time.",
            table: "Localizable", bundle: SystemL10n.bundle)))
    }
    guard !proposal.placements.isEmpty else {
      return .result(
        dialog: IntentDialog(
          LocalizedStringResource(
            "system.day_times.none_fit_dialog",
            defaultValue: "No task fits the time left on \(proposal.date).",
            table: "Localizable", bundle: SystemL10n.bundle)))
    }
    let count = proposal.placements.count
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.day_times.propose.dialog",
          defaultValue: "Suggested times for \(count) tasks on \(proposal.date).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
