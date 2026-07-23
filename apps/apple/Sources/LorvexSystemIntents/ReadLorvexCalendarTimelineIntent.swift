import AppIntents

struct ReadLorvexCalendarTimelineIntent: LorvexLocalAuthIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.calendar.timeline.read.title", defaultValue: "Read Lorvex Calendar Timeline", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.calendar.timeline.read.description", defaultValue: "Read Lorvex calendar events for a date range.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.calendar.parameter.from", defaultValue: "From", table: "Localizable", bundle: SystemL10n.bundle),
    description: LocalizedStringResource("system.calendar.parameter.from.required_date.description", defaultValue: "Start date in YYYY-MM-DD format.", table: "Localizable", bundle: SystemL10n.bundle))
  var from: String

  @Parameter(
    title: LocalizedStringResource("system.calendar.parameter.to", defaultValue: "To", table: "Localizable", bundle: SystemL10n.bundle),
    description: LocalizedStringResource("system.calendar.parameter.to.required_date.description", defaultValue: "End date in YYYY-MM-DD format.", table: "Localizable", bundle: SystemL10n.bundle))
  var to: String

  init() {
    from = ""
    to = ""
  }

  init(from: String, to: String) {
    self.from = from
    self.to = to
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let timeline = try await LorvexTaskIntentRunner.readCalendarTimeline(from: from, to: to)
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.calendar.timeline.read.dialog_count",
          defaultValue: "\(timeline.events.count) calendar events in Lorvex.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
