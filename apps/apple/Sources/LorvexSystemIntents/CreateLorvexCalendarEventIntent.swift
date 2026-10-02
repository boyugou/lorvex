import AppIntents
import LorvexCore

struct CreateLorvexCalendarEventIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.calendar.create.title", defaultValue: "Create Lorvex Calendar Event", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.calendar.create.description", defaultValue: "Create a Lorvex calendar event from Shortcuts or Siri.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.title", defaultValue: "Title", table: "Localizable", bundle: SystemL10n.bundle))
  var title: String

  @Parameter(
    title: LocalizedStringResource("system.calendar.parameter.start_date", defaultValue: "Start Date", table: "Localizable", bundle: SystemL10n.bundle),
    description: LocalizedStringResource("system.parameter.date.today_when_blank.description", defaultValue: "Leave blank for today.", table: "Localizable", bundle: SystemL10n.bundle),
    kind: .date)
  var startDate: Date?

  @Parameter(
    title: LocalizedStringResource("system.calendar.parameter.start_time", defaultValue: "Start Time", table: "Localizable", bundle: SystemL10n.bundle),
    kind: .time)
  var startTime: Date?

  @Parameter(
    title: LocalizedStringResource("system.calendar.parameter.end_time", defaultValue: "End Time", table: "Localizable", bundle: SystemL10n.bundle),
    kind: .time)
  var endTime: Date?

  @Parameter(
    title: LocalizedStringResource("system.calendar.parameter.all_day", defaultValue: "All Day", table: "Localizable", bundle: SystemL10n.bundle))
  var allDay: Bool

  @Parameter(
    title: LocalizedStringResource("system.calendar.parameter.location", defaultValue: "Location", table: "Localizable", bundle: SystemL10n.bundle))
  var location: String?

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.notes", defaultValue: "Notes", table: "Localizable", bundle: SystemL10n.bundle))
  var notes: String?

  init() {
    title = ""
    startDate = nil
    startTime = nil
    endTime = nil
    allDay = true
    location = nil
    notes = nil
  }

  init(
    title: String,
    startDate: Date? = nil,
    startTime: Date? = nil,
    endTime: Date? = nil,
    allDay: Bool = true,
    location: String? = nil,
    notes: String? = nil
  ) {
    self.title = title
    self.startDate = startDate
    self.startTime = startTime
    self.endTime = endTime
    self.allDay = allDay
    self.location = location
    self.notes = notes
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let title = try $title.requiredText()
    // A start time makes the event timed; one that is not all-day needs it.
    if !allDay, startTime == nil { throw $startTime.needsValueError() }
    let event = try await LorvexTaskIntentRunner.createCalendarEvent(
      title: title,
      startDate: startDate.map(IntentDateText.day),
      startTime: startTime.map(IntentDateText.time),
      endTime: endTime.map(IntentDateText.time),
      allDay: allDay,
      location: location,
      notes: notes
    )
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.calendar.create.dialog",
          defaultValue: "Created calendar event \(event.title) for \(lorvexDayLine(logicalDay: event.startDate)).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
