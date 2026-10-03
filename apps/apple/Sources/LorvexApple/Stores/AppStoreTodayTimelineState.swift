import Foundation
import LorvexCore

/// Today's main column for one moment, built from one read of the clock and
/// the day: the page, the schedule, and what the lists around the schedule
/// show, so every task appears once. A Today render builds it once and reads
/// every part from it, rather than rebuilding the day for each part it draws.
struct TodayColumnContent {
  /// Minutes since midnight in the product day, or nil on a day that is not
  /// today (``AppStore/nowMinutesInProductDay``).
  let nowMinutes: Int?
  /// The day's list with its lead, facts line, and overbooked decision.
  let page: LorvexCalmToday
  /// Today on the clock, for the schedule at the top of the column: the day's
  /// calendar events and its timed tasks in one reading order, with a "now"
  /// row among them. Finished tasks keep their times, so the day reads as it
  /// ran. Suggested times are left out: a suggestion is a draft the person is
  /// still deciding on, so it keeps its own reviewable rows.
  let schedule: [LorvexTodayTimelineItem]
  /// Today's list entries the schedule does not show: the tasks without a
  /// time today, started ones first as ``page`` orders them.
  let untimedItems: [LorvexCalmToday.Item]
  /// What the Done section lists: today's finished tasks without a time,
  /// since a finished timed task keeps its place in the schedule.
  let doneListTasks: [LorvexTask]

  init(
    nowMinutes: Int?, page: LorvexCalmToday, schedule: [LorvexTodayTimelineItem],
    doneToday: [LorvexTask]
  ) {
    self.nowMinutes = nowMinutes
    self.page = page
    self.schedule = schedule
    let scheduled = Set(
      schedule.compactMap { row -> LorvexTask.ID? in
        if case .task(let task) = row.kind { return task.id }
        return nil
      })
    untimedItems = page.items.filter { !scheduled.contains($0.id) }
    doneListTasks = doneToday.filter { !scheduled.contains($0.id) }
  }
}

extension AppStore {
  /// ``TodayColumnContent`` for the current clock.
  var todayColumnContent: TodayColumnContent {
    let nowMinutes = nowMinutesInProductDay
    let tasks = today.tasks.filter(\.status.isActionable) + doneTodayTasks
    return TodayColumnContent(
      nowMinutes: nowMinutes,
      page: calmToday(nowMinutes: nowMinutes),
      schedule: LorvexTodayTimeline.build(
        day: logicalTodayDateString,
        events: todayScheduleEvents,
        tasks: tasks,
        times: tasks.times(on: logicalTodayDateString),
        nowMinutes: nowMinutes),
      doneToday: doneTodayTasks)
  }

  /// Minutes since midnight in the product day's own timezone, or `nil` when the
  /// loaded snapshot is not for the current day.
  ///
  /// Anchored to ``logicalTimeZone`` rather than this Mac's zone so the marker
  /// sits where the *product day* says the clock is — the same day boundary every
  /// other Today read uses. Returns `nil` on a day that is not today, where a
  /// "now" row would be meaningless.
  var nowMinutesInProductDay: Int? {
    LorvexProductDayClock.nowMinutes(on: logicalTodayDateString, in: logicalTimeZone)
  }
}
