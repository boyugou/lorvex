import GRDB
import XCTest

@testable import LorvexCore

/// A completion-anchored repeat spawns its next occurrence INTERVAL units after
/// the completion day. Completing the occurrence that was just spawned, on the
/// same day, used to compute that same date again and fail on the series' unique
/// occurrence key with a raw SQLite error; the next occurrence now moves on by
/// another interval.
final class CompletionAnchoredSuccessorTests: XCTestCase {
  func testCompletingTheJustSpawnedOccurrenceTheSameDayAdvancesAnotherInterval() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let snapshot = try await service.loadToday()
    let today = try XCTUnwrap(snapshot.logicalDay)
    let task = try await service.createTask(title: "Water the plants", notes: "")
    _ = try await service.setTaskRecurrence(
      taskID: task.id,
      rule: TaskRecurrenceRule(freq: .weekly, interval: 4, anchor: .completion))

    _ = try await service.completeTask(id: task.id)
    let successorID = try XCTUnwrap(
      try service.read { db in
        try String.fetchOne(
          db, sql: "SELECT id FROM tasks WHERE title = 'Water the plants' AND id != ?",
          arguments: [task.id])
      })
    let firstDue = try XCTUnwrap(
      try service.read { db in
        try String.fetchOne(db, sql: "SELECT due_date FROM tasks WHERE id = ?", arguments: [successorID])
      })

    // The same day: completing the occurrence just spawned.
    _ = try await service.completeTask(id: successorID)
    let secondDue = try XCTUnwrap(
      try service.read { db in
        try String.fetchOne(
          db,
          sql: "SELECT due_date FROM tasks WHERE title = 'Water the plants' AND status = 'open'")
      })
    XCTAssertGreaterThan(secondDue, firstDue, "the next occurrence is after the one just completed")
    XCTAssertGreaterThan(firstDue, today)
  }
}
