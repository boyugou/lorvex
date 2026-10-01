import Foundation
import LorvexCore

extension AppStore {
  /// Today on the clock for the schedule at the top of the Today column: the day's calendar events and
  /// its timed tasks in one reading order, with a "now" row among them. The
  /// finished tasks keep their times, so the day reads as it ran.
  ///
  /// Suggested times are left out: a suggestion is a draft the user is still
  /// deciding on, so it keeps its own reviewable rows.
  var todaySchedule: [LorvexTodayTimelineItem] {
    let tasks = today.tasks.filter(\.status.isActionable) + doneTodayTasks
    return LorvexTodayTimeline.build(
      events: todayScheduleEvents,
      tasks: tasks,
      times: tasks.times(on: logicalTodayDateString),
      nowMinutes: nowMinutesInProductDay)
  }

  /// The ids of the tasks the schedule draws, so the column's other lists
  /// leave them out and every task appears once.
  var todayScheduledTaskIDs: Set<LorvexTask.ID> {
    Set(todaySchedule.compactMap { row in
      if case .task(let task) = row.kind { return task.id }
      return nil
    })
  }

  /// Today's list entries the schedule does not show: the tasks without a
  /// time today, started ones first as ``calmToday`` orders them.
  var todayUntimedItems: [LorvexCalmToday.Item] {
    let scheduled = todayScheduledTaskIDs
    return calmToday.items.filter { !scheduled.contains($0.id) }
  }

  /// What the Done section lists: today's finished tasks without a time,
  /// since a finished timed task keeps its place in the schedule.
  var todayDoneListTasks: [LorvexTask] {
    let scheduled = todayScheduledTaskIDs
    return doneTodayTasks.filter { !scheduled.contains($0.id) }
  }

  /// Minutes since midnight in the product day's own timezone, or `nil` when the
  /// loaded snapshot is not for the current day.
  ///
  /// Anchored to ``logicalTimezoneName`` rather than this Mac's zone so the marker
  /// sits where the *product day* says the clock is — the same day boundary every
  /// other Today read uses. Returns `nil` on a day that is not today, where a
  /// "now" row would be meaningless.
  var nowMinutesInProductDay: Int? {
    if let pinned = LorvexPreviewClock.pinnedMinutes { return pinned }
    var calendar = Calendar(identifier: .gregorian)
    if let zone = TimeZone(identifier: logicalTimezoneName) { calendar.timeZone = zone }
    let now = Date()
    let dayFormatter = DateFormatter()
    dayFormatter.calendar = Calendar(identifier: .gregorian)
    dayFormatter.locale = Locale(identifier: "en_US_POSIX")
    dayFormatter.dateFormat = "yyyy-MM-dd"
    dayFormatter.timeZone = calendar.timeZone
    guard dayFormatter.string(from: now) == logicalTodayDateString else { return nil }
    let parts = calendar.dateComponents([.hour, .minute], from: now)
    guard let hour = parts.hour, let minute = parts.minute else { return nil }
    return hour * 60 + minute
  }
}
