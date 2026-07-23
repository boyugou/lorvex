import AppIntents
import LorvexCore

struct SaveLorvexFocusScheduleIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.focus.schedule.save.title", defaultValue: "Save Lorvex Focus Schedule", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.focus.schedule.save.description", defaultValue: "Propose and save a Lorvex focus schedule for today or a specific date.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.date", defaultValue: "Date", table: "Localizable", bundle: SystemL10n.bundle),
    description: LocalizedStringResource("system.task.parameter.date.optional_today.description", defaultValue: "Optional date in YYYY-MM-DD format. Leave blank for today.", table: "Localizable", bundle: SystemL10n.bundle))
  var date: String?

  @Parameter(
    title: LocalizedStringResource("system.focus.schedule.parameter.rationale", defaultValue: "Rationale", table: "Localizable", bundle: SystemL10n.bundle),
    description: LocalizedStringResource("system.focus.schedule.parameter.rationale.description", defaultValue: "Optional note explaining why this schedule was saved.", table: "Localizable", bundle: SystemL10n.bundle))
  var rationale: String?

  init() {
    date = nil
    rationale = nil
  }

  init(date: String?, rationale: String? = nil) {
    self.date = date
    self.rationale = rationale
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let schedule = try await LorvexTaskIntentRunner.saveProposedFocusSchedule(
      date: date,
      rationale: rationale
    )
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.focus.schedule.save.dialog_count",
          defaultValue: "Saved \(schedule.blocks.count) focus blocks for \(schedule.date).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
