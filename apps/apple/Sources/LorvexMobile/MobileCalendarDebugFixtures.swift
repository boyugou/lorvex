#if DEBUG
import Foundation
import LorvexCore

extension MobileCalendarDebugState {
  static func optionalEndExample(hasEndTime: Bool = false) -> CalendarTimelineEvent? {
    guard let start = ISO8601DateFormatter().date(from: "2026-11-23T15:00:00Z") else { return nil }
    return CalendarTimelineEvent(
      id: "debug-optional-end", title: "Check in with the team", source: "canonical",
      editable: true, startDate: "2026-11-23", startTime: "10:00", endDate: nil,
      endTime: hasEndTime ? "11:00" : nil, allDay: false, location: "Studio", color: nil, eventType: "event",
      timezone: "America/New_York", isRecurring: false,
      projection: CalendarEventProjection(
        timezone: "America/New_York", start: start, end: hasEndTime ? start.addingTimeInterval(3_600) : nil))
  }

  /// A valid half-hour whose New York end clock is earlier after fall-back.
  /// Visual-only, as with the recurrence fixtures below.
  static func clockFoldExample(editable: Bool) -> CalendarTimelineEvent? {
    guard let start = ISO8601DateFormatter().date(from: "2026-11-01T05:45:00Z"),
      let end = ISO8601DateFormatter().date(from: "2026-11-01T06:15:00Z")
    else { return nil }
    return CalendarTimelineEvent(
      id: "debug-clock-fold", title: "Clock change", source: editable ? "canonical" : "provider",
      editable: editable, startDate: "2026-11-01", startTime: "01:45", endDate: nil,
      endTime: "01:15", allDay: false, location: "Studio", color: nil, eventType: "event",
      timezone: "UTC", isRecurring: false,
      projection: CalendarEventProjection(timezone: "America/New_York", start: start, end: end))
  }

  /// A visual-only example for the event-detail timezone screenshot routes:
  /// Monday night in New York is Tuesday afternoon in Tokyo. Like the mirrored
  /// detail fixture, it is never written to the user's calendar.
  static func recurrenceZoneExample(editable: Bool, advanced: Bool = false) -> CalendarTimelineEvent? {
    guard let sourceZone = TimeZone(identifier: "America/New_York"),
      let displayZone = TimeZone(identifier: "Asia/Tokyo")
    else { return nil }
    let sourceCalendar = LorvexDateFormatters.gregorianCalendar(timeZone: sourceZone)
    let components = advanced
      ? DateComponents(year: 2026, month: 4, day: 30, hour: 23, minute: 30)
      : DateComponents(year: 2026, month: 11, day: 23, hour: 23, minute: 30)
    guard let start = sourceCalendar.date(from: components)
    else { return nil }
    let displayed = CalendarEventTiming.timed(
      startingAt: start, minutes: 15,
      calendar: LorvexDateFormatters.gregorianCalendar(timeZone: displayZone))
    return CalendarTimelineEvent(
      id: "debug-recurrence-zone", title: advanced ? "Month-end review" : "New York Monday meeting",
      source: editable ? "canonical" : "provider", editable: editable,
      startDate: displayed.startDate, startTime: displayed.startTime,
      endDate: displayed.endDate, endTime: displayed.endTime,
      allDay: false, location: "Studio", color: nil, eventType: "event",
      timezone: sourceZone.identifier, isRecurring: true,
      recurrenceRule: (advanced
        ? TaskRecurrenceRule(
          freq: .monthly, byDay: ["MO", "TU", "WE", "TH", "FR"],
          byMonthDay: [-2, -1], bySetPos: [-1], wkst: "SU", count: 12)
        : TaskRecurrenceRule(freq: .weekly)).canonicalRecurrenceJSON(),
      projection: CalendarEventProjection(
        timezone: displayZone.identifier, start: displayed.start, end: displayed.end))
  }
}
#endif
