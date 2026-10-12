import LorvexCore

/// The words of a calendar event's detail and of its shared text, from this
/// module's catalog, so the sheet and the share sheet name a field the same
/// way.
enum MobileCalendarEventCopy {
  static var when: String {
    String(
      localized: "task_detail.add.when", defaultValue: "When", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  static var location: String {
    String(
      localized: "calendar.field.location", defaultValue: "Location", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  static var repeats: String {
    String(
      localized: "recurrence.repeats", defaultValue: "Repeats", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  static var attendees: String {
    String(
      localized: "calendar.event.field.attendees", defaultValue: "Attendees",
      table: "Localizable", bundle: MobileL10n.bundle)
  }

  static var url: String {
    String(
      localized: "calendar.event.field.url", defaultValue: "URL", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  static var notes: String {
    String(
      localized: "calendar.field.notes", defaultValue: "Notes", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  static var calendar: String {
    String(
      localized: "calendar.event.field.calendar", defaultValue: "Calendar", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  /// The calendar a mirrored event lives in, which the device's calendars do
  /// not name per event here.
  static var systemCalendar: String {
    String(
      localized: "calendar.event.source.system", defaultValue: "System Calendar",
      table: "Localizable", bundle: MobileL10n.bundle)
  }

  static var openInCalendar: String {
    String(
      localized: "calendar.event.open_in_calendar", defaultValue: "Open in Calendar",
      table: "Localizable", bundle: MobileL10n.bundle)
  }

  static var allDay: String {
    String(
      localized: "calendar.all_day_short", defaultValue: "All day", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  static var repeatingEvent: String {
    String(
      localized: "calendar.repeating_event.a11y", defaultValue: "Repeating event",
      table: "Localizable", bundle: MobileL10n.bundle)
  }

  static func label(_ field: LorvexEventShareField) -> String {
    switch field {
    case .when: when
    case .location: location
    case .repeats: repeats
    case .attendees: attendees
    case .url: url
    }
  }
}
