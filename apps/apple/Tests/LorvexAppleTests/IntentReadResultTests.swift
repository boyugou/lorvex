import AppIntents
import Foundation
import LorvexCore
import Testing

@testable import LorvexSystemIntents

@Test
func dependencyReadNamesUnfinishedDependenciesAndWaitingTasks() {
  func node(_ id: String, _ status: String) -> DependencyGraphNode {
    DependencyGraphNode(
      id: id, title: id.capitalized, status: status, priority: nil, dueDate: nil,
      plannedDate: nil, listID: "inbox")
  }
  let graph = DependencyGraph(
    nodes: [
      node("ship", "open"), node("tests", "open"), node("notes", "completed"),
      node("deploy", "in_progress"), node("old", "cancelled"),
    ],
    edges: [
      DependencyGraphEdge(from: "ship", to: "tests"),
      DependencyGraphEdge(from: "ship", to: "notes"),
      DependencyGraphEdge(from: "deploy", to: "ship"),
      DependencyGraphEdge(from: "old", to: "tests"),
    ],
    roots: ["tests", "notes"], blocked: ["ship", "deploy", "old"], leafBlockers: ["tests"],
    truncated: false)

  // A finished dependency is not something the task still waits on.
  #expect(ReadLorvexDependencyGraphIntent.unfinishedDependencies(of: "ship", in: graph).map(\.id) == ["tests"])
  #expect(ReadLorvexDependencyGraphIntent.unfinishedDependencies(of: "tests", in: graph).isEmpty)
  // A cancelled task is not waiting on anything.
  #expect(ReadLorvexDependencyGraphIntent.waitingTasks(in: graph).map(\.id) == ["ship", "deploy"])
}

@Test
func dependencyReadReturnsWhatATaskWaitsOnAndWhatIsWaiting() async throws {
  try await withIsolatedAppIntentDatabase {
    let core = LorvexCoreRuntimeFactory.makeForAppIntent()
    let ship = try await core.createTask(title: "Ship the release", notes: "")
    let tests = try await core.createTask(title: "Run the tests", notes: "")
    let notes = try await core.createTask(title: "Write the notes", notes: "")
    _ = try await LorvexTaskIntentRunner.updateTask(
      id: ship.id, dependsOn: [tests.id, notes.id], core: core)
    _ = try await core.completeTask(id: notes.id)

    let waitsOn = try await ReadLorvexDependencyGraphIntent(rootTask: LorvexTaskEntity(task: ship))
      .perform().value
    #expect(waitsOn?.map(\.id) == [tests.id])
    let free = try await ReadLorvexDependencyGraphIntent(rootTask: LorvexTaskEntity(task: tests))
      .perform().value
    #expect(free?.isEmpty == true)
    let waiting = try await ReadLorvexDependencyGraphIntent().perform().value
    #expect(waiting?.map(\.id) == [ship.id])
  }
}

@Test
func overdueListsComeMostOverdueFirstThenByName() {
  func list(_ id: String, _ name: String) -> LorvexList {
    LorvexList(
      id: id, name: name, color: nil, icon: nil, description: nil, openCount: 3, totalCount: 5,
      updatedAt: "2026-10-01T00:00:00Z")
  }
  func health(_ id: String, overdue: Int) -> ListHealthEntry {
    ListHealthEntry(
      id: id, name: id, color: nil, icon: nil, openCount: 3, overdueOpenCount: overdue,
      dueTodayOpenCount: 0)
  }
  let catalog = [list("home", "Home"), list("errands", "Errands"), list("work", "Work"), list("calm", "Calm")]
  let entries = [
    health("home", overdue: 1), health("errands", overdue: 1), health("work", overdue: 4),
    health("calm", overdue: 0), health("gone", overdue: 2),
  ]
  let overdue = ReadLorvexListHealthIntent.listsWithOverdueTasks(health: entries, catalog: catalog)
  // A list the catalog no longer holds is left out; ties read by name.
  #expect(overdue.map(\.list.name) == ["Work", "Errands", "Home"])
  #expect(overdue.map(\.overdueCount) == [4, 1, 1])
}

@Test
func overdueListReadReturnsTheListsWithOverdueTasks() async throws {
  try await withIsolatedAppIntentDatabase {
    let core = LorvexCoreRuntimeFactory.makeForAppIntent()
    let today = try await core.getSessionContext().date
    let lastWeek = try #require(PlannedDayBridge.storageDate(forLogicalDay: today, addingDays: -7))
    let nextWeek = try #require(PlannedDayBridge.storageDate(forLogicalDay: today, addingDays: 7))
    let work = try await LorvexTaskIntentRunner.createList(name: "Work", description: nil, core: core)
    let home = try await LorvexTaskIntentRunner.createList(name: "Home", description: nil, core: core)
    for (title, listID, due) in [
      ("File the report", work.id, lastWeek), ("Send the invoice", work.id, lastWeek),
      ("Call the plumber", home.id, lastWeek), ("Water the plants", home.id, nextWeek),
    ] {
      let task = try await core.createTask(title: title, notes: "")
      _ = try await core.updateTask(TaskUpdateDraft(id: task.id, listID: listID, dueDate: .set(due)))
    }

    let lists = try await ReadLorvexListHealthIntent().perform().value
    #expect(lists?.map(\.id) == [work.id, home.id])
  }
}

@Test
func weekDayLabelAddsTheYearOnlyForAnotherYear() throws {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
  let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 2)))
  let thisYear = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 22)))
  let lastYear = try #require(calendar.date(from: DateComponents(year: 2025, month: 12, day: 29)))
  #expect(!ReadLorvexWeeklyReviewIntent.weekDayLabel(thisYear, now: now, calendar: calendar).contains("2026"))
  #expect(ReadLorvexWeeklyReviewIntent.weekDayLabel(lastYear, now: now, calendar: calendar).contains("2025"))
}

@Test
func habitCompletionDaysAreMidnightsOfTheDeviceCalendar() throws {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
  let days = ReadLorvexHabitCompletionsIntent.days(["2026-10-01", "not-a-day", "2026-09-30"], calendar: calendar)
  #expect(days.count == 2)
  #expect(days.map { calendar.dateComponents([.year, .month, .day, .hour], from: $0) } == [
    DateComponents(year: 2026, month: 10, day: 1, hour: 0),
    DateComponents(year: 2026, month: 9, day: 30, hour: 0),
  ])
}

@Test
func readIntentsReturnListsTagsOverviewAndMemory() async throws {
  try await withIsolatedAppIntentDatabase {
    let core = LorvexCoreRuntimeFactory.makeForAppIntent()
    #expect(try await ReadLorvexOverviewIntent().perform().value?.isEmpty == true)

    let errands = try await LorvexTaskIntentRunner.createList(name: "Errands", description: nil, core: core)
    let urgent = try await core.createTask(title: "Renew the passport", notes: "")
    _ = try await core.updateTask(TaskUpdateDraft(id: urgent.id, priority: .p1, tags: ["travel"]))
    let later = try await core.createTask(title: "Sort the photos", notes: "")
    _ = try await core.upsertMemory(key: "packing_list", content: "Passport, charger")

    let lists = try await ReadLorvexListsIntent().perform().value
    #expect(lists?.contains { $0.id == errands.id && $0.name == "Errands" } == true)
    #expect(lists?.contains { $0.id == LorvexListNaming.inboxID } == true)

    #expect(try await ListLorvexTagsIntent().perform().value == ["travel"])

    let top = try await ReadLorvexOverviewIntent().perform().value
    #expect(top?.first?.id == urgent.id)
    #expect(top?.contains { $0.id == later.id } == true)

    #expect(try await ReadLorvexMemoryIntent(key: "packing_list").perform().value == "Passport, charger")
  }
}

@Test
func readIntentsReturnRemindersTimedTasksAndCalendarEvents() async throws {
  try await withIsolatedAppIntentDatabase {
    let core = LorvexCoreRuntimeFactory.makeForAppIntent()
    let today = try await core.getSessionContext().date
    let todayDate = try #require(PlannedDayBridge.storageDate(forLogicalDay: today))

    let dentist = try await core.createTask(title: "Call the dentist", notes: "")
    let fireAt = LorvexDateFormatters.iso8601.string(from: Date().addingTimeInterval(3 * 3_600))
    _ = try await core.addTaskReminder(taskID: dentist.id, reminderAt: fireAt)
    let upcoming = try await ReadLorvexUpcomingTaskRemindersIntent().perform().value
    #expect(upcoming?.map(\.taskID) == [dentist.id])
    #expect(upcoming?.first?.taskTitle == "Call the dentist")
    #expect(try await ReadLorvexDueTaskRemindersIntent().perform().value?.isEmpty == true)

    let standup = try await core.createTask(title: "Prepare the standup", notes: "")
    _ = try await core.updateTask(
      TaskUpdateDraft(id: standup.id, plannedDate: .set(todayDate), plannedTime: .set(540..<570)))
    let timed = try await ReadLorvexDayTimesIntent(date: nil).perform().value
    #expect(timed?.map(\.id) == [standup.id])

    let event = try await LorvexTaskIntentRunner.createCalendarEvent(
      title: "Design review", startDate: today, startTime: "14:00", endTime: "15:00",
      allDay: false, location: nil, notes: nil, core: core)
    let timeline = try await ReadLorvexCalendarTimelineIntent(from: .now, to: .now).perform().value
    #expect(timeline?.contains { $0.id == event.id && $0.title == "Design review" } == true)
    let found = try await SearchLorvexCalendarEventsIntent(query: "design").perform().value
    #expect(found?.map(\.id) == [event.id])
  }
}

@Test
func readIntentsReturnWeeklyCompletionsHabitsAndReviews() async throws {
  try await withIsolatedAppIntentDatabase {
    let core = LorvexCoreRuntimeFactory.makeForAppIntent()
    let today = try await core.getSessionContext().date

    let done = try await core.createTask(title: "Book the flights", notes: "")
    _ = try await core.completeTask(id: done.id)
    let completed = try await ReadLorvexWeeklyReviewIntent().perform().value
    #expect(completed?.map(\.id) == [done.id])

    let habit = try await core.createHabit(name: "Stretch", cue: nil, targetCount: 1)
    _ = try await core.completeHabit(id: habit.id, date: today)
    let entity = LorvexHabitEntity(habit: habit)
    #expect(try await ReadLorvexHabitStatsIntent(habit: entity).perform().value == 1)
    let days = try await ReadLorvexHabitCompletionsIntent(habit: entity).perform().value
    #expect(days?.map { LorvexDateFormatters.ymd.string(from: $0) } == [today])

    _ = try await LorvexTaskIntentRunner.saveDailyReview(
      summary: "Shipped the release", date: today, mood: nil, energyLevel: nil, wins: nil,
      blockers: nil, learnings: nil, core: core)
    #expect(try await ReadLorvexReviewHistoryIntent().perform().value == ["Shipped the release"])
  }
}
