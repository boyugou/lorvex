import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import Testing

@Test
func widgetSnapshotProjectorBuildsAppleWidgetPayloadFromCoreSnapshot() {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0)!
  let now = Date(timeIntervalSince1970: 1_779_465_600)  // 2026-05-22T16:00:00Z
  let day = LorvexDateFormatters.ymdUTC.date(from: "2026-05-22")
  let today = TodaySnapshot(
    summary: "Two open tasks need attention.",
    tasks: [
      makeWidgetTask(
        id: "task-1",
        title: "Overdue task",
        priority: .p1,
        dueDate: now.addingTimeInterval(-24 * 60 * 60),
        estimatedMinutes: 10,
        listID: "inbox"
      ),
      makeWidgetTask(
        id: "task-2",
        title: "Task due today",
        priority: .p2,
        dueDate: now,
        plannedDate: day,
        plannedTime: 9 * 60..<10 * 60,
        estimatedMinutes: 20,
        listID: "work"
      ),
      makeWidgetTask(
        id: "task-done",
        title: "Done task",
        priority: .p3,
        status: .completed,
        dueDate: now,
        estimatedMinutes: nil,
        listID: "work",
        completedAt: "2026-05-22T15:00:00Z"
      ),
    ],
    briefing: "Start with the most important task.",
    localChangeSequence: 4
  )
  let projector = WidgetSnapshotProjector(calendar: calendar, now: { now })

  let lists = ListCatalogSnapshot(lists: [
    LorvexList(
      id: "inbox",
      name: "Inbox",
      color: nil,
      icon: "tray",
      description: nil,
      openCount: 1,
      totalCount: 1,
      updatedAt: "2026-05-21T00:00:00Z"),
    LorvexList(
      id: "work",
      name: "Work",
      color: "blue",
      icon: "briefcase",
      description: nil,
      openCount: 1,
      totalCount: 1,
      updatedAt: "2026-05-21T00:00:00Z"),
  ])

  let snapshot = projector.snapshot(today: today, timezone: "UTC", listCatalog: lists)

  #expect(snapshot.version == WidgetSnapshot.supportedVersion)
  #expect(snapshot.generatedAt == "2026-05-22T16:00:00Z")
  #expect(snapshot.timezone == "UTC")
  #expect(snapshot.logicalDay == "2026-05-22")
  #expect(snapshot.stats.todayCount == 2)
  #expect(snapshot.stats.dueTodayCount == 1)
  #expect(snapshot.stats.overdueCount == 1)
  #expect(snapshot.stats.attentionCount == 2)
  #expect(snapshot.stats.completedTodayCount == 1)
  #expect(snapshot.briefing == "Start with the most important task.")
  // Today's order is kept as given; the completed task is not listed.
  #expect(snapshot.tasks.map(\.id) == ["task-1", "task-2"])
  #expect(snapshot.tasks.first?.priority == 1)
  #expect(snapshot.tasks.first?.dueDate == "2026-05-21")
  #expect(snapshot.tasks.map(\.listID) == ["inbox", "work"])
  // Each task carries its time today, when it has one.
  #expect(snapshot.tasks.map(\.scheduledStart) == [nil, "09:00"])
  #expect(snapshot.tasks.map(\.scheduledEnd) == [nil, "10:00"])
  #expect(snapshot.lists.map(\.id) == ["inbox", "work"])
  #expect(snapshot.lists.map(\.name) == ["Inbox", "Work"])
  #expect(snapshot.listStats.map(\.id) == ["inbox", "work"])
  #expect(snapshot.listStats[0].stats.todayCount == 1)
  #expect(snapshot.listStats[0].stats.overdueCount == 1)
  #expect(snapshot.listStats[0].stats.completedTodayCount == 0)
  #expect(snapshot.listStats[1].stats.todayCount == 1)
  #expect(snapshot.listStats[1].stats.dueTodayCount == 1)
  #expect(snapshot.listStats[1].stats.completedTodayCount == 1)
}

@Test
func widgetSnapshotProjectorOmitsATimeSavedForAnotherDay() {
  let now = Date(timeIntervalSince1970: 1_779_465_600)  // 2026-05-22T16:00:00Z
  let today = TodaySnapshot(
    summary: "",
    tasks: [
      // Planned for an earlier day and still on Today: its old time is not
      // today's time.
      makeWidgetTask(
        id: "carried", title: "Carried over", priority: .p1, dueDate: nil,
        plannedDate: LorvexDateFormatters.ymdUTC.date(from: "2026-05-21"),
        plannedTime: 9 * 60..<10 * 60, estimatedMinutes: nil)
    ],
    localChangeSequence: 1)

  let snapshot = WidgetSnapshotProjector(now: { now }).snapshot(
    logicalDay: "2026-05-22", today: today, timezone: "UTC")

  #expect(snapshot.tasks.map(\.id) == ["carried"])
  #expect(snapshot.tasks.first?.scheduledStart == nil)
  #expect(snapshot.tasks.first?.scheduledEnd == nil)
}

@Test
func widgetSnapshotProjectorRedactsTitlesAndBriefingWhenRequested() {
  let now = Date(timeIntervalSince1970: 1_779_465_600)
  let today = TodaySnapshot(
    summary: "",
    tasks: [
      makeWidgetTask(
        id: "task-private",
        title: "Private appointment",
        priority: .p1,
        dueDate: nil,
        estimatedMinutes: nil
      )
    ],
    briefing: "Sensitive briefing",
    localChangeSequence: 1
  )
  let projector = WidgetSnapshotProjector(calendar: Calendar(identifier: .gregorian), now: { now })

  let snapshot = projector.snapshot(today: today, timezone: "UTC", hideTitles: true)

  #expect(snapshot.briefing == nil)
  #expect(snapshot.tasks.map(\.title) == ["Private task"])
}

@Test
func widgetSnapshotProjectorDropsTheBriefingWhileAFocusFilterNarrowsTheList() {
  let now = Date(timeIntervalSince1970: 1_779_465_600)
  let today = TodaySnapshot(
    summary: "",
    tasks: [
      makeWidgetTask(
        id: "work", title: "Work task", priority: .p1, dueDate: nil, estimatedMinutes: nil,
        listID: "work")
    ],
    briefing: "About the whole day",
    localChangeSequence: 1)

  let snapshot = WidgetSnapshotProjector(now: { now }).snapshot(
    today: today, timezone: "UTC", focusFilter: FocusFilterConfiguration(listIDs: ["work"]))

  #expect(snapshot.tasks.map(\.id) == ["work"])
  #expect(snapshot.briefing == nil)
}

@Test
func widgetSnapshotProjectorCountsFromUncappedStatsSourceNotTheDaysList() {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0)!
  let now = Date(timeIntervalSince1970: 1_779_465_600)  // 2026-05-22T16:00:00Z
  let overdueDate = now.addingTimeInterval(-24 * 60 * 60)  // 2026-05-21

  // The day's list: 10 undated open tasks, so that if any stat were still
  // derived from it, overdue / due-today / completed-today would all read zero
  // — making the canonical-source assertions unambiguous.
  let dayTasks = (0..<10).map { index in
    makeWidgetTask(
      id: "day-\(index)", title: "Day task \(index)", priority: .p2,
      dueDate: nil, estimatedMinutes: nil, listID: "work")
  }
  let today = TodaySnapshot(summary: "", tasks: dayTasks, localChangeSequence: 1)

  // The uncapped canonical actionable set: 6 overdue + 4 due-today + 3 undated
  // open tasks, plus two started (in_progress) tasks — one overdue, one undated.
  // 15 actionable tasks in all.
  var actionable: [LorvexTask] = []
  actionable += (0..<6).map {
    makeWidgetTask(
      id: "overdue-\($0)", title: "Overdue \($0)", priority: .p1,
      dueDate: overdueDate, estimatedMinutes: nil, listID: "work")
  }
  actionable += (0..<4).map {
    makeWidgetTask(
      id: "due-\($0)", title: "Due today \($0)", priority: .p2,
      dueDate: now, estimatedMinutes: nil, listID: "work")
  }
  actionable += (0..<3).map {
    makeWidgetTask(
      id: "undated-\($0)", title: "Undated \($0)", priority: .p3,
      dueDate: nil, estimatedMinutes: nil, listID: "work")
  }
  actionable.append(
    makeWidgetTask(
      id: "started-overdue", title: "Started overdue", priority: .p1,
      status: .inProgress, dueDate: overdueDate, estimatedMinutes: nil, listID: "work"))
  actionable.append(
    makeWidgetTask(
      id: "started-undated", title: "Started undated", priority: .p1,
      status: .inProgress, dueDate: nil, estimatedMinutes: nil, listID: "work"))

  // The production stats source is already bounded to the product day's exact
  // UTC interval, so every row in completedTodayTasks is a completion today.
  let completedToday = (0..<3).map {
    makeWidgetTask(
      id: "done-\($0)", title: "Done \($0)", priority: .p3, status: .completed,
      dueDate: nil, estimatedMinutes: nil, listID: "work", completedAt: "2026-05-22T10:00:00Z")
  }
  let statsSource = WidgetStatsSource(
    actionableTasks: actionable,
    completedTodayTasks: completedToday)

  let projector = WidgetSnapshotProjector(calendar: calendar, now: { now })
  let snapshot = projector.snapshot(today: today, timezone: "UTC", statsSource: statsSource)

  // Overdue and due-today reflect all 15 actionable tasks, and completed-today
  // is a real count. The today count is the day's list, which is what the
  // widget shows.
  #expect(snapshot.stats.overdueCount == 7)  // 6 open + 1 started overdue
  #expect(snapshot.stats.dueTodayCount == 4)
  #expect(snapshot.stats.attentionCount == 11)
  #expect(snapshot.stats.completedTodayCount == 3)
  #expect(snapshot.stats.todayCount == 10)

  // Without a stats source the projector falls back to the day's list, so the
  // same `today` reports zeros — proving the counts above come from the
  // canonical source, not `today.tasks`.
  let fallback = projector.snapshot(today: today, timezone: "UTC")
  #expect(fallback.stats.overdueCount == 0)
  #expect(fallback.stats.dueTodayCount == 0)
  #expect(fallback.stats.completedTodayCount == 0)
  #expect(fallback.stats.todayCount == 10)
}

private func makeWidgetTask(
  id: String,
  title: String,
  priority: LorvexTask.Priority,
  status: LorvexTask.Status = .open,
  dueDate: Date?,
  plannedDate: Date? = nil,
  plannedTime: Range<Int>? = nil,
  estimatedMinutes: Int?,
  listID: LorvexList.ID? = nil,
  completedAt: String? = nil
) -> LorvexTask {
  LorvexTask(
    id: id,
    title: title,
    notes: "",
    priority: priority,
    status: status,
    dueDate: dueDate,
    plannedDate: plannedDate,
    plannedTime: plannedTime,
    estimatedMinutes: estimatedMinutes,
    tags: [],
    listID: listID,
    completedAt: completedAt
  )
}
