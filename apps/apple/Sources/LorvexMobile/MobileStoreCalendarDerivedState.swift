import Foundation
import LorvexCore

extension MobileStore {
  /// The logical today as the start of that day in `calendar`'s time zone:
  /// the day every calendar mode marks and returns to with Today. It follows
  /// the product day, so after midnight and before the day boundary it is
  /// still the day before.
  func calendarToday(in calendar: Calendar) -> Date {
    PlannedDayBridge.displayDate(forLogicalDay: logicalTodayString, timeZone: calendar.timeZone)
      ?? calendar.startOfDay(for: now())
  }

  /// The day the next calendar mode to appear opens on
  /// (``calendarPendingDayKey``), as the start of that day in `calendar`'s
  /// time zone; `nil` when no mode switch is pending.
  func calendarPendingDay(in calendar: Calendar) -> Date? {
    calendarPendingDayKey.flatMap {
      PlannedDayBridge.displayDate(forLogicalDay: $0, timeZone: calendar.timeZone)
    }
  }

  /// The loaded calendar events matching the calendar search `query` in
  /// title, location, or notes, with the shared term-AND semantics, as the
  /// macOS calendar filter narrows the same event array. Tasks are not
  /// searched: the field is an event search. An empty or blank query returns
  /// every loaded event.
  func calendarEvents(matching query: String) -> [CalendarTimelineEvent] {
    let events = calendarTimeline?.events ?? []
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return events }
    return events.filter { event in
      LorvexCatalogSearch.matches(query, fields: [event.title, event.location, event.notes])
    }
  }
}
