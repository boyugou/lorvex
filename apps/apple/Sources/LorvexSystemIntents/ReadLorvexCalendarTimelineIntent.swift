import AppIntents

struct ReadLorvexCalendarTimelineIntent: LorvexLocalAuthIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.calendar.timeline.read.title", defaultValue: "Read Lorvex Calendar Timeline", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.calendar.timeline.read.description", defaultValue: "Read Lorvex calendar events for a date range.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.calendar.parameter.from", defaultValue: "From", table: "Localizable", bundle: SystemL10n.bundle),
    kind: .date)
  var from: Date

  @Parameter(
    title: LocalizedStringResource("system.calendar.parameter.to", defaultValue: "To", table: "Localizable", bundle: SystemL10n.bundle),
    kind: .date)
  var to: Date

  init() {
    from = .now
    to = .now
  }

  init(from: Date, to: Date) {
    self.from = from
    self.to = to
  }

  /// Returns the range's events in time order, including events mirrored
  /// from the system calendars, which Lorvex shows but does not edit.
  func perform() async throws -> some IntentResult & ReturnsValue<[LorvexCalendarEventEntity]> & ProvidesDialog {
    let range = IntentDateText.dayRange(from: from, to: to)
    let timeline = try await LorvexTaskIntentRunner.readCalendarTimeline(
      from: range.from, to: range.to)
    return .result(
      value: timeline.events.map(LorvexCalendarEventEntity.init(event:)),
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.calendar.timeline.read.dialog_count",
          defaultValue: "\(timeline.events.count) calendar events in Lorvex.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
