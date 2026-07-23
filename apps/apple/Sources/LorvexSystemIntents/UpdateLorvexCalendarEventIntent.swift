import AppIntents
import LorvexCore

struct UpdateLorvexCalendarEventIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.calendar.update.title", defaultValue: "Update Lorvex Calendar Event", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.calendar.update.description", defaultValue: "Update a Lorvex calendar event from Shortcuts or Siri.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.calendar.parameter.event", defaultValue: "Calendar Event", table: "Localizable", bundle: SystemL10n.bundle))
  var event: LorvexCalendarEventEntity

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.title", defaultValue: "Title", table: "Localizable", bundle: SystemL10n.bundle),
    description: LocalizedStringResource("system.calendar.parameter.title.optional_replacement.description", defaultValue: "Optional replacement title.", table: "Localizable", bundle: SystemL10n.bundle))
  var title: String?

  @Parameter(
    title: LocalizedStringResource("system.calendar.parameter.start_date", defaultValue: "Start Date", table: "Localizable", bundle: SystemL10n.bundle),
    description: LocalizedStringResource("system.calendar.parameter.start_date.optional_replacement.description", defaultValue: "Optional replacement date in YYYY-MM-DD format.", table: "Localizable", bundle: SystemL10n.bundle))
  var startDate: String?

  @Parameter(
    title: LocalizedStringResource("system.calendar.parameter.start_time", defaultValue: "Start Time", table: "Localizable", bundle: SystemL10n.bundle),
    description: LocalizedStringResource("system.calendar.parameter.start_time.optional_replacement.description", defaultValue: "Optional replacement time in HH:MM format.", table: "Localizable", bundle: SystemL10n.bundle))
  var startTime: String?

  @Parameter(
    title: LocalizedStringResource("system.calendar.parameter.end_time", defaultValue: "End Time", table: "Localizable", bundle: SystemL10n.bundle),
    description: LocalizedStringResource("system.calendar.parameter.end_time.optional_replacement.description", defaultValue: "Optional replacement time in HH:MM format.", table: "Localizable", bundle: SystemL10n.bundle))
  var endTime: String?

  @Parameter(
    title: LocalizedStringResource("system.calendar.parameter.all_day", defaultValue: "All Day", table: "Localizable", bundle: SystemL10n.bundle),
    description: LocalizedStringResource("system.calendar.parameter.all_day.optional_replacement.description", defaultValue: "Optional replacement all-day setting.", table: "Localizable", bundle: SystemL10n.bundle))
  var allDay: Bool?

  @Parameter(
    title: LocalizedStringResource("system.calendar.parameter.location", defaultValue: "Location", table: "Localizable", bundle: SystemL10n.bundle),
    description: LocalizedStringResource("system.calendar.parameter.location.optional_replacement.description", defaultValue: "Optional replacement location.", table: "Localizable", bundle: SystemL10n.bundle))
  var location: String?

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.notes", defaultValue: "Notes", table: "Localizable", bundle: SystemL10n.bundle),
    description: LocalizedStringResource("system.calendar.parameter.notes.optional_replacement.description", defaultValue: "Optional replacement notes.", table: "Localizable", bundle: SystemL10n.bundle))
  var notes: String?

  init() {
    event = LorvexCalendarEventEntity(
      id: "", title: "", startDate: "", startTime: nil, endTime: nil, allDay: false)
    title = nil
    startDate = nil
    startTime = nil
    endTime = nil
    allDay = nil
    location = nil
    notes = nil
  }

  init(
    event: LorvexCalendarEventEntity,
    title: String? = nil,
    startDate: String? = nil,
    startTime: String? = nil,
    endTime: String? = nil,
    allDay: Bool? = nil,
    location: String? = nil,
    notes: String? = nil
  ) {
    self.event = event
    self.title = title
    self.startDate = startDate
    self.startTime = startTime
    self.endTime = endTime
    self.allDay = allDay
    self.location = location
    self.notes = notes
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    // This is deliberately the non-scoped operation: for a recurring entity,
    // the stable event address updates the whole current series segment. A
    // future occurrence-scoped App Intent must expose occurrence date + scope
    // explicitly rather than substituting the rendered occurrence id here.
    let updated = try await LorvexTaskIntentRunner.updateCalendarEvent(
      id: event.eventID,
      title: title,
      startDate: startDate,
      startTime: startTime,
      endTime: endTime,
      allDay: allDay,
      location: location,
      notes: notes
    )
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.calendar.update.dialog",
          defaultValue: "Updated calendar event \(updated.title) in Lorvex.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
