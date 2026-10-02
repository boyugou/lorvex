import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import Testing

/// A snapshot of `tasks` on 2026-05-22 in UTC and the render model a family
/// builds from it at `now`.
private func renderModel(
  _ tasks: [WidgetSnapshot.TodayTask],
  at now: Date = Date(timeIntervalSince1970: 1_779_465_600),  // 2026-05-22T16:00:00Z
  family: WidgetFamilyKind,
  briefing: String? = nil,
  freshness: WidgetSnapshotFreshness = .fresh(ageSeconds: 0)
) -> WidgetRenderModel {
  let snapshot = WidgetSnapshot(
    generatedAt: "2026-05-22T16:00:00Z",
    timezone: "UTC",
    logicalDay: "2026-05-22",
    stats: .init(todayCount: tasks.count, overdueCount: 0, dueTodayCount: 0),
    briefing: briefing,
    tasks: tasks
  )
  return WidgetRenderModelBuilder().model(
    entry: WidgetTimelineEntry(
      date: now, state: .snapshot(snapshot, freshness: freshness),
      refreshAfter: now.addingTimeInterval(30 * 60)),
    family: family,
    statusText: "Updated now")
}

private func utc(_ iso: String) -> Date {
  ISO8601DateFormatter().date(from: iso) ?? .distantPast
}

@Test
func widgetRenderModelBuildsMediumLeadAndRows() {
  // The entry's clock is 16:00 UTC: the first task's time (15:45–16:30) is
  // running, the second's (17:00–18:00) is ahead, and two tasks have none.
  let model = renderModel(
    [
      widgetTodayTask(
        id: "task-1", title: "First", priority: 1, estimatedMinutes: 25,
        scheduledStart: "15:45", scheduledEnd: "16:30"),
      widgetTodayTask(
        id: "task-2", title: "Second", priority: 2, estimatedMinutes: 15,
        scheduledStart: "17:00", scheduledEnd: "18:00"),
      widgetTodayTask(id: "task-3", title: "Third", priority: 3, estimatedMinutes: 20),
      widgetTodayTask(id: "task-4", title: "Fourth", priority: nil, estimatedMinutes: nil),
    ],
    family: .systemMedium,
    briefing: "  Start with deep work.\n",
    freshness: .fresh(ageSeconds: 60))

  #expect(model.state == .content)
  #expect(model.headline == "Today")
  #expect(model.briefing == "Start with deep work.")
  #expect(model.staleAgeLabel == nil)
  #expect(model.lead?.id == "task-1")
  #expect(model.lead?.isRunning == true)
  #expect(model.lead?.minutesLeft == 30)
  #expect(model.lead?.line == "Until \(lorvexClockTimeLabel(minutes: 16 * 60 + 30))")
  #expect(model.lead?.shortLine == model.lead?.line)
  #expect(model.lead?.urlString == "lorvex://task/task-1")
  #expect(model.taskRows.map(\.id) == ["task-2", "task-3"])
  #expect(model.taskRows.first?.metadata == lorvexClockTimeLabel(minutes: 17 * 60))
  #expect(model.taskRows.last?.metadata == "20 min")
  #expect(model.taskRows.first?.urlString == "lorvex://task/task-2")
  #expect(model.upcomingCount == 3)
  #expect(model.remainingCount == 4)
  #expect(model.urlString == "lorvex://open/today")
}

@Test
func widgetRenderModelPhrasesALeadWhoseTimeIsNotRunning() {
  let tasks = [
    widgetTodayTask(
      id: "timed", title: "Timed", priority: nil, estimatedMinutes: 45,
      scheduledStart: "15:45", scheduledEnd: "16:30"),
    widgetTodayTask(id: "loose", title: "Loose", priority: nil, estimatedMinutes: 40),
  ]
  let range = lorvexClockRangeLabel(startMinutes: 15 * 60 + 45, endMinutes: 16 * 60 + 30)
  let start = lorvexClockTimeLabel(minutes: 15 * 60 + 45)

  // Before its time it leads as the next time, stating its time.
  let before = renderModel(tasks, at: utc("2026-05-22T08:00:00Z"), family: .systemSmall)
  #expect(before.lead?.id == "timed")
  #expect(before.lead?.isRunning == false)
  #expect(before.lead?.progress == 0)
  #expect(before.lead?.minutesLeft == nil)
  #expect(before.lead?.line == range)
  #expect(before.lead?.shortLine == start)

  // After it, nothing runs, is started, or is ahead: no task leads, and the
  // small family lists the top two with what is left of the day.
  let after = renderModel(tasks, at: utc("2026-05-22T17:00:00Z"), family: .systemSmall)
  #expect(after.lead == nil)
  #expect(after.state == .content)
  #expect(after.taskRows.map(\.id) == ["timed", "loose"])
  #expect(after.dayLine == "2 left today · about 40 min")
  // Under the Home Screen families' "Today" title the line names no day.
  #expect(after.dayLeftUnderTitle == "2 left")
  #expect(after.dayLineUnderTitle == "2 left · about 40 min")
  // A one-line slot without the title falls back through shorter wordings.
  #expect(
    after.dayLineChoices == [
      "2 left today · about 40 min", "2 left · about 40 min", "2 left today", "2 left",
    ])

  let inline = renderModel(tasks, family: .accessoryInline)
  #expect(inline.headline == "Timed")
  #expect(inline.urlString == "lorvex://task/timed")
  #expect(inline.taskRows.isEmpty)
  #expect(inline.upcomingCount == 1)
}

@Test
func widgetRenderModelSaysNothingIsLeftWithoutADayLine() {
  let model = renderModel([], family: .systemMedium)
  #expect(model.state == .empty)
  #expect(model.dayLine == nil)
  #expect(model.dayLeftUnderTitle == nil)
  #expect(model.dayLineUnderTitle == nil)
  #expect(model.dayLineChoices.isEmpty)
}

@Test
func widgetRenderModelDropsRepeatedDayLineChoicesWithoutWork() {
  // No task carries an estimate or a time, so the line has no work part and
  // the choices with and without it would repeat each other.
  let model = renderModel(
    [widgetTodayTask(id: "loose", title: "Loose", priority: nil, estimatedMinutes: nil)],
    family: .accessoryRectangular)
  #expect(model.lead == nil)
  #expect(model.dayLineChoices == ["1 left today", "1 left"])
}

@Test
func widgetRenderModelDescribesAnUntimedLeadByItsState() {
  // An untimed task that is not started does not lead; its row keeps its
  // estimate.
  let estimated = renderModel(
    [widgetTodayTask(id: "loose", title: "Loose", priority: nil, estimatedMinutes: 40)],
    family: .systemLarge)
  #expect(estimated.lead == nil)
  #expect(estimated.taskRows.first?.metadata == "40 min")

  let started = renderModel(
    [
      widgetTodayTask(
        id: "started", title: "Started", status: LorvexTask.Status.inProgress.rawValue,
        priority: nil, estimatedMinutes: 40)
    ],
    family: .systemLarge)
  #expect(started.lead?.line == "Started · about 40 min")
  #expect(started.lead?.shortLine == "Started")

  let overdue = renderModel(
    [
      widgetTodayTask(
        id: "overdue", title: "Overdue", status: LorvexTask.Status.inProgress.rawValue,
        dueDate: "2026-05-21", priority: nil, estimatedMinutes: 40)
    ],
    family: .systemLarge)
  #expect(overdue.lead?.isOverdue == true)
  #expect(overdue.lead?.line == "Overdue")
}

@Test
func widgetRenderModelRowsReadTheirOwnState() {
  // At 16:00 UTC the "long" time (15:00–17:00) leads; "short" (15:45–16:30)
  // is running too, so its row counts down to its end.
  let model = renderModel(
    [
      widgetTodayTask(
        id: "started", title: "Started", status: LorvexTask.Status.inProgress.rawValue,
        priority: 1, estimatedMinutes: nil),
      widgetTodayTask(
        id: "long", title: "Long", priority: 2, estimatedMinutes: nil,
        scheduledStart: "15:00", scheduledEnd: "17:00"),
      widgetTodayTask(
        id: "short", title: "Short", priority: 2, estimatedMinutes: nil,
        scheduledStart: "15:45", scheduledEnd: "16:30"),
      widgetTodayTask(
        id: "overdue", title: "Overdue", dueDate: "2026-05-21", priority: 2,
        estimatedMinutes: nil),
      widgetTodayTask(
        id: "ahead", title: "Ahead", priority: 3, estimatedMinutes: 30,
        scheduledStart: "17:00", scheduledEnd: "17:30"),
      widgetTodayTask(id: "estimated", title: "Estimated", priority: 3, estimatedMinutes: 25),
    ],
    family: .systemLarge)

  #expect(model.lead?.id == "long")
  #expect(model.taskRows.map(\.id) == ["started", "short", "overdue", "ahead", "estimated"])
  #expect(
    model.taskRows.map(\.metadata) == [
      "Started", "Until \(lorvexClockTimeLabel(minutes: 16 * 60 + 30))", "Overdue",
      lorvexClockTimeLabel(minutes: 17 * 60), "25 min",
    ])
  #expect(model.taskRows.map(\.tone) == [.started, .running, .overdue, .plain, .plain])
}

@Test
func widgetRenderModelCarriesStaleAgeLabel() {
  let model = renderModel(
    [widgetTodayTask(id: "task-1", title: "First", priority: 1, estimatedMinutes: 25)],
    at: Date(timeIntervalSince1970: 1_779_472_800),
    family: .systemSmall,
    freshness: .stale(ageSeconds: 2 * 60 * 60))

  #expect(model.state == .stale)
  #expect(model.staleAgeLabel == LorvexDateFormatters.elapsed(seconds: 2 * 60 * 60))
}

@Test
func widgetRenderModelUsesEmptyAndFallbackStates() {
  let now = Date(timeIntervalSince1970: 1_779_465_600)
  let fallbackEntry = WidgetTimelineEntry(
    date: now,
    state: .fallback(.init(reason: .missingFile, detail: "missing")),
    refreshAfter: now.addingTimeInterval(5 * 60)
  )

  let emptyModel = renderModel([], family: .systemSmall)
  let fallbackModel = WidgetRenderModelBuilder().model(
    entry: fallbackEntry,
    family: .systemSmall,
    statusText: "Open Lorvex to refresh"
  )

  #expect(emptyModel.state == .empty)
  #expect(emptyModel.subheadline == "Nothing left for today.")
  #expect(emptyModel.lead == nil)
  #expect(emptyModel.taskRows.isEmpty)
  #expect(fallbackModel.state == .fallback)
  #expect(fallbackModel.headline == "Lorvex")
  #expect(fallbackModel.statusText == "Open Lorvex to refresh")
  #expect(fallbackModel.urlString == "lorvex://open/today")
}

@Test
func widgetRenderModelEscapesTaskDeepLinks() {
  let model = renderModel(
    [
      widgetTodayTask(
        id: "task with/slash", title: "Escaped task",
        status: LorvexTask.Status.inProgress.rawValue, priority: nil, estimatedMinutes: nil)
    ],
    family: .systemSmall)

  #expect(model.lead?.urlString == "lorvex://task/task%20with%2Fslash")
}

@Test
func widgetRenderModelOmitsCompletedTasksFromTheList() {
  let model = renderModel(
    [
      widgetTodayTask(
        id: "done-task",
        title: "Already completed",
        status: LorvexTask.Status.completed.rawValue,
        priority: 1,
        estimatedMinutes: 20
      ),
      widgetTodayTask(id: "open-task", title: "Still actionable", priority: 2, estimatedMinutes: 30),
    ],
    family: .systemMedium)

  #expect(model.state == .content)
  #expect(model.lead == nil)
  #expect(model.taskRows.map(\.id) == ["open-task"])
  #expect(model.taskRows.first?.title == "Still actionable")
}
