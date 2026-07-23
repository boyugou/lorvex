import AppIntents

struct ReadLorvexLinkedTasksForEventIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.calendar.linked_tasks_for_event.read.title", defaultValue: "Read Lorvex Linked Tasks for Event", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.calendar.linked_tasks_for_event.read.description", defaultValue: "Read Lorvex tasks linked to a calendar event.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.calendar.parameter.event", defaultValue: "Calendar Event", table: "Localizable", bundle: SystemL10n.bundle))
  var event: LorvexCalendarEventEntity

  init() {
    event = LorvexCalendarEventEntity(
      id: "", title: "", startDate: "", startTime: nil, endTime: nil, allDay: false)
  }

  init(event: LorvexCalendarEventEntity) {
    self.event = event
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let tasks = try await LorvexTaskIntentRunner.readLinkedTasksForEvent(eventID: event.eventID)
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.calendar.linked_tasks_for_event.read.dialog_count",
          defaultValue: "\(event.title) has \(tasks.count) linked Lorvex tasks.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
