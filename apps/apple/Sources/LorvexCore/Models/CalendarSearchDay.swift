import Foundation

/// One day of a calendar search's results: the events the search found that
/// start on that day, in the order the agenda lists a day
/// (``Swift/Sequence/sortedForAgenda(on:)``).
public struct CalendarSearchDay: Identifiable, Equatable, Sendable {
  /// The day as `yyyy-MM-dd`.
  public let key: String
  public let events: [CalendarTimelineEvent]

  public var id: String { key }

  public init(key: String, events: [CalendarTimelineEvent]) {
    self.key = key
    self.events = events
  }

  /// The days a search lists for the `events` it found: one day per start
  /// date. Days from today on come first, earliest first, so the next match
  /// leads; days before today follow, most recent first. A repeating event is
  /// one row on its first day.
  ///
  /// - Parameter todayKey: the logical today as `yyyy-MM-dd`.
  public static func days(for events: [CalendarTimelineEvent], todayKey: String) -> [CalendarSearchDay] {
    let eventsByDay = Dictionary(grouping: events, by: \.startDate)
    let keys = eventsByDay.keys.sorted()
    let ordered = keys.filter { $0 >= todayKey } + keys.filter { $0 < todayKey }.reversed()
    return ordered.map { key in
      CalendarSearchDay(key: key, events: (eventsByDay[key] ?? []).sortedForAgenda(on: key))
    }
  }
}
