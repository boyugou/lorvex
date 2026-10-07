import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

// Dropping a task on a day column's time axis or all-day strip, and dragging a
// timed block, plan the task through `AppStore.planTasks`.

/// Polls `condition` for up to three seconds. An undo or redo runs its writes in
/// a task of its own, so a test waits for the result rather than for a return.
@MainActor
private func waitUntil(_ condition: () async throws -> Bool) async throws -> Bool {
  for _ in 0..<60 {
    if try await condition() { return true }
    try await Task.sleep(for: .milliseconds(50))
  }
  return false
}

/// A local instant on the day after today, which is how the grid names a column.
private func tomorrow() throws -> Date {
  try #require(Calendar.current.date(byAdding: .day, value: 1, to: Date()))
}

private func storedDay(of date: Date) -> String {
  LorvexDateFormatters.ymdUTC.string(from: PlannedDayBridge.storageDate(forLocalInstant: date))
}

private func day(of task: LorvexTask) -> String? {
  task.plannedDate.map(LorvexDateFormatters.ymdUTC.string(from:))
}

@MainActor
private func makeStore(
  estimate: Int? = nil
) async throws -> (store: AppStore, core: any LorvexCoreServicing, taskID: LorvexTask.ID) {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()
  let task = try await core.createTask(title: "Write the launch note", notes: "")
  if let estimate {
    _ = try await core.updateTask(TaskUpdateDraft(id: task.id, estimatedMinutes: .set(estimate)))
  }
  return (store, core, task.id)
}

@MainActor
@Test
func aTaskDroppedOnATimeTakesThatStartAndItsEstimate() async throws {
  let (store, core, id) = try await makeStore(estimate: 90)
  let column = try tomorrow()

  await store.planTasks(ids: [id], on: column, time: .start(14 * 60))

  let task = try await core.loadTask(id: id)
  #expect(day(of: task) == storedDay(of: column))
  #expect(task.plannedTime == 14 * 60..<15 * 60 + 30)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func aTaskWithNoEstimateTakesHalfAnHour() async throws {
  let (store, core, id) = try await makeStore()

  await store.planTasks(ids: [id], on: try tomorrow(), time: .start(10 * 60))

  #expect(try await core.loadTask(id: id).plannedTime == 10 * 60..<10 * 60 + 30)
}

@MainActor
@Test
func aTimedTaskMovedToANewStartKeepsItsLength() async throws {
  let (store, core, id) = try await makeStore(estimate: 120)
  let column = try tomorrow()
  await store.planTasks(ids: [id], on: column, time: .start(9 * 60))
  _ = try await core.updateTask(TaskUpdateDraft(id: id, plannedTime: .set(9 * 60..<9 * 60 + 45)))

  await store.planTasks(ids: [id], on: column, time: .start(11 * 60 + 15))

  #expect(try await core.loadTask(id: id).plannedTime == 11 * 60 + 15..<12 * 60)
}

@MainActor
@Test
func aTimedTaskDroppedOnTheAllDayStripKeepsTheDayAndLosesTheTime() async throws {
  let (store, core, id) = try await makeStore()
  let column = try tomorrow()
  await store.planTasks(ids: [id], on: column, time: .start(9 * 60))

  await store.planTasks(ids: [id], on: column, time: .dayOnly)

  let task = try await core.loadTask(id: id)
  #expect(day(of: task) == storedDay(of: column))
  #expect(task.plannedTime == nil)
}

@MainActor
@Test
func aTaskDroppedOnAnotherDaysStripMovesDaysWithoutATime() async throws {
  let (store, core, id) = try await makeStore()
  await store.planTasks(ids: [id], on: try tomorrow(), time: .start(9 * 60))
  let later = try #require(Calendar.current.date(byAdding: .day, value: 3, to: Date()))

  await store.planTasks(ids: [id], on: later, time: .dayOnly)

  let task = try await core.loadTask(id: id)
  #expect(day(of: task) == storedDay(of: later))
  #expect(task.plannedTime == nil)
}

@MainActor
@Test
func aTimedTaskMovedWithUnchangedTimeKeepsItsTimeOnTheNewDay() async throws {
  let (store, core, id) = try await makeStore(estimate: 60)
  await store.planTasks(ids: [id], on: try tomorrow(), time: .start(14 * 60))
  let later = try #require(Calendar.current.date(byAdding: .day, value: 3, to: Date()))

  await store.planTasks(ids: [id], on: later, time: .unchanged)

  let task = try await core.loadTask(id: id)
  #expect(day(of: task) == storedDay(of: later))
  #expect(task.plannedTime == 14 * 60..<15 * 60)
}

@MainActor
@Test
func anUntimedTaskMovedWithUnchangedTimeStaysUntimed() async throws {
  let (store, core, id) = try await makeStore()
  let column = try tomorrow()
  await store.planTasks(ids: [id], on: column, time: .dayOnly)

  let later = try #require(Calendar.current.date(byAdding: .day, value: 2, to: Date()))
  await store.planTasks(ids: [id], on: later, time: .unchanged)

  let task = try await core.loadTask(id: id)
  #expect(day(of: task) == storedDay(of: later))
  #expect(task.plannedTime == nil)
}

@MainActor
@Test
func severalDroppedTasksStackFromTheDropMinuteInTheOrderGiven() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()
  let first = try await core.createTask(title: "First", notes: "")
  let second = try await core.createTask(title: "Second", notes: "")
  _ = try await core.updateTask(TaskUpdateDraft(id: first.id, estimatedMinutes: .set(45)))

  await store.planTasks(ids: [first.id, second.id], on: try tomorrow(), time: .start(10 * 60))

  #expect(try await core.loadTask(id: first.id).plannedTime == 10 * 60..<10 * 60 + 45)
  #expect(try await core.loadTask(id: second.id).plannedTime == 10 * 60 + 45..<11 * 60 + 15)
}

@MainActor
@Test
func aDropThatChangesNothingWritesNothingAndRegistersNoUndo() async throws {
  let (store, core, id) = try await makeStore()
  let column = try tomorrow()
  await store.planTasks(ids: [id], on: column, time: .start(9 * 60))
  let undoManager = UndoManager()

  await store.planTasks(ids: [id], on: column, time: .start(9 * 60), undoManager: undoManager)

  #expect(!undoManager.canUndo)
  #expect(try await core.loadTask(id: id).plannedTime == 9 * 60..<9 * 60 + 30)
}

@MainActor
@Test
func aFinishedTaskKeepsItsDayAndTime() async throws {
  let (store, core, id) = try await makeStore()
  let column = try tomorrow()
  await store.planTasks(ids: [id], on: column, time: .start(9 * 60))
  _ = try await core.completeTask(id: id)
  let later = try #require(Calendar.current.date(byAdding: .day, value: 4, to: Date()))

  await store.planTasks(ids: [id], on: later, time: .start(16 * 60))

  let task = try await core.loadTask(id: id)
  #expect(day(of: task) == storedDay(of: column))
  #expect(task.plannedTime == 9 * 60..<9 * 60 + 30)
}

@MainActor
@Test
func aTaskThatNoLongerExistsIsSkippedWithoutAnError() async throws {
  let (store, core, id) = try await makeStore()

  await store.planTasks(ids: ["gone", id], on: try tomorrow(), time: .start(9 * 60))

  #expect(store.errorMessage == nil)
  #expect(try await core.loadTask(id: id).plannedTime == 9 * 60..<9 * 60 + 30)
}

@MainActor
@Test
func aPlanChangeIsUndoneAndRedoneAndNamedInTheEditMenu() async throws {
  let (store, core, id) = try await makeStore()
  let before = try await core.loadTask(id: id)
  let column = try tomorrow()
  let undoManager = UndoManager()
  undoManager.groupsByEvent = false

  undoManager.beginUndoGrouping()
  await store.planTasks(ids: [id], on: column, time: .start(13 * 60), undoManager: undoManager)
  undoManager.endUndoGrouping()

  #expect(undoManager.canUndo)
  #expect(undoManager.undoActionName == AppStore.planTaskTitle)
  #expect(try await core.loadTask(id: id).plannedTime == 13 * 60..<13 * 60 + 30)

  undoManager.undo()
  #expect(
    try await waitUntil {
      let task = try await core.loadTask(id: id)
      return task.plannedDate == before.plannedDate && task.plannedTime == before.plannedTime
    })
  #expect(undoManager.canRedo)
  #expect(undoManager.redoActionName == AppStore.planTaskTitle)

  undoManager.redo()
  #expect(
    try await waitUntil {
      try await core.loadTask(id: id).plannedTime == 13 * 60..<13 * 60 + 30
    })
  #expect(undoManager.canUndo)
}

@MainActor
@Test
func undoingADropOfSeveralTasksRestoresEachOnesOwnDayAndTime() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()
  let timed = try await core.createTask(title: "Timed", notes: "")
  let loose = try await core.createTask(title: "Loose", notes: "")
  let original = try #require(LorvexDateFormatters.ymdUTC.date(from: "2026-03-02"))
  _ = try await core.updateTask(
    TaskUpdateDraft(id: timed.id, plannedDate: .set(original), plannedTime: .set(8 * 60..<9 * 60)))
  let undoManager = UndoManager()
  undoManager.groupsByEvent = false

  undoManager.beginUndoGrouping()
  await store.planTasks(
    ids: [timed.id, loose.id], on: try tomorrow(), time: .start(15 * 60), undoManager: undoManager)
  undoManager.endUndoGrouping()
  undoManager.undo()

  #expect(
    try await waitUntil {
      let restored = try await core.loadTask(id: timed.id)
      let cleared = try await core.loadTask(id: loose.id)
      return restored.plannedDate == original && restored.plannedTime == 8 * 60..<9 * 60
        && cleared.plannedDate == nil && cleared.plannedTime == nil
    })
}

@MainActor
@Test
func theSelectedTasksDetailAdoptsANewPlan() async throws {
  let (store, _, id) = try await makeStore()
  store.selectTaskFromList(id)
  await store.loadSelectedTaskDetail()

  await store.planTasks(ids: [id], on: try tomorrow(), time: .start(16 * 60))

  #expect(store.taskDetailPlannedTime == 16 * 60..<16 * 60 + 30)
  #expect(store.taskDetailHasPlannedDate)
}
