import AppIntents
import LorvexCore

struct ProposeLorvexDayTimesIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.day_times.propose.title", defaultValue: "Suggest Lorvex Times", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.day_times.propose.description", defaultValue: "Suggest times for today’s Lorvex tasks, or a specific date’s, around your calendar. Nothing is saved.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.date", defaultValue: "Date", table: "Localizable", bundle: SystemL10n.bundle),
    description: LocalizedStringResource("system.parameter.date.today_when_blank.description", defaultValue: "Leave blank for today.", table: "Localizable", bundle: SystemL10n.bundle),
    kind: .date)
  var date: Date?

  init() {
    date = nil
  }

  init(date: Date?) {
    self.date = date
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let proposal = try await LorvexTaskIntentRunner.proposeDayTimes(date: date.map(IntentDateText.day))
    if proposal.placements.isEmpty, proposal.unscheduled.isEmpty {
      return .result(
        dialog: IntentDialog(
          LocalizedStringResource(
            "system.day_times.nothing_to_place_dialog",
            defaultValue: "Nothing on \(lorvexDayLine(logicalDay: proposal.date)) needs a time.",
            table: "Localizable", bundle: SystemL10n.bundle)))
    }
    guard !proposal.placements.isEmpty else {
      return .result(
        dialog: IntentDialog(
          LocalizedStringResource(
            "system.day_times.none_fit_dialog",
            defaultValue: "No task fits the time left on \(lorvexDayLine(logicalDay: proposal.date)).",
            table: "Localizable", bundle: SystemL10n.bundle)))
    }
    let count = proposal.placements.count
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.day_times.propose.dialog",
          defaultValue: "Suggested times for \(count) tasks on \(lorvexDayLine(logicalDay: proposal.date)).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
