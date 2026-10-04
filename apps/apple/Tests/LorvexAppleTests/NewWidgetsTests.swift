import Foundation
import LorvexCore
import LorvexWidgetExtension
import LorvexWidgetKitSupport
@testable import LorvexWidgetViews
import Testing

// MARK: - WidgetSnapshot habit/task codable round-trip

@Test
func widgetSnapshotHabitSummaryRoundTripsViaJSON() throws {
  let habit = WidgetSnapshot.HabitSummary(
    id: "h1",
    name: "Morning run",
    icon: "🏃",
    completedToday: 1,
    target: 1
  )
  let snapshot = WidgetSnapshot(
    generatedAt: "2026-05-25T08:00:00Z",
    timezone: "UTC",
    stats: .init(todayCount: 0, overdueCount: 0, dueTodayCount: 0),
    briefing: nil,
    tasks: [],
    habits: [habit]
  )
  let data = try JSONEncoder().encode(snapshot)
  let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
  #expect(decoded.habits.count == 1)
  #expect(decoded.habits[0].id == "h1")
  #expect(decoded.habits[0].name == "Morning run")
  #expect(decoded.habits[0].completedToday == 1)
  #expect(decoded.habits[0].target == 1)
  #expect(decoded.habits[0].isDoneToday == true)
}

@Test
func widgetSnapshotTodayTaskRoundTripsViaJSON() throws {
  let task = WidgetSnapshot.TodayTask(
    id: "t1",
    title: "Write tests",
    status: LorvexTask.Status.inProgress.rawValue,
    dueDate: "2026-05-25",
    priority: 1,
    listID: "work",
    estimatedMinutes: 30,
    scheduledStart: "09:00",
    scheduledEnd: "09:30"
  )
  let snapshot = WidgetSnapshot(
    generatedAt: "2026-05-25T08:00:00Z",
    timezone: "UTC",
    stats: .init(todayCount: 1, overdueCount: 0, dueTodayCount: 1),
    briefing: "Ship the tests before lunch.",
    tasks: [task],
    habits: [],
    lists: [.init(id: "work", name: "Work", icon: "briefcase")],
    listStats: [
      .init(
        id: "work",
        stats: .init(
          todayCount: 1,
          overdueCount: 0,
          dueTodayCount: 1,
          completedTodayCount: 1))
    ]
  )
  let data = try JSONEncoder().encode(snapshot)
  let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
  #expect(decoded == snapshot)
  #expect(decoded.tasks.count == 1)
  #expect(decoded.tasks[0].id == "t1")
  #expect(decoded.tasks[0].title == "Write tests")
  #expect(decoded.tasks[0].status == "in_progress")
  #expect(decoded.tasks[0].dueDate == "2026-05-25")
  #expect(decoded.tasks[0].priority == 1)
  #expect(decoded.tasks[0].listID == "work")
  #expect(decoded.tasks[0].estimatedMinutes == 30)
  #expect(decoded.tasks[0].scheduledStart == "09:00")
  #expect(decoded.tasks[0].scheduledEnd == "09:30")
  #expect(decoded.briefing == "Ship the tests before lunch.")
  #expect(decoded.lists == [.init(id: "work", name: "Work", icon: "briefcase")])
  #expect(decoded.listStats.first?.id == "work")
  #expect(decoded.listStats.first?.stats.completedTodayCount == 1)
}

@Test
func widgetSnapshotRejectsSnapshotMissingRequiredArray() {
  // A snapshot must carry every data array (empty, never omitted). The
  // decoder is strict, so a missing array is a decode failure the loader turns
  // into a graceful fallback rather than a silent empty default. Here
  // `list_stats` is absent.
  let incompleteJSON = """
    {
      "version": 4,
      "generated_at": "2026-05-25T08:00:00Z",
      "storage_generation": 0,
      "focus_filter_revision": 0,
      "workspace_instance_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      "local_change_sequence": 1,
      "stats": {
        "today_count": 1, "overdue_count": 0, "due_today_count": 0,
        "attention_count": 0, "completed_today_count": 0
      },
      "tasks": [],
      "habits": [],
      "lists": []
    }
    """
  let data = incompleteJSON.data(using: .utf8)!
  #expect(throws: DecodingError.self) {
    try JSONDecoder().decode(WidgetSnapshot.self, from: data)
  }
}

// MARK: - WidgetSnapshotProjector: habits + tasks projection

@Test
func widgetSnapshotProjectorPopulatesHabitsFromCatalog() {
  let now = Date(timeIntervalSince1970: 1_779_465_600)
  let today = TodaySnapshot(summary: "", tasks: [], localChangeSequence: 0)
  let catalog = HabitCatalogSnapshot(habits: [
    LorvexHabit(
      id: "h1", name: "Meditate", icon: "🧘", color: nil, cue: nil,
      frequencyType: "daily", targetCount: 1, completionsToday: 1,
      totalCompletions: 10, completionRate30d: 0.8, archived: false
    ),
    LorvexHabit(
      id: "h2", name: "Read", icon: nil, color: nil, cue: nil,
      frequencyType: "daily", targetCount: 2, completionsToday: 0,
      totalCompletions: 5, completionRate30d: 0.4, archived: false
    ),
    LorvexHabit(
      id: "h3", name: "Archived habit", icon: nil, color: nil, cue: nil,
      frequencyType: "daily", targetCount: 1, completionsToday: 0,
      totalCompletions: 0, completionRate30d: 0, archived: true
    ),
  ])
  let projector = WidgetSnapshotProjector(now: { now })
  let snapshot = projector.snapshot(
    today: today,
    timezone: "UTC",
    habitCatalog: catalog
  )
  // Archived habits must be excluded.
  #expect(snapshot.habits.count == 2)
  #expect(snapshot.habits[0].id == "h1")
  #expect(snapshot.habits[0].isDoneToday == true)
  #expect(snapshot.habits[1].id == "h2")
  #expect(snapshot.habits[1].isDoneToday == false)
}

@Test
func widgetSnapshotProjectorLeavesOutAHabitOnItsRestDay() {
  let now = Date(timeIntervalSince1970: 1_779_465_600)
  let today = TodaySnapshot(summary: "", tasks: [], localChangeSequence: 0)
  func habit(_ id: String, weekdays: [Int]?, completionsToday: Int = 0) -> LorvexHabit {
    LorvexHabit(
      id: id, name: id, icon: nil, color: nil, cue: nil,
      frequencyType: weekdays == nil ? "daily" : "weekly", targetCount: 1,
      completionsToday: completionsToday, totalCompletions: 0, completionRate30d: 0,
      archived: false, weekdays: weekdays)
  }
  // 2026-05-26 is a Tuesday: the Monday-Wednesday-Friday habit rests, and one
  // pinned to Mondays stays because it was checked in.
  let catalog = HabitCatalogSnapshot(habits: [
    habit("daily", weekdays: nil),
    habit("mon-wed-fri", weekdays: [0, 2, 4]),
    habit("tuesday", weekdays: [1]),
    habit("checked-in", weekdays: [0], completionsToday: 1),
  ])
  let snapshot = WidgetSnapshotProjector(now: { now }).snapshot(
    logicalDay: "2026-05-26", today: today, timezone: "UTC", habitCatalog: catalog)

  #expect(snapshot.habits.map(\.id) == ["daily", "tuesday", "checked-in"])
}

@Test
func widgetSnapshotProjectorListsAPeriodHabitOnlyWhileItIsOpen() {
  let now = Date(timeIntervalSince1970: 1_779_465_600)
  let today = TodaySnapshot(summary: "", tasks: [], localChangeSequence: 0)
  func habit(
    _ id: String, frequencyType: String, perPeriodTarget: Int? = nil, dayOfMonth: Int? = nil,
    periodMetDays: Int = 0
  ) -> LorvexHabit {
    LorvexHabit(
      id: id, name: id, icon: nil, color: nil, cue: nil, frequencyType: frequencyType,
      targetCount: 1, completionsToday: 0, totalCompletions: 0, completionRate30d: 0,
      archived: false, perPeriodTarget: perPeriodTarget, dayOfMonth: dayOfMonth,
      periodMetDays: periodMetDays)
  }
  // 2026-05-26: a monthly habit shows from its day until the month has a met
  // day, and a times-per-week habit until the week's quota is met.
  let catalog = HabitCatalogSnapshot(habits: [
    habit("monthly-open", frequencyType: "monthly", dayOfMonth: 20),
    habit("monthly-done", frequencyType: "monthly", dayOfMonth: 20, periodMetDays: 1),
    habit("monthly-later", frequencyType: "monthly", dayOfMonth: 28),
    habit("weekly-open", frequencyType: "times_per_week", perPeriodTarget: 3, periodMetDays: 2),
    habit("weekly-met", frequencyType: "times_per_week", perPeriodTarget: 3, periodMetDays: 3),
  ])
  let snapshot = WidgetSnapshotProjector(now: { now }).snapshot(
    logicalDay: "2026-05-26", today: today, timezone: "UTC", habitCatalog: catalog)

  #expect(snapshot.habits.map(\.id) == ["monthly-open", "weekly-open"])
}

@Test
func widgetSnapshotProjectorListsTheActionableTasksInTodaysOrder() {
  let now = Date(timeIntervalSince1970: 1_779_465_600)
  let today = TodaySnapshot(
    summary: "",
    tasks: [
      makeProjectorTask(
        id: "started-1", title: "Started task", priority: .p3, status: .inProgress, dueDate: nil,
        estimatedMinutes: nil),
      makeProjectorTask(id: "open-1", title: "Open task", priority: .p1, status: .open, dueDate: nil, estimatedMinutes: 20),
      makeProjectorTask(id: "done-1", title: "Done task", priority: .p2, status: .completed, dueDate: nil, estimatedMinutes: nil),
    ],
    localChangeSequence: 1
  )
  let projector = WidgetSnapshotProjector(now: { now })
  let snapshot = projector.snapshot(today: today, timezone: "UTC")
  #expect(snapshot.tasks.map(\.id) == ["started-1", "open-1"])
  #expect(snapshot.tasks[0].status == "in_progress")
  #expect(snapshot.tasks[1].title == "Open task")
  #expect(snapshot.tasks[1].estimatedMinutes == 20)
  #expect(snapshot.stats.todayCount == 2)
}

@Test
func widgetSnapshotProjectorNarrowsTasksToTheFocusFilterLists() {
  let now = Date(timeIntervalSince1970: 1_779_465_600)
  let today = TodaySnapshot(
    summary: "",
    tasks: [
      makeProjectorTask(
        id: "work-1", title: "Work task", priority: .p1, status: .open, dueDate: nil,
        estimatedMinutes: 20, listID: "work"),
      makeProjectorTask(
        id: "home-1", title: "Home task", priority: .p2, status: .open, dueDate: nil,
        estimatedMinutes: 10, listID: "home"),
    ],
    localChangeSequence: 1
  )
  let projector = WidgetSnapshotProjector(now: { now })
  let snapshot = projector.snapshot(
    today: today,
    timezone: "UTC",
    focusFilter: FocusFilterConfiguration(listIDs: ["work"])
  )

  #expect(snapshot.tasks.map(\.id) == ["work-1"])
}

// MARK: - Progress math

@Test
func progressWidgetRatioComputationIsCorrect() {
  // Two tasks done today and three still on Today's list: two of five.
  let p = ProgressWidgetView.todayProgress(completedToday: 2, leftToday: 3)
  #expect(p.total == 5)
  #expect(p.completed == 2)
  #expect(abs(p.ratio - 0.4) < 0.001)
}

@Test
func progressWidgetRatioIsZeroWhenNoTasks() {
  let p = ProgressWidgetView.todayProgress(completedToday: 0, leftToday: 0)
  #expect(p.total == 0)
  #expect(p.ratio == 0)
}

// Completing a task on Today's list moves it from left to done: the total
// holds and the ring advances. Clearing the list fills the ring.
@Test
func progressWidgetAdvancesOnCompletionAndReachesFull() {
  let before = ProgressWidgetView.todayProgress(completedToday: 1, leftToday: 2)
  let after = ProgressWidgetView.todayProgress(completedToday: 2, leftToday: 1)
  #expect(before.total == after.total)
  #expect(after.ratio > before.ratio)

  let full = ProgressWidgetView.todayProgress(completedToday: 3, leftToday: 0)
  #expect(full.total == 3)
  #expect(abs(full.ratio - 1.0) < 0.001)
}

@Test
func progressWidgetClampsNegativeCounts() {
  let p = ProgressWidgetView.todayProgress(completedToday: -1, leftToday: -4)
  #expect(p.completed == 0)
  #expect(p.total == 0)
  #expect(p.ratio == 0)
}

// MARK: - Habit isDoneToday logic

@Test
func habitSummaryIsDoneTodayRequiresMeetingTarget() {
  let notDone = WidgetSnapshot.HabitSummary(id: "h1", name: "Run", icon: nil, completedToday: 0, target: 1)
  let done = WidgetSnapshot.HabitSummary(id: "h2", name: "Read", icon: nil, completedToday: 2, target: 2)
  let over = WidgetSnapshot.HabitSummary(id: "h3", name: "Walk", icon: nil, completedToday: 3, target: 2)
  #expect(notDone.isDoneToday == false)
  #expect(done.isDoneToday == true)
  #expect(over.isDoneToday == true)
}

// MARK: - Bundle widget registration (structural check)

@Test
func widgetFamilyKindCoversAccessoryCircular() {
  // The circular accessory shows a count or a running time, never task rows.
  #expect(WidgetFamilyKind.accessoryCircular.maxTaskRows == 0)
}

@MainActor
@Test
func systemWidgetDrawsEveryRowItsFamiliesBudget() {
  // The medium and large views draw their rows as static branches up to a
  // fixed capacity; a larger budget would silently drop rows past it.
  for family in [WidgetFamilyKind.systemMedium, .systemLarge] {
    #expect(family.maxTaskRows <= SystemWidgetView.rowCapacity)
    #expect(family.maxTaskRowsWithoutLead <= SystemWidgetView.rowCapacity)
  }
}

@Test
func widgetSnapshotProjectorOmitsNoHabitsWhenCatalogIsNil() {
  let now = Date(timeIntervalSince1970: 1_779_465_600)
  let today = TodaySnapshot(summary: "", tasks: [], localChangeSequence: 0)
  let projector = WidgetSnapshotProjector(now: { now })
  let snapshot = projector.snapshot(today: today, timezone: nil, habitCatalog: nil)
  #expect(snapshot.habits.isEmpty)
}

@Test
func widgetSnapshotHabitTargetClampedToMinimumOne() {
  let habit = WidgetSnapshot.HabitSummary(id: "h1", name: "Test", icon: nil, completedToday: 0, target: 0)
  // target is clamped to 1 in the initializer
  #expect(habit.target == 1)
}

// MARK: - Helpers

private func makeProjectorTask(
  id: String,
  title: String,
  priority: LorvexTask.Priority,
  status: LorvexTask.Status,
  dueDate: Date?,
  estimatedMinutes: Int?,
  listID: String? = nil
) -> LorvexTask {
  LorvexTask(
    id: id, title: title, notes: "", priority: priority, status: status,
    dueDate: dueDate, estimatedMinutes: estimatedMinutes, tags: [], listID: listID
  )
}
