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

  /// The day's rows in reading order: all-day events and the days that longer
  /// events fill, then the timed events and the tasks with a time that day by
  /// start, then the tasks without one. An event that began on an earlier day
  /// starts this day at midnight (``CalendarTimelineEvent/clockSpan(on:)``). Rows
  /// that start together keep their arrival order, events ahead of tasks, the
  /// way Today's schedule reads; `events` and `tasks` arrive in their own
  /// display order, which each kind keeps.
  var entries: [Entry] {
    var allDay: [Entry] = []
    var timed: [(start: Int, entry: Entry)] = []
    var untimed: [Entry] = []
    for event in events {
      if let span = event.clockSpan(on: key) {
        timed.append((span.start, .event(event)))
      } else {
        allDay.append(.event(event))
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
  /// before today, and on today a timed event whose time on the day
  /// (``CalendarTimelineEvent/clockSpan(on:)``) has ended by `nowMinutes`. An
  /// event that runs on past today, fills the day, or has no end time has not
  /// passed.
  ///
  /// - Parameters:
  ///   - todayKey: the logical today as `yyyy-MM-dd`.
  ///   - nowMinutes: the current time in minutes since midnight, or `nil`
  ///     when it is unknown.
  func hasPassed(_ event: CalendarTimelineEvent, todayKey: String, nowMinutes: Int?) -> Bool {
    if key < todayKey { return true }
    guard key == todayKey, let nowMinutes, let end = event.clockSpan(on: key)?.end else {
      return false
    }
    return end <= nowMinutes
  }

  /// The days an agenda lists out of `days`, in their order.
  ///
  /// A day with nothing on it is left out: the day grid beside the agenda
  /// already shows that day free, and a day header
  /// with nothing under it reads as content that failed to load. Today is the
  /// exception and always keeps its section, so a free today says so instead
  /// of disappearing, and so does `pinnedDayKey`, the day a month grid has
  /// chosen, whose section is the whole agenda.
  ///
  /// - Parameters:
  ///   - todayKey: the logical today as `yyyy-MM-dd`.
  ///   - pinnedDayKey: a day as `yyyy-MM-dd` kept like today, or nil.
  static func listed(
    _ days: [MobileCalendarAgendaDay], todayKey: String, pinnedDayKey: String? = nil
  ) -> [MobileCalendarAgendaDay] {
    days.filter { day in day.key == todayKey || day.key == pinnedDayKey || !day.isEmpty }
  }

  /// The agenda days for `dates`, in their order, from a loaded window's
  /// `events` and scheduled `tasks`.
  ///
  /// A day's events are the ones ``agendaEvents(from:on:)`` places on it. Its
  /// tasks are the ones whose calendar day
  /// (``CalendarGridModel/scheduledTaskDayKey(_:)``) it is, leaving out a
  /// cancelled task as the calendar grids do; a task with a time that day
  /// comes first, by time, then the rest by priority, then title.
  ///
  /// - Parameter keyFor: the `yyyy-MM-dd` key of a local date.
  static func days(
    for dates: [Date], events: [CalendarTimelineEvent], tasks: [LorvexTask],
    keyFor: (Date) -> String
  ) -> [MobileCalendarAgendaDay] {
    dates.map { date in
      let key = keyFor(date)
      let dayTasks = tasks
        .filter { task in
          task.status != .cancelled && CalendarGridModel.scheduledTaskDayKey(task) == key
        }
        .sorted { lhs, rhs in
          let lhsStart = lhs.time(on: key)?.lowerBound ?? Int.max
          let rhsStart = rhs.time(on: key)?.lowerBound ?? Int.max
          if lhsStart != rhsStart { return lhsStart < rhsStart }
          if lhs.priority != rhs.priority { return lhs.priority.rawValue < rhs.priority.rawValue }
          return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
      return MobileCalendarAgendaDay(
        date: date, key: key, events: agendaEvents(from: events, on: key), tasks: dayTasks)
    }
  }

  /// Events that belong on the agenda for `key` (`yyyy-MM-dd`), ordered for
  /// display. The day filter is ``CalendarTimelineEvent/occurs(on:)``, the
  /// test the calendar grids use too, so they never disagree about which day
  /// an event belongs to: a multi-day event appears on every day it takes
  /// time on, which leaves out the end day of a timed event ending at exactly
  /// midnight. Ordering puts events without a start time (all-day) first, then
  /// start-time ascending, then title.
  static func agendaEvents(
    from events: [CalendarTimelineEvent],
    on key: String
  ) -> [CalendarTimelineEvent] {
    events
      .filter { $0.occurs(on: key) }
      .sorted { lhs, rhs in
        switch (lhs.startTime, rhs.startTime) {
        case (let left?, let right?) where left != right:
          left < right
        case (nil, _?):
          true
        case (_?, nil):
          false
        default:
          lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
      }
  }
}
