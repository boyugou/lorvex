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
