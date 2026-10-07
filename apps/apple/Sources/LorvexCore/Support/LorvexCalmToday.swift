import Foundation

/// Today's page, derived from Today's list, each task's time today, and the
/// day's calendar.
///
/// Every surface that draws Today (the macOS column and menu bar panel, iPhone,
/// iPad) reads this value instead of re-deriving the pieces, so these rules
/// hold everywhere:
///
/// - **items** is Today's whole list in Today's order: started tasks first,
///   then by priority and due date. There are no tiers and nothing is folded
///   away; an overdue task says so on its own row, and a started task with its
///   chip.
/// - The **lead** is the task every glance leads with (``TodayLead``): a task
///   whose saved time contains the clock, else a started task, else the next
///   saved time today; nil when none of those exists. The page gives it no
///   label; glances such as the menu bar panel open with it.
/// - The **facts** line and the **overbooked** decision read the same inputs,
///   so neither disagrees with the rows beneath it.
public struct LorvexCalmToday: Equatable, Sendable {
  /// One task on Today as the list shows it.
  public struct Item: Identifiable, Equatable, Sendable {
    public var task: LorvexTask
    /// The task's time today in minutes since midnight
    /// (``LorvexTask/time(on:)``), when it has one.
    public var time: Range<Int>?
    /// True while ``time`` contains the clock.
    public var isRunning: Bool
    public var id: String { task.id }

    public init(task: LorvexTask, time: Range<Int>? = nil, isRunning: Bool = false) {
      self.task = task
      self.time = time
      self.isRunning = isRunning
    }

    /// How much of a running time has passed, 0…1; 0 unless ``isRunning``.
    public func progress(nowMinutes: Int?) -> Double {
      guard isRunning, let nowMinutes, let time, !time.isEmpty else { return 0 }
      return min(max(Double(nowMinutes - time.lowerBound) / Double(time.count), 0), 1)
    }

    /// Whole minutes left in a running time, or nil.
    public func minutesLeft(nowMinutes: Int?) -> Int? {
      guard isRunning, let nowMinutes, let time else { return nil }
      return max(time.upperBound - nowMinutes, 0)
    }

    /// Minutes of work the task still asks of today: what is left of a running
    /// time, the length of a time still ahead, and otherwise the estimate (a
    /// time that passed unfinished still needs its work, so it counts its
    /// estimate, else its length). Nil when the task has neither.
    func workMinutes(nowMinutes: Int?) -> Int? {
      let estimate = task.estimatedMinutes.flatMap { $0 > 0 ? $0 : nil }
      guard let time else { return estimate }
      guard let nowMinutes else { return time.count }
      if time.contains(nowMinutes) { return time.upperBound - nowMinutes }
      if time.lowerBound >= nowMinutes { return time.count }
      return estimate ?? time.count
    }
  }

  /// Today holds more estimated work than the working time left after
  /// meetings. The page says so once ("About 6 hr of work and 4 hr free") and
  /// offers to move ``candidates`` to tomorrow.
  public struct Overbooked: Equatable, Sendable {
    /// Minutes of estimated work left today (``LorvexCalmToday/workMinutes``).
    public var workMinutes: Int
    /// Working minutes left today after the meetings in them.
    public var freeMinutes: Int
    /// The least urgent tasks that do not fit, taken from the end of the list
    /// until moving them covers the excess, and listed in the list's order:
    /// tasks that are not started, not timed, not due today or earlier, and
    /// that carry an estimate, since only an estimate frees time. Empty when no
    /// task qualifies; the page then states the fact and offers nothing.
    public var candidates: [LorvexTask]

    public init(workMinutes: Int, freeMinutes: Int, candidates: [LorvexTask]) {
      self.workMinutes = workMinutes
      self.freeMinutes = freeMinutes
      self.candidates = candidates
    }
  }

  /// The facts line under the date.
  public enum Facts: Equatable, Sendable {
    /// Nothing on Today, no meeting ahead, and nothing done today.
    case empty
    /// Nothing on Today and no meeting ahead, after this many tasks were done
    /// today.
    case allDone(done: Int)
    /// Tasks left; the estimated work in minutes when any task carries an
    /// estimate or a time; meetings still ahead.
    case day(tasks: Int, workMinutes: Int?, meetings: Int)
  }

  /// Today's list in Today's order.
  public var items: [Item]
  /// The ``TodayLead`` at the clock the page was built for, or nil when no
  /// task leads.
  public var leadID: LorvexTask.ID?
  public var doneToday: Int
  /// Timed calendar events still ahead today (or under way): the timed rows
  /// of Today's schedule the clock has not cleared
  /// (``CalendarTimelineEvent/clockSpan(on:)``). All-day events, and days that
  /// longer events fill, read as all day there and are not counted.
  public var remainingMeetings: Int
  /// Minutes of estimated work left, summed over the tasks that carry an
  /// estimate or a time (``Item/workMinutes(nowMinutes:)``); nil when none does.
  public var workMinutes: Int?
  /// Set while working hours remain and the estimated work exceeds the free
  /// working time left by at least ``LorvexWeekLoad/overbookedTolerance``.
  public var overbooked: Overbooked?

  public init(
    items: [Item], leadID: LorvexTask.ID?, doneToday: Int, remainingMeetings: Int,
    workMinutes: Int?, overbooked: Overbooked?
  ) {
    self.items = items
    self.leadID = leadID
    self.doneToday = doneToday
    self.remainingMeetings = remainingMeetings
    self.workMinutes = workMinutes
    self.overbooked = overbooked
  }

  /// The lead task's item.
  public var lead: Item? { items.first { $0.id == leadID } }

  public var facts: Facts {
    if items.isEmpty && remainingMeetings == 0 {
      return doneToday > 0 ? .allDone(done: doneToday) : .empty
    }
    return .day(tasks: items.count, workMinutes: workMinutes, meetings: remainingMeetings)
  }

  /// Pushes after which Today marks a task as pushed often.
  public static let deferredOftenThreshold = 3

  /// The assistant's briefing for the day as the page shows it under the
  /// facts line: the stored briefing with surrounding whitespace removed, or
  /// nil when there is none or only whitespace.
  public static func briefing(from raw: String?) -> String? {
    guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
    else { return nil }
    return trimmed
  }

  /// Derive the page.
  ///
  /// - Parameters:
  ///   - tasks: Today's list in Today's order (``TodaySnapshot/tasks``).
  ///     Tasks that are not actionable are skipped; each task's time today is
  ///     its ``LorvexTask/time(on:)`` for `logicalDay`.
  ///   - events: today's calendar events.
  ///   - doneToday: tasks completed today.
  ///   - nowMinutes: minutes since midnight, or nil for a day that is not
  ///     today (no lead by the clock, no running time, no overbooked check).
  ///   - logicalDay: the product day as `YYYY-MM-DD`. Due dates are stored as
  ///     UTC midnight of their calendar day, so they are compared as UTC day
  ///     strings against this value rather than through a device calendar.
  ///   - workingHours: the working window in minutes since midnight, for the
  ///     overbooked check; nil skips it.
  public static func build(
    tasks: [LorvexTask],
    events: [CalendarTimelineEvent],
    doneToday: Int,
    nowMinutes: Int?,
    logicalDay: String,
    workingHours: Range<Int>?
  ) -> LorvexCalmToday {
    let items = tasks.filter(\.status.isActionable).map { task in
      let time = task.time(on: logicalDay)
      return Item(
        task: task, time: time,
        isRunning: nowMinutes.map { now in time?.contains(now) ?? false } ?? false)
    }
    let leadIndex = TodayLead.lead(
      in: items, nowMinutes: nowMinutes, time: \.time,
      isStarted: { $0.task.status == .inProgress })?.index
    let work = items.compactMap { $0.workMinutes(nowMinutes: nowMinutes) }
    let workMinutes = work.isEmpty ? nil : work.reduce(0, +)
    let remainingMeetings = events.filter { event in
      guard let span = event.clockSpan(on: logicalDay) else { return false }
      guard let nowMinutes else { return true }
      return (span.end ?? span.start) > nowMinutes
    }.count
    return LorvexCalmToday(
      items: items,
      leadID: leadIndex.map { items[$0].id },
      doneToday: doneToday,
      remainingMeetings: remainingMeetings,
      workMinutes: workMinutes,
      overbooked: overbooked(
        items: items, workMinutes: workMinutes ?? 0, events: events, nowMinutes: nowMinutes,
        logicalDay: logicalDay, workingHours: workingHours))
  }

  /// The overbooked decision: the week strip's measure of today (meetings
  /// clipped to the rest of the working window, overlaps merged), so the Plan
  /// page and Today never disagree about whether today fits.
  static func overbooked(
    items: [Item], workMinutes: Int, events: [CalendarTimelineEvent], nowMinutes: Int?,
    logicalDay: String, workingHours: Range<Int>?
  ) -> Overbooked? {
    guard let nowMinutes, let workingHours, !workingHours.isEmpty else { return nil }
    let start = min(max(workingHours.lowerBound, nowMinutes), workingHours.upperBound)
    let capacity = workingHours.upperBound - start
    guard capacity > 0 else { return nil }
    let meetingMinutes = LorvexWeekLoad.mergedMeetings(
      events, key: logicalDay, workStart: workingHours.lowerBound, workEnd: workingHours.upperBound
    ).reduce(0) { $0 + max($1.end - max($1.start, start), 0) }
    let freeMinutes = max(capacity - meetingMinutes, 0)
    let excess = workMinutes - freeMinutes
    guard excess >= LorvexWeekLoad.overbookedTolerance else { return nil }

    var chosen = Set<LorvexTask.ID>()
    var moved = 0
    for item in items.reversed() where moved < excess {
      let task = item.task
      guard task.status != .inProgress, item.time == nil,
        let estimate = task.estimatedMinutes, estimate > 0
      else { continue }
      if let due = task.dueDate, LorvexDateFormatters.ymdUTC.string(from: due) <= logicalDay {
        continue
      }
      chosen.insert(task.id)
      moved += estimate
    }
    return Overbooked(
      workMinutes: workMinutes, freeMinutes: freeMinutes,
      candidates: items.map(\.task).filter { chosen.contains($0.id) })
  }
}
