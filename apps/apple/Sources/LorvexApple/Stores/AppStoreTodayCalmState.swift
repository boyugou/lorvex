import Foundation
import LorvexCore

extension AppStore {
  var doneTodayCount: Int {
    get { todayStorage.doneTodayCount }
    set { todayStorage.doneTodayCount = newValue }
  }

  /// Tasks completed on the product day, newest completion first.
  var doneTodayTasks: [LorvexTask] {
    get { todayStorage.doneTodayTasks }
    set { todayStorage.doneTodayTasks = newValue }
  }

  var workdayStartMinutes: Int? {
    get { todayStorage.workdayStartMinutes }
    set { todayStorage.workdayStartMinutes = newValue }
  }

  var workdayEndMinutes: Int? {
    get { todayStorage.workdayEndMinutes }
    set { todayStorage.workdayEndMinutes = newValue }
  }

  /// Load the working hours for Today's overbooked decision and the Plan
  /// week's per-day load, and return them for a caller that also shows the
  /// window.
  @discardableResult
  func loadWorkdayWindow() async -> (start: String, end: String) {
    let hours = await loadWorkingHoursPreference()
    workdayStartMinutes = lorvexMinutesSinceMidnight(hours.start)
    workdayEndMinutes = lorvexEndMinutesSinceMidnight(hours.end)
    return hours
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
  /// facts line, and the overbooked decision (``LorvexCalmToday``), read by
  /// Today and the menu bar panel alike.
  ///
  /// Recomputed on every read so a view inside a per-minute `TimelineView`
  /// advances a running time without a reload.
  var calmToday: LorvexCalmToday {
    calmToday(tasks: today.tasks)
  }

  /// Each of today's timed tasks' time range ("9:45 – 10:45 AM"), keyed by
  /// task id, so a list surface outside Today shows when a task happens with
  /// the same words Today uses. Built from one ``calmToday`` read; a list
  /// reads it once per render and looks rows up in it.
  var todayTimeLabels: [LorvexTask.ID: String] {
    var labels: [LorvexTask.ID: String] = [:]
    for item in calmToday.items {
      guard let time = item.time else { continue }
      labels[item.id] = TodayCalmCopy.timeRange(start: time.lowerBound, end: time.upperBound)
    }
    return labels
  }

  private func calmToday(tasks: [LorvexTask]) -> LorvexCalmToday {
    LorvexCalmToday.build(
      tasks: tasks,
      events: todayScheduleEvents,
      doneToday: doneTodayCount,
      nowMinutes: nowMinutesInProductDay,
      logicalDay: logicalTodayDateString,
      workingHours: workdayWindow)
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
}
