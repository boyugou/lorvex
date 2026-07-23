import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import Testing

@Test
func widgetSnapshotProjectorBuildsAppleWidgetPayloadFromCoreSnapshot() {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0)!
  let now = Date(timeIntervalSince1970: 1_779_465_600)
  let today = TodaySnapshot(
    focusTitle: "Today",
    summary: "Two open tasks need attention.",
    tasks: [
      makeWidgetTask(
        id: "task-2",
        title: "Second focus task",
        priority: .p2,
        dueDate: now,
        estimatedMinutes: 20,
        listID: "work"
      ),
      makeWidgetTask(
        id: "task-1",
        title: "First focus task",
        priority: .p1,
        dueDate: now.addingTimeInterval(-24 * 60 * 60),
        estimatedMinutes: 10,
        listID: "inbox"
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
    localChangeSequence: 4
  )
  let currentFocus = CurrentFocusPlan(
    date: "2026-05-22",
    taskIDs: ["task-1", "task-2"],
    briefing: "Start with the most important task.",
    timezone: "UTC",
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

  let snapshot = projector.snapshot(
    today: today,
    currentFocus: currentFocus,
    timezone: nil,
    listCatalog: lists)

  #expect(snapshot.version == WidgetSnapshot.supportedVersion)
  #expect(snapshot.generatedAt == "2026-05-22T16:00:00Z")
  #expect(snapshot.timezone == "UTC")
  #expect(snapshot.logicalDay == "2026-05-22")
  #expect(snapshot.stats.focusCount == 2)
  #expect(snapshot.stats.dueTodayCount == 1)
  #expect(snapshot.stats.overdueCount == 1)
  #expect(snapshot.stats.attentionCount == 2)
  #expect(snapshot.briefing == "Start with the most important task.")
  #expect(snapshot.focusTasks.map(\.id) == ["task-1", "task-2"])
  #expect(snapshot.focusTasks.first?.priority == 1)
  #expect(snapshot.focusTasks.first?.dueDate == "2026-05-21")
  #expect(snapshot.focusTasks.map(\.listID) == ["inbox", "work"])
  #expect(snapshot.todayTasks.map(\.listID).contains("work"))
  #expect(snapshot.lists.map(\.id) == ["inbox", "work"])
  #expect(snapshot.lists.map(\.name) == ["Inbox", "Work"])
  #expect(snapshot.listStats.map(\.id) == ["inbox", "work"])
  #expect(snapshot.listStats[0].stats.focusCount == 1)
  #expect(snapshot.listStats[0].stats.overdueCount == 1)
  #expect(snapshot.listStats[0].stats.completedTodayCount == 0)
  #expect(snapshot.listStats[1].stats.focusCount == 1)
  #expect(snapshot.listStats[1].stats.dueTodayCount == 1)
  #expect(snapshot.listStats[1].stats.completedTodayCount == 1)
}

@Test
func widgetSnapshotProjectorRedactsTitlesAndBriefingWhenRequested() {
  let now = Date(timeIntervalSince1970: 1_779_465_600)
  let today = TodaySnapshot(
    focusTitle: "Today",
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
    localChangeSequence: 1
  )
  let currentFocus = CurrentFocusPlan(
    date: "2026-05-22",
    taskIDs: ["task-private"],
    briefing: "Sensitive briefing",
    timezone: "UTC",
    localChangeSequence: 1
  )
  let projector = WidgetSnapshotProjector(calendar: Calendar(identifier: .gregorian), now: { now })

  let snapshot = projector.snapshot(
    today: today,
    currentFocus: currentFocus,
    timezone: nil,
    hideTitles: true
  )

  #expect(snapshot.briefing == nil)
  #expect(snapshot.focusTasks.map(\.title) == ["Private task"])
}

@Test
func widgetSnapshotProjectorCountsFromUncappedStatsSourceNotDashboardPool() {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0)!
  let now = Date(timeIntervalSince1970: 1_779_465_600)  // 2026-05-22T16:00:00Z
  let overdueDate = now.addingTimeInterval(-24 * 60 * 60)  // 2026-05-21

  // The dashboard pool is the ≤10 priority-capped list. Give it 10 undated open
  // tasks so that if any stat were still derived from it, overdue / due-today /
  // completed-today would all read zero and focus would read 10 — making the
  // canonical-source assertions unambiguous.
  let dashboardTasks = (0..<10).map { index in
    makeWidgetTask(
      id: "dash-\(index)", title: "Dashboard \(index)", priority: .p2,
      dueDate: nil, estimatedMinutes: nil, listID: "work")
  }
  let today = TodaySnapshot(
    focusTitle: "Today", summary: "", tasks: dashboardTasks, localChangeSequence: 1)

  // The uncapped canonical actionable set: 6 overdue + 4 due-today + 3 undated
  // open tasks, plus two started (in_progress) tasks that sit *beyond* the
  // dashboard cap — one overdue, one undated. 15 actionable tasks in all.
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
  let snapshot = projector.snapshot(
    today: today, currentFocus: nil, timezone: nil, statsSource: statsSource)

  // Counts reflect all 15 actionable tasks (incl. the two started ones beyond the
  // cap), not the 10-task dashboard pool, and completed-today is a real count.
  #expect(snapshot.stats.overdueCount == 7)  // 6 open + 1 started overdue
  #expect(snapshot.stats.dueTodayCount == 4)
  #expect(snapshot.stats.focusCount == 15)
  #expect(snapshot.stats.attentionCount == 11)
  #expect(snapshot.stats.completedTodayCount == 3)

  // Without a stats source the projector falls back to the dashboard pool, so the
  // same `today` reports zeros and a capped focus count — proving the counts
  // above come from the canonical source, not `today.tasks`.
  let fallback = projector.snapshot(today: today, currentFocus: nil, timezone: nil)
  #expect(fallback.stats.overdueCount == 0)
  #expect(fallback.stats.dueTodayCount == 0)
  #expect(fallback.stats.completedTodayCount == 0)
  #expect(fallback.stats.focusCount == 10)
}

private func makeWidgetTask(
  id: String,
  title: String,
  priority: LorvexTask.Priority,
  status: LorvexTask.Status = .open,
  dueDate: Date?,
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
    estimatedMinutes: estimatedMinutes,
    tags: [],
    listID: listID,
    completedAt: completedAt
  )
}
