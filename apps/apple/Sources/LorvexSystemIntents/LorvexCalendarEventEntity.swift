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

  private var localizedScheduleSummary: LocalizedStringResource {
    if allDay {
      return LocalizedStringResource(
        "system.entity.calendar_event.schedule.all_day",
        defaultValue: "\(startDate) all day",
        table: "Localizable",
        bundle: SystemL10n.bundle)
    }
    guard let startTime else {
      return LocalizedStringResource(
        "system.entity.calendar_event.schedule.unscheduled",
        defaultValue: "\(startDate) unscheduled",
        table: "Localizable",
        bundle: SystemL10n.bundle)
    }
    guard let endTime else {
      return LocalizedStringResource(
        "system.entity.calendar_event.schedule.start",
        defaultValue: "\(startDate) \(startTime)",
        table: "Localizable",
        bundle: SystemL10n.bundle)
    }
    return LocalizedStringResource(
      "system.entity.calendar_event.schedule.range",
      defaultValue: "\(startDate) \(startTime)-\(endTime)",
      table: "Localizable",
      bundle: SystemL10n.bundle)
  }
}
