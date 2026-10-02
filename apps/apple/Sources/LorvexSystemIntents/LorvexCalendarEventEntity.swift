import AppIntents
import LorvexCore

struct LorvexCalendarEventEntity: AppEntity, Identifiable {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource("system.entity.calendar_event.type", defaultValue: "Lorvex Calendar Event", table: "Localizable", bundle: SystemL10n.bundle))
  static let defaultQuery = LorvexCalendarEventEntityQuery()

  /// Stable canonical event or recurring-segment address. App Entities outlive
  /// an individual timeline render, so this must never use the expanded
  /// occurrence identity from ``CalendarTimelineEvent/id``.
  var id: CalendarTimelineEvent.ID
  var eventID: CalendarTimelineEvent.ID { id }
  var title: String
  var startDate: String
  var startTime: String?
  var endTime: String?
  var allDay: Bool

  /// Raw, process-locale-independent text used only by the entity query's
  /// search matcher. System presentation uses ``localizedScheduleSummary``.
  var scheduleSummary: String {
    if allDay {
      return "\(startDate) all day"
    }
    guard let startTime else {
      return "\(startDate) unscheduled"
    }
    guard let endTime else {
      return "\(startDate) \(startTime)"
    }
    return "\(startDate) \(startTime)-\(endTime)"
  }

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(
      title: "\(title)",
      subtitle: localizedScheduleSummary,
      image: .init(systemName: "calendar")
    )
  }

  init(
    id: CalendarTimelineEvent.ID,
    title: String,
    startDate: String,
    startTime: String?,
    endTime: String?,
    allDay: Bool
  ) {
    self.id = id
    self.title = title
    self.startDate = startDate
    self.startTime = startTime
    self.endTime = endTime
    self.allDay = allDay
  }

  init(event: CalendarTimelineEvent) {
    self.init(
      id: event.eventID,
      title: event.title,
      startDate: event.startDate,
      startTime: event.startTime,
      endTime: event.endTime,
      allDay: event.allDay
    )
  }

  /// The schedule as the system shows it under the event's title, in the
  /// user's locale: the day in the medium date style ("Oct 1, 2026") and the
  /// times on the user's clock ("9:00 AM", or "09:00" on a 24-hour clock).
  private var localizedScheduleSummary: LocalizedStringResource {
    let day = displayDay
    if allDay {
      return LocalizedStringResource(
        "system.entity.calendar_event.schedule.all_day",
        defaultValue: "\(day) all day",
        table: "Localizable",
        bundle: SystemL10n.bundle)
    }
    guard let startTime else {
      return LocalizedStringResource(
        "system.entity.calendar_event.schedule.unscheduled",
        defaultValue: "\(day) unscheduled",
        table: "Localizable",
        bundle: SystemL10n.bundle)
    }
    let start = lorvexClockTimeLabel(startTime)
    // An end of 24:00 is the midnight that closes the day.
    guard let endTime, let endMinutes = lorvexEndMinutesSinceMidnight(endTime) else {
      return LocalizedStringResource(
        "system.entity.calendar_event.schedule.start",
        defaultValue: "\(day) \(start)",
        table: "Localizable",
        bundle: SystemL10n.bundle)
    }
    let end = lorvexClockTimeLabel(minutes: endMinutes)
    return LocalizedStringResource(
      "system.entity.calendar_event.schedule.range",
      defaultValue: "\(day) \(start)-\(end)",
      table: "Localizable",
      bundle: SystemL10n.bundle)
  }

  /// The event's `yyyy-MM-dd` day in the locale's medium date style, or the
  /// stored day when it does not parse. A day key names a calendar day, not
  /// an instant, so it is read and written in UTC.
  private var displayDay: String {
    guard let date = LorvexDateFormatters.ymdUTC.date(from: startDate) else { return startDate }
    return LorvexDateFormatters.string(date, dateStyle: .medium, timeZone: .gmt)
  }
}
