import XCTest

@testable import LorvexCore

/// A batch lifecycle call over ids in every state: each tool says it skips what it cannot act on,
/// so one finished or missing id never aborts the rest. Completing a cancelled task used to throw
/// from inside the batch and roll back every other task with it.
final class BatchLifecycleMixedStatusTests: XCTestCase {
  private struct Fixture {
    let service: SwiftLorvexCoreService
    let open: String
    let started: String
    let someday: String
    let completed: String
    let cancelled: String
    let missing = "00000000-0000-7000-8000-00000000dead"

    var all: [String] { [open, started, someday, completed, cancelled, missing] }
  }

  private func fixture() async throws -> Fixture {
    let service = try SwiftLorvexCoreService.inMemory()
    let open = try await service.createTask(title: "open", notes: "").id
    let started = try await service.createTask(title: "started", notes: "").id
    let someday = try await service.createTask(title: "someday", notes: "").id
    let completed = try await service.createTask(title: "completed", notes: "").id
    let cancelled = try await service.createTask(title: "cancelled", notes: "").id
    _ = try await service.startTask(id: started)
    _ = try await service.markTaskSomeday(id: someday)
    _ = try await service.completeTask(id: completed)
    _ = try await service.cancelTask(id: cancelled)
    return Fixture(
      service: service, open: open, started: started, someday: someday, completed: completed,
      cancelled: cancelled)
  }

  func testBatchCompleteSkipsFinishedAndMissingTasksAndCompletesTheRest() async throws {
    let f = try await fixture()
    let result = try await f.service.batchCompleteTasks(ids: f.all)

    XCTAssertEqual(Set(result.changedIDs), [f.open, f.started, f.someday])
    XCTAssertEqual(Set(result.skipped), [f.completed, f.cancelled, f.missing])
    let cancelled = try await f.service.loadTask(id: f.cancelled)
    XCTAssertEqual(cancelled.status, .cancelled)
    for id in [f.open, f.started, f.someday] {
      let task = try await f.service.loadTask(id: id)
      XCTAssertEqual(task.status, .completed, task.title)
    }
  }

  func testBatchReopenSkipsOpenAndMissingTasks() async throws {
    let f = try await fixture()
    let result = try await f.service.batchReopenTasks(ids: f.all)

    XCTAssertEqual(Set(result.changedIDs), [f.started, f.someday, f.completed, f.cancelled])
    XCTAssertEqual(Set(result.skipped), [f.open, f.missing])
  }

  func testBatchReopenSkipsARepeatWhoseNextOccurrenceMovedOnAndReopensTheRest() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let repeating = try await service.createTask(title: "Water the plants", notes: "")
    _ = try await service.setTaskRecurrence(
      taskID: repeating.id, rule: TaskRecurrenceRule(freq: .daily))
    _ = try await service.completeTask(id: repeating.id)
    let successorID = try XCTUnwrap(
      try service.read { db in
        try String.fetchOne(
          db, sql: "SELECT id FROM tasks WHERE title = 'Water the plants' AND id != ?",
          arguments: [repeating.id])
      })
    // The next occurrence is finished too, so reopening the first one would fork the series.
    _ = try await service.completeTask(id: successorID)
    let plain = try await service.createTask(title: "Plain", notes: "")
    _ = try await service.completeTask(id: plain.id)

    let result = try await service.batchReopenTasks(ids: [repeating.id, plain.id])

    XCTAssertEqual(result.changedIDs, [plain.id])
    XCTAssertEqual(result.skipped, [repeating.id])
    let stillDone = try await service.loadTask(id: repeating.id)
    XCTAssertEqual(stillDone.status, .completed)
    let reopened = try await service.loadTask(id: plain.id)
    XCTAssertEqual(reopened.status, .open)
  }

  func testBatchCompleteSkipsARepeatWhoseNextOccurrenceMovedOnAndCompletesTheRest() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let repeating = try await service.createTask(title: "Water the plants", notes: "")
    _ = try await service.setTaskRecurrence(
      taskID: repeating.id, rule: TaskRecurrenceRule(freq: .daily))
    _ = try await service.completeTask(id: repeating.id)
    let successorID = try XCTUnwrap(
      try service.read { db in
        try String.fetchOne(
          db, sql: "SELECT id FROM tasks WHERE title = 'Water the plants' AND id != ?",
          arguments: [repeating.id])
      })
    _ = try await service.reopenTaskReturningTask(id: repeating.id)
    // Another device finished the reserved next occurrence while this one was open again.
    try service.write { db in
      try db.execute(
        sql: "UPDATE tasks SET status = 'completed', completed_at = '2026-04-02T10:00:00Z' WHERE id = ?",
        arguments: [successorID])
    }
    let plain = try await service.createTask(title: "Plain", notes: "")

    let result = try await service.batchCompleteTasks(ids: [repeating.id, plain.id])

    XCTAssertEqual(result.changedIDs, [plain.id])
    XCTAssertEqual(result.skipped, [repeating.id])
    let stillOpen = try await service.loadTask(id: repeating.id)
    XCTAssertEqual(stillOpen.status, .open)
  }

  func testBatchDeferSkipsFinishedAndMissingTasks() async throws {
    let f = try await fixture()
    let result = try await f.service.batchDeferTasks(
      ids: f.all, until: Date().addingTimeInterval(3 * 86_400), reason: nil, note: nil)

    XCTAssertEqual(Set(result.changedIDs), [f.open, f.started, f.someday])
    XCTAssertEqual(Set(result.skipped), [f.completed, f.cancelled, f.missing])
  }

  func testBatchCancelSkipsFinishedAndMissingTasks() async throws {
    let f = try await fixture()
    let result = try await f.service.batchCancelTasks(ids: f.all, cancelSeries: false)

    XCTAssertEqual(Set(result.cancelled.map(\.id)), [f.open, f.started, f.someday])
    XCTAssertEqual(Set(result.skipped), [f.completed, f.cancelled, f.missing])
  }
}
