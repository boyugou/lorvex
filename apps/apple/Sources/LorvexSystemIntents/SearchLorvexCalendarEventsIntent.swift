import AppIntents

struct SearchLorvexCalendarEventsIntent: LorvexLocalAuthIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.calendar.search.title", defaultValue: "Search Lorvex Calendar Events", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.calendar.search.description", defaultValue: "Search Lorvex calendar events from Shortcuts.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.query", defaultValue: "Query", table: "Localizable", bundle: SystemL10n.bundle))
  var query: String

  @Parameter(
    title: LocalizedStringResource("system.calendar.parameter.from", defaultValue: "From", table: "Localizable", bundle: SystemL10n.bundle),
    description: LocalizedStringResource("system.calendar.parameter.from.optional_date.description", defaultValue: "Optional start date in YYYY-MM-DD format.", table: "Localizable", bundle: SystemL10n.bundle))
  var from: String?

  @Parameter(
    title: LocalizedStringResource("system.calendar.parameter.to", defaultValue: "To", table: "Localizable", bundle: SystemL10n.bundle),
    description: LocalizedStringResource("system.calendar.parameter.to.optional_date.description", defaultValue: "Optional end date in YYYY-MM-DD format.", table: "Localizable", bundle: SystemL10n.bundle))
  var to: String?

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.limit", defaultValue: "Limit", table: "Localizable", bundle: SystemL10n.bundle))
  var limit: Int?

  init() {
    query = ""
    from = nil
    to = nil
    limit = nil
  }

  init(query: String, from: String? = nil, to: String? = nil, limit: Int? = nil) {
    self.query = query
    self.from = from
    self.to = to
    self.limit = limit
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let events = try await LorvexTaskIntentRunner.searchCalendarEvents(
      query: query,
      from: from,
      to: to,
      limit: limit
    )
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.calendar.search.dialog_count",
          defaultValue: "Found \(events.count) calendar events in Lorvex.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
