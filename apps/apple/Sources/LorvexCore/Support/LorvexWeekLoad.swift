import Foundation

/// How full each day of a week is, measured against the working hours.
///
/// A day's load is its meetings (timed events, clipped to the working window
/// and with overlaps merged) plus the work its open tasks ask for: a task with
/// a time that day counts the time's length, any other task its estimate
/// (``LorvexCalmToday/Item``, so Today's overbooked decision measures today the
/// same way). For the strip, that work is packed into the free gaps between
/// meetings from the start of the working window; whatever does not fit
/// continues past the window's end as overrun. On today the window that counts
/// starts at the current time, so time already gone is neither free nor packed.
/// Every day shares one ``range`` so seven strips read on one scale.
public struct LorvexWeekLoad: Equatable, Sendable {
  public struct Day: Identifiable, Equatable, Sendable {
    public var id: String { key }
    /// The day as `yyyy-MM-dd`.
    public let key: String
    public let isToday: Bool
    /// Whether the day comes before today in a week that holds today. Such a
    /// day is over, and the week surfaces fade its marks (its load strip) and
    /// quiet its day number while keeping its words legible, the way Today
    /// treats the schedule rows the clock has cleared. A week without today
    /// has no past days to set apart: it is all history or all ahead, and was
    /// opened on purpose.
    public let isPast: Bool
    /// Meeting blocks and packed task blocks, in minutes since midnight.
    public let segments: [Block]
    public let meetingMinutes: Int
    public let taskCount: Int
    public let taskMinutes: Int
    /// Minutes the day's load exceeds the working window; zero when it fits
    /// or runs over by less than ``overbookedTolerance``, since estimates are
    /// rough and a few minutes over is not a problem worth a headline.
    public let overMinutes: Int
    /// Working minutes left after meetings and task estimates.
    public let freeMinutes: Int

    public var isEmpty: Bool { meetingMinutes == 0 && taskCount == 0 }
  }

  public struct Block: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case meeting, task, overrun }
    public let kind: Kind
    public let start: Int
    public let end: Int
  }

  /// The one sentence the week earns.
  public enum Headline: Equatable, Sendable {
    /// The worst overbooked day, by how much, and how many other days are over.
    case overbooked(key: String, minutes: Int, otherDays: Int)
    /// No day is over; the day with the least free time and what it keeps.
    case fullest(key: String, freeMinutes: Int)
    /// Nothing is planned.
    case open
  }

  /// The one change that would relieve the overbooked day: move a task from
  /// it to the roomiest day that can hold the task's estimate. Only a task that
  /// is not started, has no time that day, and is not due that day or earlier
  /// is ever moved.
  public struct Move: Equatable, Sendable {
    public let taskID: LorvexTask.ID
    public let title: String
    public let minutes: Int
    public let fromKey: String
    public let toKey: String
  }

  /// How far a day's load must exceed its working time before the day counts
  /// as overbooked, in minutes. Estimates are rough, and the pages round the
  /// durations they show to 15 minutes, so a smaller excess would set two
  /// nearly equal figures ("5 hr 30 min of work, 5 hr 15 min free") in front of
  /// a decision that is not worth making.
  public static let overbookedTolerance = 30

  public let days: [Day]
  public let range: ClosedRange<Int>
  public let headline: Headline
  /// Present only while ``headline`` is ``Headline/overbooked(key:minutes:otherDays:)``
  /// and some later-or-today day has room for one of that day's tasks.
  public let suggestion: Move?

  /// One day's input: its key, the timed events that touch it, and its tasks.
  /// A task's time that day is its ``LorvexTask/time(on:)`` for `key`.
  public struct DayInput: Sendable {
    public let key: String
    public let events: [CalendarTimelineEvent]
    public let tasks: [LorvexTask]
    public init(key: String, events: [CalendarTimelineEvent], tasks: [LorvexTask]) {
      self.key = key
      self.events = events
      self.tasks = tasks
    }
  }

  /// - Parameters:
  ///   - days: the week's days in order.
  ///   - todayKey: the logical today; the headline judges only today and later
  ///     days when the week contains any.
  ///   - workStart: working-window start, minutes since midnight.
  ///   - workEnd: working-window end, minutes since midnight, after `workStart`.
  ///   - nowMinutes: the current time on today, or `nil` to count today whole.
  public static func build(
    days: [DayInput], todayKey: String, workStart: Int, workEnd: Int, nowMinutes: Int? = nil
  ) -> LorvexWeekLoad {
    var built: [Day] = []
    var openTasks: [String: [LorvexTask]] = [:]
    var latestEnd = workEnd
    let holdsToday = days.contains { $0.key == todayKey }
    for input in days {
      let start = input.key == todayKey ? min(max(workStart, nowMinutes ?? workStart), workEnd) : workStart
      let capacity = workEnd - start
      let meetings = mergedMeetings(input.events, key: input.key, workStart: workStart, workEnd: workEnd)
      let meetingMinutes = meetings.reduce(0) { $0 + max($1.end - max($1.start, start), 0) }
      let open = input.tasks.filter(\.status.isActionable)
      openTasks[input.key] = open
      let dayNow = input.key == todayKey ? nowMinutes : nil
      let taskMinutes = open.reduce(0) { total, task in
        let item = LorvexCalmToday.Item(task: task, time: task.time(on: input.key))
        return total + max(item.workMinutes(nowMinutes: dayNow) ?? 0, 0)
      }
      let packed = pack(taskMinutes, around: meetings, workStart: start, workEnd: workEnd)
      latestEnd = max(latestEnd, packed.last?.end ?? workEnd)
      let load = meetingMinutes + taskMinutes
      built.append(
        Day(
          key: input.key,
          isToday: input.key == todayKey,
          isPast: holdsToday && input.key < todayKey,
          segments: (meetings.map { Block(kind: .meeting, start: $0.start, end: $0.end) } + packed)
            .sorted { $0.start < $1.start },
          meetingMinutes: meetingMinutes,
          taskCount: open.count,
          taskMinutes: taskMinutes,
          overMinutes: load - capacity >= overbookedTolerance ? load - capacity : 0,
          freeMinutes: max(capacity - load, 0)))
    }
    let headline = headline(built, todayKey: todayKey)
    return LorvexWeekLoad(
      days: built,
      range: workStart...min(latestEnd, 24 * 60),
      headline: headline,
      suggestion: suggestion(for: headline, days: built, openTasks: openTasks, todayKey: todayKey))
  }

  /// The least urgent movable task on the overbooked day (see ``Move``),
  /// moved to the today-or-later day with the most free time that fits it and
  /// is not past the task's due date. Among equally urgent tasks the smallest
  /// one that relieves the overbooking wins, then the largest.
  static func suggestion(
    for headline: Headline, days: [Day], openTasks: [String: [LorvexTask]], todayKey: String
  ) -> Move? {
    guard case .overbooked(let key, let over, _) = headline else { return nil }
    let candidates = (openTasks[key] ?? []).filter { task in
      (task.estimatedMinutes ?? 0) > 0 && task.status != .inProgress && task.time(on: key) == nil
        && (dueKey(task).map { $0 > key } ?? true)
    }
    let ordered = candidates.sorted { lhs, rhs in
      if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
      let l = lhs.estimatedMinutes ?? 0
      let r = rhs.estimatedMinutes ?? 0
      let lRelieves = l >= over
      let rRelieves = r >= over
      if lRelieves != rRelieves { return lRelieves }
      return lRelieves ? l < r : l > r
    }
    for task in ordered {
      let minutes = task.estimatedMinutes ?? 0
      let due = dueKey(task)
      let target = days
        .filter { day in
          day.key != key && day.key >= todayKey && day.freeMinutes >= minutes
            && (due.map { day.key <= $0 } ?? true)
        }
        .max { $0.freeMinutes < $1.freeMinutes || ($0.freeMinutes == $1.freeMinutes && $0.key > $1.key) }
      if let target {
        return Move(taskID: task.id, title: task.title, minutes: minutes, fromKey: key, toKey: target.key)
      }
    }
    return nil
  }

  private static func dueKey(_ task: LorvexTask) -> String? {
    task.dueDate.map { LorvexDateFormatters.ymdUTC.string(from: $0) }
  }

  private static func headline(_ days: [Day], todayKey: String) -> Headline {
    let ahead = days.filter { $0.key >= todayKey }
    let judged = ahead.isEmpty ? days : ahead
    let over = judged.filter { $0.overMinutes > 0 }
    if let worst = over.max(by: { $0.overMinutes < $1.overMinutes }) {
      return .overbooked(key: worst.key, minutes: worst.overMinutes, otherDays: over.count - 1)
    }
    let loaded = judged.filter { !$0.isEmpty }
    if let fullest = loaded.min(by: { $0.freeMinutes < $1.freeMinutes }) {
      return .fullest(key: fullest.key, freeMinutes: fullest.freeMinutes)
    }
    return .open
  }

  /// The day's timed events as disjoint intervals inside the working window.
  /// Each event takes its time on the day
  /// (``CalendarTimelineEvent/clockSpan(on:)``): a multi-day timed event
  /// covers its start to midnight on its first day, midnight to its end on its
  /// last, and whole days in between, and an event that ends at exactly
  /// midnight runs to the end of its day. An event without an end time takes
  /// the hour the calendar grids draw it with
  /// (``CalendarGridModel/defaultEventDurationMinutes``), and a zero-length
  /// event takes no time. An event that does not occur on the day
  /// (``CalendarTimelineEvent/occurs(on:)``) or has no readable start adds
  /// nothing.
  static func mergedMeetings(
    _ events: [CalendarTimelineEvent], key: String, workStart: Int, workEnd: Int
  ) -> [(start: Int, end: Int)] {
    let intervals: [(start: Int, end: Int)] = events.compactMap { event in
      guard !event.allDay, event.occurs(on: key) else { return nil }
      let start: Int
      let end: Int
      if event.dayPart(on: key) == .middleDay {
        (start, end) = (0, 24 * 60)
      } else if let span = event.clockSpan(on: key) {
        start = span.start
        end = min(span.end ?? span.start + CalendarGridModel.defaultEventDurationMinutes, 24 * 60)
      } else {
        return nil
      }
      let clipped = (start: max(start, workStart), end: min(end, workEnd))
      return clipped.end > clipped.start ? clipped : nil
    }
    var merged: [(start: Int, end: Int)] = []
    for interval in intervals.sorted(by: { $0.start < $1.start }) {
      if let last = merged.last, interval.start <= last.end {
        merged[merged.count - 1].end = max(last.end, interval.end)
      } else {
        merged.append(interval)
      }
    }
    return merged
  }

  /// Task minutes laid into the gaps between meetings, then past the window.
  static func pack(
    _ minutes: Int, around meetings: [(start: Int, end: Int)], workStart: Int, workEnd: Int
  ) -> [Block] {
    var remaining = minutes
    var blocks: [Block] = []
    var cursor = workStart
    for meeting in meetings + [(start: workEnd, end: workEnd)] where remaining > 0 {
      let gap = meeting.start - cursor
      if gap > 0 {
        let used = min(gap, remaining)
        blocks.append(Block(kind: .task, start: cursor, end: cursor + used))
        remaining -= used
      }
      cursor = max(cursor, meeting.end)
    }
    if remaining > 0 {
      let start = max(cursor, workEnd)
      blocks.append(Block(kind: .overrun, start: start, end: min(start + remaining, 24 * 60)))
    }
    return blocks
  }
}
