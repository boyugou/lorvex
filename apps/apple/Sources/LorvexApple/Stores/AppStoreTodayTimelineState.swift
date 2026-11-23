import Foundation
import LorvexCore

/// Where Today draws the day's schedule (``TodayPageLayout``).
enum TodaySchedulePlacement: Sendable {
  /// In the main column, above the tasks without a time.
  case inColumn
  /// On a time grid in a rail beside the column, which then lists every task.
  case besideColumn
}

/// Today's main column for one moment, built from one read of the clock and
/// the day: the page, the schedule, and what the column lists as tasks, so
/// the column shows every task once. A Today render builds it once and reads
/// every part from it, rather than rebuilding the day for each part it draws.
struct TodayColumnContent {
  let schedulePlacement: TodaySchedulePlacement
  /// Minutes since midnight in the product day, or nil on a day that is not
  /// today (``AppStore/nowMinutesInProductDay``).
  let nowMinutes: Int?
  let workCue: TodayWorkCue?
  let featured: LorvexCalmToday.Item?
  /// The day's list with its lead, facts line, and overbooked decision.
  let page: LorvexCalmToday
  /// Today on the clock: the day's calendar events and its timed tasks in one
  /// reading order, with a "now" row among them. With the schedule in the
  /// column these are its rows; beside the column the rail draws the day on
  /// its own grid, and these rows only tell a suggestion which calendar an
  /// event belongs to. Finished tasks keep their times, so the day reads as
  /// it ran. Suggested times are left out: a suggestion is a draft the person
  /// is still deciding on, so it keeps its own reviewable rows.
  let schedule: [LorvexTodayTimelineItem]
  /// The task list under the featured task, started tasks first as ``page``
  /// orders them. With the schedule in the column it holds the tasks without
  /// a time today, since the schedule shows the timed ones; beside the
  /// column it holds every task.
  let listItems: [LorvexCalmToday.Item]
  /// What the Done section lists. With the schedule in the column it leaves
  /// out a finished timed task, which keeps its place in the schedule; beside
  /// the column it holds everything finished today.
  let doneListTasks: [LorvexTask]

  init(
    nowMinutes: Int?, page: LorvexCalmToday, schedule: [LorvexTodayTimelineItem],
    doneToday: [LorvexTask], workCue: TodayWorkCue?,
    schedulePlacement: TodaySchedulePlacement = .inColumn
  ) {
    self.schedulePlacement = schedulePlacement
    self.nowMinutes = nowMinutes
    self.page = page
    self.workCue = workCue
    let featuredID = workCue.flatMap { $0.bringsTaskToTop ? $0.taskID : nil }
    featured = featuredID == nil ? nil : page.lead
    self.schedule = schedule.filter { row in
      if case .task(let task) = row.kind { return task.id != featuredID }
      return true
    }
    // The tasks the in-column schedule already shows. Beside the column no
    // task is drawn there, so the list and Done hold them all.
    let scheduled: Set<LorvexTask.ID> =
      schedulePlacement == .besideColumn
      ? []
      : Set(
        schedule.compactMap { row -> LorvexTask.ID? in
          if case .task(let task) = row.kind { return task.id }
          return nil
        })
    listItems = page.items.filter { $0.id != featuredID && !scheduled.contains($0.id) }
    doneListTasks = doneToday.filter { !scheduled.contains($0.id) }
  }

  /// The unfinished timed tasks the in-column schedule draws as rows, in its
  /// order; none while the schedule stands beside the column, where each is a
  /// row of ``listItems`` instead.
  var scheduleRowTasks: [LorvexTask] {
    guard schedulePlacement == .inColumn else { return [] }
    return schedule.compactMap { row in
      guard case .task(let task) = row.kind, task.status.isActionable else { return nil }
      return task
    }
  }
}

extension AppStore {
  /// Where the window showing Today draws the day's schedule. The page sets
  /// it from the width it has (``TodayPageLayout``), so the arrow keys, range
  /// selection, and Select All follow the rows the column draws.
  var todaySchedulePlacement: TodaySchedulePlacement {
    get { todayStorage.schedulePlacement }
    set { if todayStorage.schedulePlacement != newValue { todayStorage.schedulePlacement = newValue } }
  }

  /// ``TodayColumnContent`` for the current clock.
  var todayColumnContent: TodayColumnContent {
    todayColumnContent(at: Date())
  }

  /// - Parameter placement: where the caller draws the schedule; nil reads
  ///   ``todaySchedulePlacement``.
  func todayColumnContent(
    at tick: Date, placement: TodaySchedulePlacement? = nil
  ) -> TodayColumnContent {
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
      doneToday: doneTodayTasks, workCue: cue,
      schedulePlacement: placement ?? todaySchedulePlacement)
  }

  /// Today's tasks that have a time today, finished ones included: what a
  /// time grid of today draws as task blocks.
  var todayTimedTasks: [LorvexTask] {
    let day = logicalTodayDateString
    return (today.tasks.filter(\.status.isActionable) + doneTodayTasks).filter { $0.time(on: day) != nil }
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
