import Foundation
import Testing

@testable import LorvexCarPlay
@testable import LorvexCore

// MARK: - Helpers

/// Creates a task through the real write API and returns the stored task.
/// `dueToday` anchors the due date on the storage-frame day (raw `Date()`
/// lands on the next UTC day every local evening, vanishing from the
/// due-today pool); `.completed` completes it after creation.
@discardableResult
private func seedTask(
  _ svc: SwiftLorvexCoreService,
  title: String,
  status: LorvexTask.Status = .open,
  dueToday: Bool = true
) async throws -> LorvexTask {
  let created = try await svc.createTask(title: title, notes: "")
  var task = created
  if dueToday {
    task = try await svc.updateTask(
      TaskUpdateDraft(
        id: created.id,
        dueDate: .set(PlannedDayBridge.storageDate(forLocalInstant: Date()))))
  }
  if status == .completed {
    task = try await svc.completeTaskReturningTask(id: created.id)
  }
  return task
}

private func logicalDay(_ core: any LorvexCoreServicing) async throws -> String {
  try await core.getSessionContext().date
}

// MARK: - Tests

@MainActor
@Test
func carPlayControllerEmptySnapshotProducesNoRows() async throws {
  let svc = try makeInMemoryCore()
  let ctrl = CarPlayTaskListController(core: svc)
  try await ctrl.refresh()
  #expect(ctrl.todayRows.isEmpty)
  #expect(ctrl.rows.isEmpty)
}

@MainActor
@Test
func carPlayControllerTodayRowTitlesMatchOpenTasks() async throws {
  let svc = try makeInMemoryCore()
  try await seedTask(svc, title: "Alpha")
  try await seedTask(svc, title: "Beta")
  let ctrl = CarPlayTaskListController(core: svc)
  try await ctrl.refresh()
  let titles = Set(ctrl.todayRows.map(\.title))
  #expect(titles == ["Alpha", "Beta"])
}

@MainActor
@Test
func carPlayControllerExcludesCompletedTasksFromTodayRows() async throws {
  let svc = try makeInMemoryCore()
  try await seedTask(svc, title: "Open")
  try await seedTask(svc, title: "Done", status: .completed)
  let ctrl = CarPlayTaskListController(core: svc)
  try await ctrl.refresh()
  #expect(ctrl.todayRows.count == 1)
  #expect(ctrl.todayRows[0].title == "Open")
}

@MainActor
@Test
func carPlayControllerCompleteCallsServiceAndUpdatesRows() async throws {
  let svc = try makeInMemoryCore()
  let taskX = try await seedTask(svc, title: "Task X")
  try await seedTask(svc, title: "Task Y")
  let ctrl = CarPlayTaskListController(core: svc)
  try await ctrl.refresh()
  #expect(ctrl.todayRows.count == 2)
  try await ctrl.complete(id: taskX.id)
  let remaining = ctrl.todayRows.map(\.id)
  #expect(!remaining.contains(taskX.id))
}

@MainActor
@Test
func carPlayControllerCompleteRemovesRowFromList() async throws {
  let svc = try makeInMemoryCore()
  let rowA = try await seedTask(svc, title: "Row A")
  let ctrl = CarPlayTaskListController(core: svc)
  try await ctrl.refresh()
  try await ctrl.complete(id: rowA.id)
  #expect(ctrl.todayRows.isEmpty)
}

@MainActor
@Test
func carPlayControllerOrderPreservedFromSnapshot() async throws {
  let svc = try makeInMemoryCore()
  var tasks: [LorvexTask] = []
  for title in ["First", "Second", "Third"] {
    tasks.append(try await seedTask(svc, title: title))
  }
  let ctrl = CarPlayTaskListController(core: svc)
  try await ctrl.refresh()
  // The controller preserves the core's canonical order (equal priority and
  // due date, so id ASC decides).
  let expected = tasks.map(\.id).sorted()
  #expect(ctrl.todayRows.map(\.id) == expected)
}

@MainActor
@Test
func carPlayControllerReadsTodaysListWithoutABroadOpenQuery() async throws {
  let svc = StubCoreService(preview: try await makeSeededInMemoryCore())
  let todayTask = try await seedTask(svc.preview, title: "CarPlay today task")
  let inboxTask = try await seedTask(svc.preview, title: "CarPlay inbox task", dueToday: false)
  let completed = try await seedTask(svc.preview, title: "CarPlay completed task", status: .completed)
  let ctrl = CarPlayTaskListController(core: svc)

  try await ctrl.refresh()

  #expect(svc.listTasksCallCount == 0)
  #expect(ctrl.todayRows.contains { $0.id == todayTask.id })
  #expect(!ctrl.todayRows.contains { $0.id == inboxTask.id })
  #expect(!ctrl.todayRows.contains { $0.id == completed.id })
}

@MainActor
@Test
func carPlayControllerDriverSafeErrorMessageDoesNotExposeRawError() {
  let message = CarPlayTaskListController.driverSafeErrorMessage(
    for: LorvexCoreError.unsupportedOperation("SQLite database is locked at /private/tmp/lorvex.db")
  )

  #expect(message == "Couldn’t load tasks — tap to retry.")
  #expect(!message.localizedCaseInsensitiveContains("sqlite"))
  #expect(!message.localizedCaseInsensitiveContains("/private/tmp"))
}

@MainActor
@Test
func carPlayControllerDeferToTomorrowDropsTaskFromToday() async throws {
  let svc = try makeInMemoryCore()
  let deferMe = try await seedTask(svc, title: "Defer Me")
  let keep = try await seedTask(svc, title: "Keep")
  let ctrl = CarPlayTaskListController(core: svc)
  try await ctrl.refresh()
  #expect(ctrl.todayRows.count == 2)

  try await ctrl.deferToTomorrow(id: deferMe.id)

  let ids = ctrl.todayRows.map(\.id)
  #expect(!ids.contains(deferMe.id))
  #expect(ids.contains(keep.id))
}

// MARK: - Times, clock, and row copy

/// Pins the controller's clock to `hour:minute` in the day's timezone. The
/// controller must have refreshed once so the timezone is resolved.
@MainActor
private func pinClock(_ ctrl: CarPlayTaskListController, hour: Int, minute: Int) throws {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(ctrl.dayTimezone)
  let date = try #require(
    calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date()))
  ctrl.now = { date }
}

@MainActor
@Test
func carPlayControllerLeadsWithATaskOnlyWhileItsTimeRuns() async throws {
  let svc = try makeInMemoryCore()
  let first = try await seedTask(svc, title: "First")
  _ = try await svc.updateTask(TaskUpdateDraft(id: first.id, priority: .p1))
  let timed = try await seedTask(svc, title: "Timed")
  try await planTask(svc, timed.id, on: try await logicalDay(svc), time: 10 * 60..<11 * 60)
  let ctrl = CarPlayTaskListController(core: svc)
  try await ctrl.refresh()

  // Today's order is untouched by the time; the row carries it.
  #expect(ctrl.todayRows.map(\.id) == [first.id, timed.id])
  #expect(ctrl.todayRows[1].startMinutes == 10 * 60)
  #expect(ctrl.todayRows[1].endMinutes == 11 * 60)

  try pinClock(ctrl, hour: 10, minute: 30)
  #expect(ctrl.nowMinutes == 10 * 60 + 30)
  #expect(ctrl.rows.map(\.id) == [timed.id, first.id])
  #expect(
    CarPlayRowCopy.detail(for: ctrl.rows[0], nowMinutes: ctrl.nowMinutes)
      == "Until \(lorvexClockTimeLabel(minutes: 11 * 60))")

  try pinClock(ctrl, hour: 12, minute: 0)
  #expect(ctrl.rows.map(\.id) == [first.id, timed.id])
  #expect(
    CarPlayRowCopy.detail(for: ctrl.rows[1], nowMinutes: ctrl.nowMinutes)
      == lorvexClockRangeLabel(startMinutes: 10 * 60, endMinutes: 11 * 60))
}

@MainActor
@Test
func carPlayControllerMarksOverdueRows() async throws {
  let svc = try makeInMemoryCore()
  let overdue = try await seedTask(svc, title: "Overdue")
  let today = PlannedDayBridge.storageDate(forLocalInstant: Date())
  _ = try await svc.updateTask(
    TaskUpdateDraft(id: overdue.id, dueDate: .set(today.addingTimeInterval(-86_400))))
  let onTime = try await seedTask(svc, title: "On time")
  let ctrl = CarPlayTaskListController(core: svc)
  try await ctrl.refresh()

  let rows = Dictionary(uniqueKeysWithValues: ctrl.todayRows.map { ($0.id, $0) })
  #expect(rows[overdue.id]?.isOverdue == true)
  #expect(rows[onTime.id]?.isOverdue == false)
  #expect(CarPlayRowCopy.detail(for: try #require(rows[overdue.id]), nowMinutes: nil) == "Overdue")
}

@MainActor
@Test
func carPlayControllerShowsAStartedTaskFirstAndSaysSo() async throws {
  let svc = try makeInMemoryCore()
  let other = try await seedTask(svc, title: "Other")
  _ = try await svc.updateTask(TaskUpdateDraft(id: other.id, priority: .p1))
  let task = try await seedTask(svc, title: "Drive prep")
  _ = try await svc.updateTask(TaskUpdateDraft(id: task.id, estimatedMinutes: .set(30)))
  let ctrl = CarPlayTaskListController(core: svc)
  try await ctrl.refresh()
  #expect(ctrl.todayRows.map(\.id) == [other.id, task.id])
  #expect(CarPlayRowCopy.detail(for: ctrl.todayRows[1], nowMinutes: nil) == "About 30 min")

  _ = try await svc.startTask(id: task.id)
  try await ctrl.refresh()

  #expect(ctrl.todayRows.map(\.id) == [task.id, other.id])
  #expect(ctrl.todayRows[0].isStarted)
  #expect(CarPlayRowCopy.detail(for: ctrl.todayRows[0], nowMinutes: nil) == "Started · about 30 min")
}

@MainActor
@Test
func carPlayRowCopyReadsTheClock() {
  typealias Row = CarPlayTaskListController.Row
  let timed = Row(id: "1", title: "Timed", startMinutes: 585, endMinutes: 645)
  let range = lorvexClockRangeLabel(startMinutes: 585, endMinutes: 645)
  #expect(
    CarPlayRowCopy.detail(for: timed, nowMinutes: 600)
      == "Until \(lorvexClockTimeLabel(minutes: 645))")
  #expect(CarPlayRowCopy.detail(for: timed, nowMinutes: 700) == range)
  #expect(CarPlayRowCopy.detail(for: timed, nowMinutes: 500) == range)
  #expect(CarPlayRowCopy.detail(for: timed, nowMinutes: nil) == range)
  #expect(
    CarPlayRowCopy.detail(
      for: Row(id: "2", title: "Estimated", estimatedMinutes: 25), nowMinutes: 600)
      == "About 25 min")
  #expect(
    CarPlayRowCopy.detail(for: Row(id: "3", title: "Overdue", isOverdue: true), nowMinutes: 600)
      == "Overdue")
  #expect(
    CarPlayRowCopy.detail(for: Row(id: "4", title: "Started", isStarted: true), nowMinutes: 600)
      == "Started")
  #expect(CarPlayRowCopy.detail(for: Row(id: "5", title: "Plain"), nowMinutes: 600) == nil)
}
