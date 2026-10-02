import AppIntents

struct SearchLorvexCalendarEventsIntent: LorvexLocalAuthIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.calendar.search.title", defaultValue: "Search Lorvex Calendar Events", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.calendar.search.description", defaultValue: "Search Lorvex calendar events from Shortcuts.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.query", defaultValue: "Query", table: "Localizable", bundle: SystemL10n.bundle))
  var query: String

  @Parameter(
    title: LocalizedStringResource("system.calendar.parameter.from", defaultValue: "From", table: "Localizable", bundle: SystemL10n.bundle),
    kind: .date)
  var from: Date?

  @Parameter(
    title: LocalizedStringResource("system.calendar.parameter.to", defaultValue: "To", table: "Localizable", bundle: SystemL10n.bundle),
    kind: .date)
  var to: Date?

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.limit", defaultValue: "Limit", table: "Localizable", bundle: SystemL10n.bundle))
  var limit: Int?

  init() {
    query = ""
    from = nil
    to = nil
    limit = nil
  }

  init(query: String, from: Date? = nil, to: Date? = nil, limit: Int? = nil) {
    self.query = query
    self.from = from
    self.to = to
    self.limit = limit
  }

  /// Returns the matching events, including events mirrored from the system
  /// calendars, which Lorvex shows but does not edit.
  func perform() async throws -> some IntentResult & ReturnsValue<[LorvexCalendarEventEntity]> & ProvidesDialog {
    let query = try $query.requiredText()
    let range = IntentDateText.dayRange(from: from, to: to)
    let events = try await LorvexTaskIntentRunner.searchCalendarEvents(
      query: query,
      from: range.from,
      to: range.to,
      limit: limit
    )
    return .result(
      value: events.map(LorvexCalendarEventEntity.init(event:)),
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.calendar.search.dialog_count",
          defaultValue: "Found \(events.count) calendar events in Lorvex.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
