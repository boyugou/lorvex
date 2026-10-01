import Foundation
import LorvexCore

/// Today's list read at one clock, for every widget and complication: the lead
/// task, when one leads, and the tasks after it.
///
/// The lead follows ``TodayLead``: a task whose saved time contains the clock,
/// else a started task, else the next saved time today; otherwise no task
/// leads and `rest` is Today's whole list. The rest keep Today's order. A
/// running time is the only thing a glance measures: its ring fills and its
/// minutes count down; every other task is a row in the list.
public struct WidgetTodayGlance: Equatable, Sendable {
  public struct Item: Equatable, Sendable, Identifiable {
    public var task: WidgetSnapshot.TodayTask
    /// Minutes since midnight of the task's saved time today, when it has one.
    public var time: Range<Int>?

    public var id: String { task.id }

    public init(task: WidgetSnapshot.TodayTask, time: Range<Int>?) {
      self.task = task
      self.time = time
    }
  }

  public var lead: Item?
  /// Why `lead` leads; nil exactly when `lead` is.
  public var leadKind: TodayLead.Kind?
  public var rest: [Item]
  public var nowMinutes: Int

  public init(lead: Item?, leadKind: TodayLead.Kind? = nil, rest: [Item], nowMinutes: Int) {
    self.lead = lead
    self.leadKind = lead == nil ? nil : leadKind
    self.rest = rest
    self.nowMinutes = nowMinutes
  }

  /// True while the lead's saved time contains the clock.
  public var isLeadRunning: Bool {
    lead?.time?.contains(nowMinutes) ?? false
  }

  /// The ring's fill: how much of the lead's running time has passed; empty
  /// when its time is not running.
  public var progress: Double {
    guard isLeadRunning, let time = lead?.time, !time.isEmpty else { return 0 }
    return Double(nowMinutes - time.lowerBound) / Double(time.count)
  }

  /// Whole minutes left in the lead's running time, or nil.
  public var minutesLeft: Int? {
    guard isLeadRunning, let time = lead?.time else { return nil }
    return time.upperBound - nowMinutes
  }

  /// Every task still to do: the lead and the ones after it.
  public var remainingCount: Int { (lead == nil ? 0 : 1) + rest.count }

  /// Minutes of work left today: what remains of each saved time not yet
  /// over, and each untimed task's estimate. Nil when no task carries either.
  public var workMinutes: Int? {
    let minutes = ([lead].compactMap { $0 } + rest).compactMap { item -> Int? in
      if let time = item.time {
        return time.upperBound > nowMinutes
          ? time.upperBound - max(time.lowerBound, nowMinutes) : nil
      }
      guard let estimate = item.task.estimatedMinutes, estimate > 0 else { return nil }
      return estimate
    }
    return minutes.isEmpty ? nil : minutes.reduce(0, +)
  }

  public static func build(
    tasks: [WidgetSnapshot.TodayTask], nowMinutes: Int
  ) -> WidgetTodayGlance {
    let items = tasks.filter(\.isActionable).map { Item(task: $0, time: time(of: $0)) }
    guard
      let lead = TodayLead.lead(
        in: items, nowMinutes: nowMinutes, time: \.time, isStarted: \.task.isStarted)
    else {
      return WidgetTodayGlance(lead: nil, rest: items, nowMinutes: nowMinutes)
    }
    var rest = items
    let leadItem = rest.remove(at: lead.index)
    return WidgetTodayGlance(
      lead: leadItem, leadKind: lead.kind, rest: rest, nowMinutes: nowMinutes)
  }

  /// The task's saved time as minutes since midnight. A time that ends at
  /// midnight is stored as `24:00`.
  public static func time(of task: WidgetSnapshot.TodayTask) -> Range<Int>? {
    guard let start = lorvexMinutesSinceMidnight(task.scheduledStart),
      let end = lorvexEndMinutesSinceMidnight(task.scheduledEnd), end > start
    else { return nil }
    return start..<end
  }

  /// Minutes since midnight at `date` in the day's timezone, or in `base`'s
  /// zone when the snapshot names none or one the system does not know.
  public static func minutes(
    at date: Date, timezoneName: String?, calendar base: Calendar = .autoupdatingCurrent
  ) -> Int {
    let calendar = Self.calendar(base, timezoneName: timezoneName)
    let parts = calendar.dateComponents([.hour, .minute], from: date)
    return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
  }

  /// The instants after `date` and not after `until` at which a glance built
  /// from `tasks` changes: every saved time's start and end still ahead (the
  /// lead can change at each), plus a tick every `tickMinutes` inside each time
  /// so a running ring keeps filling. Sorted, unique, at most `limit` dates.
  public static func changeDates(
    tasks: [WidgetSnapshot.TodayTask],
    from date: Date,
    until: Date,
    timezoneName: String?,
    calendar base: Calendar = .autoupdatingCurrent,
    tickMinutes: Int = 10,
    limit: Int = 40
  ) -> [Date] {
    guard until > date, tickMinutes > 0, limit > 0 else { return [] }
    let calendar = Self.calendar(base, timezoneName: timezoneName)
    let nowMinutes = minutes(at: date, timezoneName: timezoneName, calendar: base)
    var marks = Set<Int>()
    for task in tasks where task.isActionable {
      guard let time = time(of: task) else { continue }
      var minute = time.lowerBound
      while minute < time.upperBound {
        if minute > nowMinutes { marks.insert(minute) }
        minute += tickMinutes
      }
      if time.upperBound > nowMinutes { marks.insert(time.upperBound) }
    }
    let startOfDay = calendar.startOfDay(for: date)
    let dates = marks.sorted().compactMap { minute -> Date? in
      let instant: Date?
      if minute >= 24 * 60 {
        instant = calendar.date(byAdding: .day, value: 1, to: startOfDay)
      } else {
        instant = calendar.date(
          bySettingHour: minute / 60, minute: minute % 60, second: 0, of: startOfDay)
      }
      guard let instant, instant > date, instant <= until else { return nil }
      return instant
    }
    return Array(dates.prefix(limit))
  }

  private static func calendar(_ base: Calendar, timezoneName: String?) -> Calendar {
    var calendar = base
    if let timezoneName, let zone = TimeZone(identifier: timezoneName) {
      calendar.timeZone = zone
    }
    return calendar
  }
}
