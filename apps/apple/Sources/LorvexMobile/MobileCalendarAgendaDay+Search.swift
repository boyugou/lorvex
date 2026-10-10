import Foundation
import LorvexCore

extension MobileCalendarAgendaDay {
  /// The days a calendar search lists for the `events` it found, in the order
  /// ``CalendarSearchDay/days(for:todayKey:)`` gives: days from today on
  /// first, then past days, which read as past through the faded rows
  /// (``hasPassed(_:todayKey:nowMinutes:)``).
  ///
  /// - Parameters:
  ///   - todayKey: the logical today as `yyyy-MM-dd`.
  ///   - calendar: gives each day its local start-of-day date.
  static func searchResults(
    _ events: [CalendarTimelineEvent], todayKey: String, calendar: Calendar
  ) -> [MobileCalendarAgendaDay] {
    CalendarSearchDay.days(for: events, todayKey: todayKey).compactMap { day in
      guard
        let date = PlannedDayBridge.displayDate(forLogicalDay: day.key, timeZone: calendar.timeZone)
      else { return nil }
      return MobileCalendarAgendaDay(date: date, key: day.key, events: day.events, tasks: [])
    }
  }
}
