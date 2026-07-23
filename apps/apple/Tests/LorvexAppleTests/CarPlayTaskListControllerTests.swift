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
  #expect(ctrl.focusRows.isEmpty)
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
func carPlayControllerFocusSectionReflectsFocusPlan() async throws {
  let svc = try makeInMemoryCore()
  let focusTask = try await seedTask(svc, title: "Focus Task")
  try await seedTask(svc, title: "Other")
  _ = try await svc.setCurrentFocus(
    date: try await logicalDay(svc),
    taskIDs: [focusTask.id],
    briefing: nil,
    timezone: TimeZone.current.identifier
  )
  let ctrl = CarPlayTaskListController(core: svc)
  try await ctrl.refresh()
  #expect(ctrl.focusRows.count == 1)
  #expect(ctrl.focusRows[0].id == focusTask.id)
  #expect(ctrl.focusRows[0].isFocus == true)
}

@MainActor
@Test
func carPlayControllerLoadsFocusTasksOutsideFirstOpenTaskPage() async throws {
  let svc = try makeInMemoryCore()
  for index in 0..<100 {
    try await seedTask(svc, title: "Filler \(index)")
  }
  let offscreenFocusTask = try await seedTask(svc, title: "Offscreen Focus")

  // The premise needs the focus task outside the first open page. The
  // canonical sort breaks priority/due ties by id (a fresh UUID may land
  // anywhere), so demote it to P3 — every P2 filler then pages ahead of it.
  _ = try await svc.updateTask(
    TaskUpdateDraft(id: offscreenFocusTask.id, priority: .p3))
  let firstPage = try await svc.listTasks(
    status: LorvexTask.Status.open.rawValue,
    listID: nil,
    priority: nil,
    text: nil,
    limit: 100,
    offset: 0
  )
  #expect(!firstPage.tasks.contains { $0.id == offscreenFocusTask.id })

  _ = try await svc.setCurrentFocus(
    date: try await logicalDay(svc),
    taskIDs: [offscreenFocusTask.id],
    briefing: nil,
    timezone: TimeZone.current.identifier
  )

  let ctrl = CarPlayTaskListController(core: svc)
  try await ctrl.refresh()

  #expect(ctrl.focusRows == [
    CarPlayTaskListController.Row(
      id: offscreenFocusTask.id,
      title: offscreenFocusTask.title,
      isFocus: true
    )
  ])
  #expect(!ctrl.todayRows.contains { $0.id == offscreenFocusTask.id })
}

@MainActor
@Test
func carPlayControllerFocusTasksNotDoubleCountedInToday() async throws {
  let svc = try makeInMemoryCore()
  let shared = try await seedTask(svc, title: "Shared Task")
  _ = try await svc.setCurrentFocus(
    date: try await logicalDay(svc),
    taskIDs: [shared.id],
    briefing: nil,
    timezone: TimeZone.current.identifier
  )
  let ctrl = CarPlayTaskListController(core: svc)
  try await ctrl.refresh()
  #expect(ctrl.focusRows.count == 1)
  #expect(ctrl.todayRows.isEmpty)
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
func carPlayControllerReadsUncappedTodayPoolWithoutLoadTodayOrBroadOpenQuery() async throws {
  let svc = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  svc.loadTodayError = .unsupportedOperation("loadToday must not feed CarPlay task rows")
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
func carPlayControllerNoFocusPlanProducesEmptyFocusRows() async throws {
  let svc = try makeInMemoryCore()
  try await seedTask(svc, title: "Task")
  // No focus plan set — loadCurrentFocus returns nil
  let ctrl = CarPlayTaskListController(core: svc)
  try await ctrl.refresh()
  #expect(ctrl.focusRows.isEmpty)
  #expect(ctrl.todayRows.count == 1)
}

@MainActor
@Test
func carPlayControllerDriverSafeErrorMessageDoesNotExposeRawError() {
  let message = CarPlayTaskListController.driverSafeErrorMessage(
    for: LorvexCoreError.unsupportedOperation("SQLite database is locked at /private/tmp/lorvex.db")
  )

  #expect(message == "Couldn't load tasks — tap to retry.")
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

@MainActor
@Test
func carPlayControllerRemoveFromFocusMovesTaskBackToToday() async throws {
  let svc = try makeInMemoryCore()
  let focusX = try await seedTask(svc, title: "Focus X")
  _ = try await svc.setCurrentFocus(
    date: try await logicalDay(svc),
    taskIDs: [focusX.id],
    briefing: nil,
    timezone: TimeZone.current.identifier
  )
  let ctrl = CarPlayTaskListController(core: svc)
  try await ctrl.refresh()
  #expect(ctrl.focusRows.map(\.id) == [focusX.id])
  #expect(ctrl.todayRows.isEmpty)

  try await ctrl.removeFromFocus(id: focusX.id)

  // Un-focusing only drops the Focus membership; the still-open, still-due
  // task reappears under Today rather than being completed or cancelled.
  #expect(ctrl.focusRows.isEmpty)
  #expect(ctrl.todayRows.map(\.id) == [focusX.id])
}
