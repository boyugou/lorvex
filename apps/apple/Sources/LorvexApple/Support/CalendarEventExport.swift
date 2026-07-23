import Foundation
import LorvexCore
import LorvexDomain

struct CalendarEventExport: Equatable, Sendable {
  var title: String
  var startDate: Date
  var endDate: Date
  var isAllDay: Bool
  var location: String?
  var notes: String?
  var recurrence: String?

  init?(event: CalendarTimelineEvent, notes: String?, calendar: Calendar = .current) {
    guard
      let startDate = Self.date(from: event.startDate, time: event.startTime, calendar: calendar)
    else { return nil }

    let resolvedEndDate: Date
    if event.allDay {
      // Lorvex stores an inclusive all-day span while EventKit expects an
      // exclusive end instant. Preserve an explicit multi-day end by advancing
      // the final Lorvex day once; a nil end remains a one-day event.
      let inclusiveEnd =
        event.endDate.flatMap { Self.date(from: $0, time: nil, calendar: calendar) }
        ?? startDate
      resolvedEndDate = AllDayEventSpan.exclusiveEnd(
        start: startDate, inclusiveEnd: inclusiveEnd, calendar: calendar)
    } else if let endDate = event.endDate,
      let parsedEnd = Self.date(from: endDate, time: event.endTime, calendar: calendar)
    {
      resolvedEndDate = parsedEnd
    } else if let parsedEnd = Self.date(
      from: event.startDate,
      time: event.endTime,
      calendar: calendar
    ) {
      // No `endDate`: the end time is anchored to the start day. If it lands at
      // or before the start, the event crosses midnight (e.g. 22:00 → 00:00), so
      // roll the end into the next day rather than letting the 5-minute floor
      // below collapse it into a sub-minute event.
      resolvedEndDate =
        parsedEnd > startDate
        ? parsedEnd
        : (calendar.date(byAdding: .day, value: 1, to: parsedEnd) ?? parsedEnd)
    } else {
      resolvedEndDate = startDate.addingTimeInterval(30 * 60)
    }

    self.title = event.title
    self.startDate = startDate
    self.endDate = max(resolvedEndDate, startDate.addingTimeInterval(5 * 60))
    self.isAllDay = event.allDay
    self.location = event.location.trimmedNilIfEmpty
    self.notes = notes.trimmedNilIfEmpty
    self.recurrence = event.recurrenceRule
  }

  private static func date(from ymd: String, time: String?, calendar: Calendar) -> Date? {
    let parts = ymd.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    let timeParts = (time ?? "00:00").split(separator: ":").compactMap { Int($0) }
    guard timeParts.count >= 2 else { return nil }

    var components = DateComponents()
    components.calendar = calendar
    components.timeZone = calendar.timeZone
    components.year = parts[0]
    components.month = parts[1]
    components.day = parts[2]
    components.hour = timeParts[0]
    components.minute = timeParts[1]
    return components.date
  }
}
