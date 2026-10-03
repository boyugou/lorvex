import Foundation

/// One row of a day on the clock: a calendar event, a task with a time that
/// day, or the clock itself.
///
/// The schedule beside Today (the macOS and iPad pane, the iPhone sheet and
/// strip) reads these rows in order, so meetings and timed work interleave the
/// way the day will run instead of the reader merging two lists by eye.
public struct LorvexTodayTimelineItem: Identifiable, Equatable, Sendable {
  public enum Kind: Equatable, Sendable {
    /// A calendar event. Never completable: an event is not the user's to check
    /// off, and offering a checkbox would imply it is.
    case event(CalendarTimelineEvent)
    /// A task with a time on this day, resolved to the real task so the row
    /// carries the same checkbox, chips, and actions it has everywhere else. A
    /// finished task keeps its place and reads as done, so finishing early does
    /// not reshuffle the day.
    case task(LorvexTask)
    /// Where the clock sits among the timed rows.
    case now
  }

  public var id: String
  public var kind: Kind
  /// Minutes since midnight on this day, or nil for a row without a clock
  /// position: an all-day event, or a day that a longer event fills. An event
  /// that runs past midnight holds only its share of the day, so its first
  /// day ends at 1440 and its last day starts at 0.
  public var startMinutes: Int?
  public var endMinutes: Int?
  /// The leading time label: a start ("9:00 AM"), or "Until 1:30 AM" on the
  /// last day of an event that started on an earlier day; empty for a row
  /// without a clock position.
  public var timeLabel: String
  /// True once the clock has passed this row's end and the row asks nothing
  /// more of the day: a finished meeting, or a finished (or cancelled) task. A
  /// task whose time passed unfinished still needs its work and keeps reading
  /// as actionable, and rows without a clock position are never past.
  public var isPast: Bool
  /// For an event row, the part of the event this day holds
  /// (``CalendarTimelineEvent/dayPart(on:)``): the whole event, or the first,
  /// a middle, or the last day of one that takes time on several days. Nil
  /// for a task row and the now row.
  public var eventPart: CalendarEventDayPart?

  public init(
    id: String,
    kind: Kind,
    startMinutes: Int? = nil,
    endMinutes: Int? = nil,
    timeLabel: String = "",
    isPast: Bool = false,
    eventPart: CalendarEventDayPart? = nil
  ) {
    self.id = id
    self.kind = kind
    self.startMinutes = startMinutes
    self.endMinutes = endMinutes
    self.timeLabel = timeLabel
    self.isPast = isPast
    self.eventPart = eventPart
  }
}

/// Builds a day on the clock. Pure and synchronous, so every surface that
/// draws the schedule applies the same ordering.
public enum LorvexTodayTimeline {
  /// Merge `events`, the events that occur on `day` (`yyyy-MM-dd`), and the
  /// timed `tasks` into one reading order:
  ///
  /// 1. all-day events, and the days in between of timed events that fill
  ///    them, which frame the whole day rather than sitting at a time;
  /// 2. timed events and timed tasks, ascending by start, with a
  ///    ``LorvexTodayTimelineItem/Kind/now`` row at the clock's position.
  ///
  /// A timed event that runs past midnight takes only its share of `day`
  /// (``CalendarTimelineEvent/clockSpan(on:)``): on its first day it runs from
  /// its start to midnight and shows its start, so it never reads as past that
  /// day; on its last day it runs from midnight to its end, opens the timed
  /// rows, and shows "Until" its end (``CalendarTimelineEvent/timeLabel(for:)``).
  /// One that ends at exactly midnight runs to the end of its day. An event
  /// row is past once the clock clears its end on `day`, or its start when it
  /// has no end time, so a zero-length event still ages out.
  ///
  /// A task appears only when `times` holds its time on this day; tasks without
  /// one are left out, since the schedule is drawn beside a list that already
  /// shows every task. Rows that share a start keep their arrival order:
  /// events first, then tasks in the order given.
  ///
  /// `nowMinutes` is minutes since midnight in the product's clock, or nil to
  /// omit the now row (a day that is not today has no "now").
  public static func build(
    day: String,
    events: [CalendarTimelineEvent],
    tasks: [LorvexTask],
    times: [LorvexTask.ID: Range<Int>],
    nowMinutes: Int?
  ) -> [LorvexTodayTimelineItem] {
    var timed: [LorvexTodayTimelineItem] = []
    var allDay: [LorvexTodayTimelineItem] = []

    for event in events {
      let part = event.dayPart(on: day)
      guard let span = event.clockSpan(on: day) else {
        allDay.append(
          LorvexTodayTimelineItem(id: "event:\(event.id)", kind: .event(event), eventPart: part))
        continue
      }
      timed.append(
        LorvexTodayTimelineItem(
          id: "event:\(event.id)",
          kind: .event(event),
          startMinutes: span.start,
          endMinutes: span.end,
          timeLabel: event.timeLabel(for: part) ?? "",
          isPast: nowMinutes.map { (span.end ?? span.start) <= $0 } == true,
          eventPart: part))
    }

    for task in tasks {
      guard let time = times[task.id] else { continue }
      timed.append(
        LorvexTodayTimelineItem(
          id: "task:\(task.id)",
          kind: .task(task),
          startMinutes: time.lowerBound,
          endMinutes: time.upperBound,
          timeLabel: lorvexClockTimeLabel(minutes: time.lowerBound),
          isPast: task.status.isResolved && nowMinutes.map { time.upperBound <= $0 } == true))
    }

    // Break ties on arrival index: `sort` does not promise stability, and the
    // contract is that rows sharing a start keep the order they arrived in.
    timed = timed.enumerated()
      .sorted { lhs, rhs in
        let (left, right) = (lhs.element.startMinutes ?? 0, rhs.element.startMinutes ?? 0)
        return left != right ? left < right : lhs.offset < rhs.offset
      }
      .map(\.element)

    if let nowMinutes, !timed.isEmpty {
      let insertAt = timed.firstIndex { ($0.startMinutes ?? 0) > nowMinutes } ?? timed.count
      timed.insert(
        LorvexTodayTimelineItem(id: "now", kind: .now, startMinutes: nowMinutes),
        at: insertAt)
    }

    return allDay + timed
  }

  /// The rows a schedule folds behind its "N earlier" line: the past rows that
  /// open the day's timed rows, up to the first timed row that is not past (at
  /// the latest the clock's own row). All-day rows sit above the fold and never
  /// join it, and a past row after that point stays in place, quieted, so the
  /// folded rows are exactly the ones above everything still shown and reading
  /// down keeps the day's order. Empty when there is nothing to fold; its
  /// lower bound is where the fold's line goes.
  public static func earlierFold(_ items: [LorvexTodayTimelineItem]) -> Range<Int> {
    guard let start = items.firstIndex(where: { $0.startMinutes != nil }) else {
      return items.endIndex..<items.endIndex
    }
    let end = items[start...].firstIndex { !$0.isPast } ?? items.endIndex
    return start..<end
  }
}
