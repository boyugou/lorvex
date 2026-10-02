import Foundation
import LorvexCore

extension MobileStore {
  /// Today's calendar events, the day's fixed commitments, filtered out of the
  /// loaded timeline window. Empty when the timeline has not loaded or the day
  /// is clear.
  var todayScheduleEvents: [CalendarTimelineEvent] {
    calendarTimeline?.eventsOccurring(on: logicalTodayString) ?? []
  }

  /// Today on the clock for the schedule: the day's calendar events and its
  /// timed tasks in one reading order, with a "now" row among them. Finished
  /// tasks keep their times, so the day reads as it ran.
  ///
  /// Suggested times are left out: a suggestion is a draft the user is still
  /// deciding on, so it keeps its own reviewable rows.
  var todaySchedule: [LorvexTodayTimelineItem] {
    let tasks = snapshot.today.tasks.filter(\.status.isActionable) + doneTodayTasks
    return LorvexTodayTimeline.build(
      events: todayScheduleEvents,
      tasks: tasks,
      times: tasks.times(on: logicalTodayString),
      nowMinutes: nowMinutesInProductDay)
  }

  /// Minutes since midnight in the product day's own timezone, or `nil` when the
  /// loaded snapshot is not for the current day, where a clock position would
  /// be meaningless.
  var nowMinutesInProductDay: Int? {
    LorvexProductDayClock.nowMinutes(on: logicalTodayString, in: logicalTimeZone)
  }

  /// The working window in minutes since midnight, or nil until the
  /// preference loads or when it does not run forward.
  var workdayWindow: Range<Int>? {
    guard let start = workdayStartMinutes, let end = workdayEndMinutes, end > start else {
      return nil
    }
    return start..<end
  }

  /// The Today page for the current clock: the day's list with its lead, the
  /// facts line, and the overbooked decision (``LorvexCalmToday``).
  /// Recomputed on every read, so a view inside a per-minute `TimelineView`
  /// advances a running time without a reload.
  var calmToday: LorvexCalmToday {
    LorvexCalmToday.build(
      tasks: snapshot.today.tasks,
      events: todayScheduleEvents,
      doneToday: doneTodayCount,
      nowMinutes: nowMinutesInProductDay,
      logicalDay: logicalTodayString,
      workingHours: workdayWindow)
  }

  /// Each of today's timed tasks' time range ("9:45 – 10:45 AM"), keyed by
  /// task id, so a task list outside Today shows when a task happens with the
  /// same words Today uses. Built from one ``calmToday`` read; a list reads it
  /// once per render and looks rows up in it.
  var todayTimeLabels: [LorvexTask.ID: String] {
    var labels: [LorvexTask.ID: String] = [:]
    for item in calmToday.items {
      guard let time = item.time else { continue }
      labels[item.id] = MobileTodayCalmCopy.timeRange(
        start: time.lowerBound, end: time.upperBound)
    }
    return labels
  }

  /// True once the lists have loaded and none holds an open task: an empty
  /// Today then means an empty app, not a free day with work waiting elsewhere.
  var hasNoOpenTasks: Bool {
    guard let lists = lists?.lists else { return false }
    return lists.allSatisfy { $0.openCount == 0 }
  }

  /// The day strip's segments: timed meetings, and timed tasks (the one whose
  /// time contains the clock in full accent, finished ones green).
  var todayStripSegments: [LorvexDayStrip.Segment] {
    let now = nowMinutesInProductDay
    return todaySchedule.compactMap { item in
      guard let start = item.startMinutes, let end = item.endMinutes, end > start else {
        return nil
      }
      switch item.kind {
      case .event(let event):
        return event.allDay ? nil : .init(kind: .meeting, start: start, end: end)
      case .task(let task):
        let kind: LorvexDayStrip.Kind =
          task.status == .completed
          ? .done : (now.map { (start..<end).contains($0) } == true ? .current : .task)
        return .init(kind: kind, start: start, end: end)
      case .now:
        return nil
      }
    }
  }

  /// The span the day strip draws: the working hours (8:00–19:00 until they
  /// load), widened to whole hours around anything timed outside them, so no
  /// segment is cut off at the strip's ends.
  var todayStripRange: ClosedRange<Int> {
    let segments = todayStripSegments
    let start = min(workdayWindow?.lowerBound ?? 8 * 60, segments.map(\.start).min() ?? .max)
    let end = max(workdayWindow?.upperBound ?? 19 * 60, segments.map(\.end).max() ?? 0)
    let lower = start / 60 * 60
    let upper = min((end + 59) / 60 * 60, 24 * 60)
    return lower...max(upper, lower + 60)
  }

  /// Refresh the done-today tasks and count from the canonical completed-today
  /// set, the same product-day-bounded query the widgets count. A failed read
  /// keeps the last value: the Done section is a record, not a reason to raise
  /// an error.
  func loadDoneTodayCount() async {
    guard let source = try? await core.loadWidgetStatsSource() else { return }
    doneTodayCount = source.completedTodayTasks.count
    // Completion stamps are UTC ISO-8601 strings, which sort chronologically.
    doneTodayTasks = source.completedTodayTasks.sorted {
      ($0.completedAt ?? "") > ($1.completedAt ?? "")
    }
  }

  /// Load the working hours for Today's overbooked decision, the day strip,
  /// and the Plan week's load.
  func loadWorkdayWindow() async {
    let hours = await loadWorkingHoursPreference()
    workdayStartMinutes = lorvexMinutesSinceMidnight(hours.start)
    workdayEndMinutes = lorvexEndMinutesSinceMidnight(hours.end)
  }
}
