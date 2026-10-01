import LorvexCore
import SwiftUI

/// One day of the agenda: its local start-of-day `date`, the same day as the
/// `yyyy-MM-dd` `key` its events and tasks were grouped under, and those events
/// and tasks.
struct MobileCalendarAgendaDay: Identifiable, Equatable {
  let date: Date
  let key: String
  let events: [CalendarTimelineEvent]
  let tasks: [LorvexTask]

  var id: Date { date }

  var isEmpty: Bool { events.isEmpty && tasks.isEmpty }

  /// One row of a day: an event or a task.
  enum Entry: Identifiable, Equatable {
    case event(CalendarTimelineEvent)
    case task(LorvexTask)

    var id: String {
      switch self {
      case .event(let event): "event:\(event.id)"
      case .task(let task): "task:\(task.id)"
      }
    }
  }

  /// The day's rows in reading order: all-day events, then the timed events
  /// and the tasks with a time that day by start, then the tasks without one.
  /// An event that began on an earlier day starts this day at midnight. Rows
  /// that start together keep their arrival order, events ahead of tasks, the
  /// way Today's schedule reads; `events` and `tasks` arrive in their own
  /// display order, which each kind keeps.
  var entries: [Entry] {
    var allDay: [Entry] = []
    var timed: [(start: Int, entry: Entry)] = []
    var untimed: [Entry] = []
    for event in events {
      if event.allDay || event.startTime == nil {
        allDay.append(.event(event))
      } else {
        let start = event.startDate == key ? lorvexMinutesSinceMidnight(event.startTime) ?? 0 : 0
        timed.append((start, .event(event)))
      }
    }
    for task in tasks {
      if let time = task.time(on: key) {
        timed.append((time.lowerBound, .task(task)))
      } else {
        untimed.append(.task(task))
      }
    }
    let ordered = timed.enumerated()
      .sorted { lhs, rhs in
        lhs.element.start != rhs.element.start
          ? lhs.element.start < rhs.element.start : lhs.offset < rhs.offset
      }
      .map(\.element.entry)
    return allDay + ordered + untimed
  }

  /// Whether the clock has passed `event` on this day: every event of a day
  /// before today, and on today a timed event that has ended by `nowMinutes`.
  /// An event that runs on past today, or has no end time, has not passed.
  ///
  /// - Parameters:
  ///   - todayKey: the logical today as `yyyy-MM-dd`.
  ///   - nowMinutes: the current time in minutes since midnight, or `nil`
  ///     when it is unknown.
  func hasPassed(_ event: CalendarTimelineEvent, todayKey: String, nowMinutes: Int?) -> Bool {
    if key < todayKey { return true }
    guard key == todayKey, let nowMinutes, !event.allDay else { return false }
    if let endDate = event.endDate, endDate > key { return false }
    guard let end = lorvexMinutesSinceMidnight(event.endTime) else { return false }
    return end <= nowMinutes
  }

  /// The days an agenda lists out of `days`, in their order.
  ///
  /// A day with nothing on it is left out: the day grid beside the agenda
  /// already shows that day free, and a day header
  /// with nothing under it reads as content that failed to load. Today is the
  /// exception and always keeps its section, so a free today says so instead
  /// of disappearing.
  ///
  /// - Parameter todayKey: the logical today as `yyyy-MM-dd`.
  static func listed(_ days: [MobileCalendarAgendaDay], todayKey: String) -> [MobileCalendarAgendaDay] {
    days.filter { day in day.key == todayKey || !day.isEmpty }
  }
}
