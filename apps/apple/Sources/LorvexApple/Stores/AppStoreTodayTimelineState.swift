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
  let workCue: TodayWorkCue?
  let featured: LorvexCalmToday.Item?
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
    doneToday: [LorvexTask], workCue: TodayWorkCue?
  ) {
    self.nowMinutes = nowMinutes
    self.page = page
    self.workCue = workCue
    let featuredID = workCue.flatMap { $0.bringsTaskToTop ? $0.taskID : nil }
    featured = featuredID == nil ? nil : page.lead
    self.schedule = schedule.filter { row in
      if case .task(let task) = row.kind { return task.id != featuredID }
      return true
    }
    let scheduled = Set(
      schedule.compactMap { row -> LorvexTask.ID? in
        if case .task(let task) = row.kind { return task.id }
        return nil
      })
    untimedItems = page.items.filter { $0.id != featuredID && !scheduled.contains($0.id) }
    doneListTasks = doneToday.filter { !scheduled.contains($0.id) }
  }
}

extension AppStore {
  /// ``TodayColumnContent`` for the current clock.
  var todayColumnContent: TodayColumnContent {
    todayColumnContent(at: Date())
  }

  func todayColumnContent(at tick: Date) -> TodayColumnContent {
    let day = logicalTodayDateString
    let now = LorvexPreviewClock.now(in: LorvexDateFormatters.gregorianCalendar(timeZone: logicalTimeZone), tick: tick)
    let nowMinutes = LorvexProductDayClock.nowMinutes(on: day, in: logicalTimeZone, at: now)
    let events = todayScheduleEvents
    let page = calmToday(nowMinutes: nowMinutes, events: events, now: now)
    let hasCalendar = calendarTimeline.map { !$0.truncated && $0.from <= day && day <= $0.to } ?? false
    let cue = hasCalendar ? TodayWorkCue.resolve(
      lead: page.lead, blocked: today.blockedTaskIDs,
      events: events, day: day, nowMinutes: nowMinutes, now: now) : nil
    let tasks = today.tasks.filter(\.status.isActionable) + doneTodayTasks
    return TodayColumnContent(
      nowMinutes: nowMinutes,
      page: page,
      schedule: LorvexTodayTimeline.build(
        day: logicalTodayDateString,
        events: events,
        tasks: tasks,
        times: tasks.times(on: logicalTodayDateString),
        nowMinutes: nowMinutes, now: now),
      doneToday: doneTodayTasks, workCue: cue)
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

  /// Recheck the live task and the calendar before acting on a displayed cue.
  /// Continue and conflict inspection select the task without toggling its state.
  func performTodayWorkAction(_ cue: TodayWorkCue, at now: Date = Date()) async {
    guard let live = todayColumnContent(at: now).workCue, live.taskID == cue.taskID,
      live.action == cue.action, let task = today.tasks.first(where: { $0.id == cue.taskID })
    else { return }
    selectOnlyTodayTask(task.id)
    if cue.action == .start, !startIsHeldUp(for: task) {
      await startTaskFromRow(task)
    }
  }
}
