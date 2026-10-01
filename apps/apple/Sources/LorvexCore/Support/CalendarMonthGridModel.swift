import Foundation

/// One entry a month-grid day cell can show: a calendar event, a task planned
/// or due on the day without a time, or a task at its time on the day, in the
/// day's display order (see ``CalendarMonthGridDay/entries``).
public enum CalendarMonthGridEntry: Identifiable, Equatable, Sendable {
  case event(CalendarTimelineEvent)
  case task(LorvexTask)
  /// A task and its time on the day in minutes since midnight.
  case timedTask(LorvexTask, time: Range<Int>)

  public var id: String {
    switch self {
    case .event(let event): "event#\(event.id)"
    case .task(let task): "task#\(task.id)"
    case .timedTask(let task, _): "timed#\(task.id)"
    }
  }
}

/// One day cell's content in the month grid: every event and every planned,
/// due, or timed task that falls on this date, plus whether the date belongs
/// to the anchor month (leading/trailing days from adjacent months render
/// dimmed but still show their own content).
public struct CalendarMonthGridDay: Identifiable, Equatable, Sendable {
  public let date: Date
  /// `yyyy-MM-dd` key matching `CalendarTimelineEvent.startDate`.
  public let dayKey: String
  public let isCurrentMonth: Bool
  /// All-day entries first (sorted by title), then timed entries in start-time
  /// order — the order a reader scans a day: full-day context before the
  /// clock-ordered agenda. Unbounded; callers cap the visible count with
  /// ``CalendarMonthGridModel/chips(for:maxVisible:)``.
  public let events: [CalendarTimelineEvent]
  /// Tasks planned or due on the day without a time on it.
  public let scheduledTasks: [LorvexTask]
  /// Tasks with a time on this day, in start order.
  public let timedTasks: [LorvexTask]
  public var id: String { dayKey }

  public init(
    date: Date,
    dayKey: String,
    isCurrentMonth: Bool,
    events: [CalendarTimelineEvent],
    scheduledTasks: [LorvexTask],
    timedTasks: [LorvexTask] = []
  ) {
    self.date = date
    self.dayKey = dayKey
    self.isCurrentMonth = isCurrentMonth
    self.events = events
    self.scheduledTasks = scheduledTasks
    self.timedTasks = timedTasks
  }

  /// The day's entries in reading order: all-day events, then timed events and
  /// timed tasks together by start time (title on a tie), then the tasks
  /// planned or due on the day without a time.
  public var entries: [CalendarMonthGridEntry] {
    let allDay = events.filter(\.allDay).map(CalendarMonthGridEntry.event)
    let timed: [(minute: Int, title: String, entry: CalendarMonthGridEntry)] =
      events.filter { !$0.allDay }.map {
        (CalendarGridModel.parseMinutes($0.startTime) ?? -1, $0.title, .event($0))
      }
      + timedTasks.compactMap { task in
        task.plannedTime.map { time in
          (time.lowerBound, task.title, CalendarMonthGridEntry.timedTask(task, time: time))
        }
      }
    let ordered = timed.sorted { lhs, rhs in
      if lhs.minute != rhs.minute { return lhs.minute < rhs.minute }
      return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
    return allDay + ordered.map(\.entry) + scheduledTasks.map(CalendarMonthGridEntry.task)
  }
}

/// Pure month-grid layout assembly: takes a month anchor plus the events and
/// scheduled tasks visible in its grid range and produces the weeks × 7 day
/// cells a month view renders. Free of SwiftUI so it stays cheap, testable,
/// and shared the way ``CalendarGridModel`` is shared between the macOS week
/// grid and the iPhone day/3-day view.
///
/// Layout rules:
/// - The grid always starts on the first day of the week (per
///   `calendar.firstWeekday`) containing the 1st of the month, and spans
///   whole weeks through the month's last day — 5 or 6 rows depending on how
///   the month's length and first weekday align. Leading/trailing days from
///   the adjacent months fill the remaining cells (`isCurrentMonth == false`).
/// - An event occupies every day cell its `[startDate, endDate]` span
///   intersects within the grid range, regardless of `allDay` — unlike the
///   week/day timeline, the month grid has no intra-day axis to clip a timed
///   event to, so it is shown as a whole-day entry on each day it touches.
/// - A task with a time renders as a timed chip on its planned day, the way the
///   week grid draws it; a task without one renders as a plain chip on its
///   planned day (falling back to its due day). A cancelled task is not drawn,
///   and a task passed twice is drawn once.
public enum CalendarMonthGridModel {
  /// Cells shown per row before the rest of a busy day folds into a "+N"
  /// overflow chip (see ``chips(for:maxVisible:)``).
  public static let defaultMaxChipsPerDay = 3

  /// The first moment (start of day) of the month containing `date`.
  public static func startOfMonth(containing date: Date, calendar: Calendar) -> Date {
    let components = calendar.dateComponents([.year, .month], from: date)
    return calendar.date(from: components) ?? calendar.startOfDay(for: date)
  }

  /// The grid's first visible day and how many days it spans (always a
  /// multiple of 7) to cover the month containing `date` in whole weeks.
  public static func gridRange(forMonthContaining date: Date, calendar: Calendar) -> (
    start: Date, dayCount: Int
  ) {
    let monthStart = startOfMonth(containing: date, calendar: calendar)
    let gridStart = CalendarGridModel.startOfWeek(containing: monthStart, calendar: calendar)
    guard let monthDayRange = calendar.range(of: .day, in: .month, for: monthStart) else {
      return (gridStart, 42)
    }
    let leadingDays = calendar.dateComponents([.day], from: gridStart, to: monthStart).day ?? 0
    let totalDays = leadingDays + monthDayRange.count
    let weeks = Int(ceil(Double(totalDays) / 7.0))
    return (gridStart, max(weeks, 1) * 7)
  }

  /// Builds the full weeks × 7 day-cell grid for the month containing
  /// `monthAnchor`. `dayKeyFor` formats a Date to the `yyyy-MM-dd` key used by
  /// event `startDate`/`endDate`. Task storage days use the shared
  /// planned-first UTC key from ``CalendarGridModel/scheduledTaskDayKey(_:)``.
  public static func buildDays(
    monthAnchor: Date,
    calendar: Calendar,
    events: [CalendarTimelineEvent],
    tasks: [LorvexTask],
    dayKeyFor: (Date) -> String
  ) -> [CalendarMonthGridDay] {
    let monthStart = startOfMonth(containing: monthAnchor, calendar: calendar)
    let (gridStart, dayCount) = gridRange(forMonthContaining: monthAnchor, calendar: calendar)
    let dayDates: [Date] = (0..<dayCount).compactMap {
      calendar.date(byAdding: .day, value: $0, to: gridStart)
    }
    let dayKeys = dayDates.map(dayKeyFor)
    let keySet = Set(dayKeys)

    var eventsByKey: [String: [CalendarTimelineEvent]] = [:]
    for event in events {
      let startKey = event.startDate
      let endKey = event.endDate ?? event.startDate
      for key in dayKeys where key >= startKey && key <= endKey {
        eventsByKey[key, default: []].append(event)
      }
    }

    var timedByKey: [String: [LorvexTask]] = [:]
    var tasksByKey: [String: [LorvexTask]] = [:]
    var seenTaskIDs = Set<LorvexTask.ID>()
    for task in tasks where task.status != .cancelled && seenTaskIDs.insert(task.id).inserted {
      if let plannedDate = task.plannedDate, task.plannedTime != nil {
        let key = LorvexDateFormatters.ymdUTC.string(from: plannedDate)
        if keySet.contains(key) { timedByKey[key, default: []].append(task) }
        continue
      }
      guard let key = CalendarGridModel.scheduledTaskDayKey(task), keySet.contains(key) else { continue }
      tasksByKey[key, default: []].append(task)
    }

    return zip(dayDates, dayKeys).map { date, key in
      let dayEvents = (eventsByKey[key] ?? []).sorted(by: orderedBefore)
      let dayTimed = (timedByKey[key] ?? []).sorted {
        ($0.plannedTime?.lowerBound ?? 0) < ($1.plannedTime?.lowerBound ?? 0)
      }
      return CalendarMonthGridDay(
        date: date,
        dayKey: key,
        isCurrentMonth: calendar.isDate(date, equalTo: monthStart, toGranularity: .month),
        events: dayEvents,
        scheduledTasks: tasksByKey[key] ?? [],
        timedTasks: dayTimed
      )
    }
  }

  /// Splits a day's events + tasks into the chips a bounded cell can show and
  /// the remainder folded into a "+N" overflow count. When the day overflows,
  /// one visible slot is reserved for the "+N" chip itself, matching the week
  /// grid's all-day-strip overflow convention.
  public static func chips(
    for day: CalendarMonthGridDay, maxVisible: Int
  ) -> (visible: [CalendarMonthGridEntry], overflowCount: Int) {
    let all = day.entries
    guard all.count > maxVisible else { return (all, 0) }
    let cap = max(maxVisible - 1, 0)
    return (Array(all.prefix(cap)), all.count - cap)
  }

  /// All-day events sort first (by title), then timed events by start minute
  /// (by title on a tie) — full-day context before the clock-ordered agenda.
  private static func orderedBefore(_ lhs: CalendarTimelineEvent, _ rhs: CalendarTimelineEvent)
    -> Bool
  {
    let lhsMinute = lhs.allDay ? -1 : (CalendarGridModel.parseMinutes(lhs.startTime) ?? -1)
    let rhsMinute = rhs.allDay ? -1 : (CalendarGridModel.parseMinutes(rhs.startTime) ?? -1)
    if lhsMinute != rhsMinute { return lhsMinute < rhsMinute }
    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
  }
}
