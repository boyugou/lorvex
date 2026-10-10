import Foundation
import LorvexCore

extension MobileCalendarAgendaDay {
  /// The days a calendar search lists for the `events` it found: one day per
  /// start date holding that date's events, ordered as the agenda orders a
  /// day (``isListedBefore(_:_:)``). Days from today on come first, earliest
  /// first, so the next match leads; days before today follow, most recent
  /// first, and read as past through the faded rows
  /// (``hasPassed(_:todayKey:nowMinutes:)``). A repeating event is one row on
  /// its first day.
  ///
  /// - Parameters:
  ///   - todayKey: the logical today as `yyyy-MM-dd`.
  ///   - calendar: gives each day its local start-of-day date.
  static func searchResults(
    _ events: [CalendarTimelineEvent], todayKey: String, calendar: Calendar
  ) -> [MobileCalendarAgendaDay] {
    let eventsByDay = Dictionary(grouping: events, by: \.startDate)
    let keys = eventsByDay.keys.sorted()
    let ordered = keys.filter { $0 >= todayKey } + keys.filter { $0 < todayKey }.reversed()
    return ordered.compactMap { key in
      guard
        let date = PlannedDayBridge.displayDate(forLogicalDay: key, timeZone: calendar.timeZone)
      else { return nil }
      return MobileCalendarAgendaDay(
        date: date, key: key, events: (eventsByDay[key] ?? []).sorted(by: isListedBefore),
        tasks: [])
    }
  }
}
