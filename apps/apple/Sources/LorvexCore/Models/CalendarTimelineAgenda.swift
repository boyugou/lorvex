import Foundation

/// Single-day agenda derivation over a multi-day ``CalendarTimelineSnapshot``.
///
/// The timeline snapshot is a multi-day window (the Today refresh loads two
/// weeks so the same data backs the calendar grid). Every "today's schedule"
/// surface needs just one day out of it, ordered as an agenda. This is the one
/// canonical place that filters and orders that day — so no call site
/// re-implements the predicate (and the day-window mismatch that comes with
/// reading the raw 14-day `events` array unfiltered).
extension CalendarTimelineSnapshot {
  /// The events that occur on `day` (a `YYYY-MM-DD` string), ordered as a day
  /// agenda by ``Swift/Sequence/sortedForAgenda(on:)``. Multi-day events appear
  /// on every day they take time on (``CalendarTimelineEvent/occurs(on:)``).
  ///
  /// Named `eventsOccurring` rather than `events(on:)` so the base name does not
  /// collide with the stored `events` property (which would shadow the method at
  /// call sites).
  public func eventsOccurring(on day: String) -> [CalendarTimelineEvent] {
    events.filter { $0.occurs(on: day) }.sortedForAgenda(on: day)
  }
}

extension CalendarTimelineEvent {
  /// True when this event takes time on `day` (`YYYY-MM-DD`): every day from
  /// its `startDate` through its `endDate`, both inclusive, except the end day
  /// of a timed event that ends at exactly midnight on a later day. That event
  /// takes no time on its end day, so 22:00 to 00:00 the next day occurs on
  /// its start day only, as in Apple Calendar. An all-day event's `endDate` is
  /// its last day, so it occurs on that day too. A single-day event occurs
  /// only on its `startDate`. Every surface that places events on days (the
  /// Today schedule, the day, week, and month grids, the agendas) asks this,
  /// so they agree on which days an event belongs to. Relies on `YYYY-MM-DD`
  /// sorting lexicographically the same as chronologically.
  public func occurs(on day: String) -> Bool {
    let end = endDate ?? startDate
    guard startDate <= day, day <= end else { return false }
    let endsAtMidnight = !allDay && CalendarGridModel.parseMinutes(endTime) == 0
    return !(day == end && end != startDate && endsAtMidnight)
  }

  /// The last day this event takes time on (`YYYY-MM-DD`), by the rule of
  /// ``occurs(on:)``: its end date, or its start date when it has none, except
  /// that a timed event ending at exactly midnight on a later day ends the day
  /// before.
  public var lastOccupiedDay: String {
    let end = endDate ?? startDate
    let endsAtMidnight = !allDay && CalendarGridModel.parseMinutes(endTime) == 0
    guard end > startDate, endsAtMidnight else { return end }
    return LorvexDateFormatters.ymdUTCAddingDays(end, days: -1) ?? end
  }

  /// True when this event takes time on more than one day: an all-day event
  /// across several days, or a timed one that runs past midnight. A timed
  /// event that ends at exactly midnight on the next day is a one-day event,
  /// shown and dragged in the calendar grids as one block on its start day.
  public var isMultiDay: Bool { lastOccupiedDay > startDate }

  /// The part of this event that `day` (`YYYY-MM-DD`) holds, for a day the
  /// event occurs on (``occurs(on:)``): the whole event when it takes time on
  /// one day only, and otherwise its first day, its last day
  /// (``lastOccupiedDay``), or a day in between.
  public func dayPart(on day: String) -> CalendarEventDayPart {
    guard isMultiDay else { return .whole }
    if day <= startDate { return .firstDay }
    return day >= lastOccupiedDay ? .lastDay : .middleDay
  }

  /// The minutes this event takes on `day` (`YYYY-MM-DD`), a day it occurs
  /// on, measured on that day's clock. A one-day event runs from its start to
  /// its end, which is nil when it has no end time and 1440 when it ends at
  /// exactly midnight. An event that runs past midnight runs from its start
  /// to 1440 on its first day and from 0 to its end on its last
  /// (``dayPart(on:)``). Nil where the event has no place on the day's clock:
  /// an all-day event, an event without a readable start, a day in between
  /// that the event fills from midnight to midnight, and the last day of an
  /// event without an end time.
  public func clockSpan(on day: String) -> (start: Int, end: Int?)? {
    guard !allDay, let start = lorvexMinutesSinceMidnight(startTime) else { return nil }
    let end = lorvexMinutesSinceMidnight(endTime)
    switch dayPart(on: day) {
    case .whole:
      // A one-day event with a later end date ends at exactly midnight.
      return (start, (endDate ?? startDate) > startDate ? 1440 : end)
    case .firstDay:
      return (start, 1440)
    case .middleDay:
      return nil
    case .lastDay:
      return end.map { (0, $0) }
    }
  }
}

/// The part of an event that one day holds. An event that takes time on one
/// day only, including a timed one that ends at exactly midnight, is whole on
/// that day. An event that takes time on several days starts on its first
/// day, ends on its last, and fills each day in between: a timed event that
/// runs past midnight takes its first day from its start to midnight, each
/// day in between from midnight to midnight, and its last day from midnight
/// to its end.
public enum CalendarEventDayPart: Sendable, Equatable {
  case whole
  case firstDay
  case middleDay
  case lastDay
}

extension Sequence where Element == CalendarTimelineEvent {
  /// Order events for a single-day agenda on `day`: events already underway on
  /// `day` (all-day, or carried over from a start before `day`) lead, since
  /// they frame the whole day; then timed events ascending by start time, ties
  /// broken case-insensitively by title for a stable order. Events with no
  /// start time sort after timed ones.
  public func sortedForAgenda(on day: String) -> [CalendarTimelineEvent] {
    sorted { a, b in
      let aUnderway = a.allDay || a.startDate < day
      let bUnderway = b.allDay || b.startDate < day
      if aUnderway != bUnderway { return aUnderway && !bUnderway }
      let aTime = a.startTime ?? "99:99"
      let bTime = b.startTime ?? "99:99"
      if aTime != bTime { return aTime < bTime }
      return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
    }
  }
}
