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
  /// Minutes since midnight, or nil for an all-day event, which has no clock
  /// position.
  public var startMinutes: Int?
  public var endMinutes: Int?
  /// The leading time label; empty for an all-day event.
  public var timeLabel: String
  /// True once the clock has passed this row's end and the row asks nothing
  /// more of the day: a finished meeting, or a finished (or cancelled) task. A
  /// task whose time passed unfinished still needs its work and keeps reading
  /// as actionable, and all-day events are never past.
  public var isPast: Bool

  public init(
    id: String,
    kind: Kind,
    startMinutes: Int? = nil,
    endMinutes: Int? = nil,
    timeLabel: String = "",
    isPast: Bool = false
  ) {
    self.id = id
    self.kind = kind
    self.startMinutes = startMinutes
    self.endMinutes = endMinutes
    self.timeLabel = timeLabel
    self.isPast = isPast
  }
}

/// Builds a day on the clock. Pure and synchronous, so every surface that
/// draws the schedule applies the same ordering.
public enum LorvexTodayTimeline {
  /// Merge `events` and the timed `tasks` into one reading order:
  ///
  /// 1. all-day events, which frame the whole day rather than sitting at a
  ///    time;
  /// 2. timed events and timed tasks, ascending by start, with a
  ///    ``LorvexTodayTimelineItem/Kind/now`` row at the clock's position.
  ///
  /// A task appears only when `times` holds its time on this day; tasks without
  /// one are left out, since the schedule is drawn beside a list that already
  /// shows every task. Rows that share a start keep their arrival order:
  /// events first, then tasks in the order given.
  ///
  /// `nowMinutes` is minutes since midnight in the product's clock, or nil to
  /// omit the now row (a day that is not today has no "now").
  public static func build(
    events: [CalendarTimelineEvent],
    tasks: [LorvexTask],
    times: [LorvexTask.ID: Range<Int>],
    nowMinutes: Int?
  ) -> [LorvexTodayTimelineItem] {
    var timed: [LorvexTodayTimelineItem] = []
    var allDay: [LorvexTodayTimelineItem] = []

    for event in events {
      let start = lorvexMinutesSinceMidnight(event.startTime)
      let end = lorvexMinutesSinceMidnight(event.endTime)
      let item = LorvexTodayTimelineItem(
        id: "event:\(event.id)",
        kind: .event(event),
        startMinutes: event.allDay ? nil : start,
        endMinutes: event.allDay ? nil : end,
        timeLabel: event.allDay ? "" : (event.startTime.map(lorvexClockTimeLabel) ?? ""),
        isPast: Self.isPast(start: start, end: end, nowMinutes: nowMinutes, allDay: event.allDay)
      )
      if event.allDay || start == nil {
        allDay.append(item)
      } else {
        timed.append(item)
      }
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

  /// An event is past once the clock has cleared its end, falling back to its
  /// start when it has no end, so a zero-length event still ages out. All-day
  /// events never read as past: they belong to the whole day, including the
  /// part still ahead.
  private static func isPast(
    start: Int?, end: Int?, nowMinutes: Int?, allDay: Bool
  ) -> Bool {
    guard !allDay, let nowMinutes, let boundary = end ?? start else { return false }
    return boundary <= nowMinutes
  }
}
