import Foundation
import GRDB
import LorvexStore
import LorvexWorkflow
import XCTest

@testable import LorvexCore

/// Taking an occurrence of a repeating task out of its series withdraws the
/// occurrences generated after it. An occurrence somebody completed is a
/// record of work done, so a write that would withdraw one is refused whole
/// and changes nothing.
final class SeriesEndKeepsCompletedOccurrencesTests: XCTestCase {

  private func makeService() throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    return SwiftLorvexCoreService(
      store: try LorvexStore.openInMemory(
        schemaSQL: schemaSQL, migrations: try SwiftLorvexCoreService.resolveSchemaMigrations()))
  }

  /// What a write to the series may change on one occurrence.
  private struct Occurrence: Equatable {
    var status: String
    var hasCompletionTime: Bool
    var repeats: Bool
    var rollover: String
    var predecessor: String?
  }

  private func occurrence(_ service: SwiftLorvexCoreService, _ id: String) throws -> Occurrence {
    try service.read { db in
      let row = try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: """
            SELECT status, completed_at IS NOT NULL, recurrence IS NOT NULL,
                   recurrence_rollover_state, spawned_from
            FROM tasks WHERE id = ?
            """,
          arguments: [id]))
      return Occurrence(
        status: row[0], hasCompletionTime: row[1], repeats: row[2], rollover: row[3],
        predecessor: row[4])
    }
  }

  private func makeDailyTask(_ service: SwiftLorvexCoreService) async throws -> String {
    try await service.createTask(
      .init(
        title: "Water the plants", priority: .p3, dueDate: Date(),
        recurrence: TaskRecurrenceRule(freq: .daily))
    ).id
  }

  /// The occurrence generated from `id`.
  private func next(_ service: SwiftLorvexCoreService, after id: String) throws -> String {
    try service.read { db in
      try XCTUnwrap(
        String.fetchOne(db, sql: "SELECT id FROM tasks WHERE spawned_from = ?", arguments: [id]))
    }
  }

  /// The records queued for other devices and the change log entries: what a
  /// refused write must not add to.
  private func recordsWritten(_ service: SwiftLorvexCoreService) throws -> [Int] {
    let changes = try service.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog") ?? 0
    }
    return [try service.pendingOutbound().count, changes]
  }

  /// A series whose first occurrence is open again while the occurrence it
  /// once generated is completed: complete the first, reopen it (which
  /// withdraws the second), reopen the second by hand, and complete it.
  private func makeReopenedTaskWithACompletedNextOccurrence(
    _ service: SwiftLorvexCoreService
  ) async throws -> (first: String, second: String) {
    let first = try await makeDailyTask(service)
    _ = try await service.completeTask(id: first)
    let second = try next(service, after: first)
    _ = try await service.reopenTask(id: first)
    XCTAssertEqual(try occurrence(service, second).status, "cancelled")
    _ = try await service.reopenTask(id: second)
    _ = try await service.completeTask(id: second)
    XCTAssertEqual(try occurrence(service, first).status, "open")
    XCTAssertEqual(try occurrence(service, second).status, "completed")
    XCTAssertEqual(try occurrence(service, second).predecessor, first)
    return (first, second)
  }

  /// Asserts that turning the repeat off on `task` is refused because of the
  /// completed occurrence `blocker`.
  private func assertRepeatOffRefused(
    _ service: SwiftLorvexCoreService, on task: String, becauseOf blocker: String,
    file: StaticString = #filePath, line: UInt = #line
  ) async {
    do {
      _ = try await service.removeTaskRecurrence(taskID: task)
      XCTFail("turning the repeat off was accepted", file: file, line: line)
    } catch TaskLifecycleError.seriesEndBlockedByCompletedOccurrence(let taskId, let successorId) {
      XCTAssertEqual(taskId, task, file: file, line: line)
      XCTAssertEqual(successorId, blocker, file: file, line: line)
    } catch {
      XCTFail("unexpected error: \(error)", file: file, line: line)
    }
  }

  func testTurningTheRepeatOffIsRefusedWhenTheNextOccurrenceIsCompleted() async throws {
    let service = try makeService()
    let first = try await makeDailyTask(service)
    _ = try await service.completeTask(id: first)
    let second = try next(service, after: first)
    _ = try await service.completeTask(id: second)
    let third = try next(service, after: second)
    let before = try [first, second, third].map { try occurrence(service, $0) }
    let written = try recordsWritten(service)

    await assertRepeatOffRefused(service, on: first, becauseOf: second)

    XCTAssertEqual(try [first, second, third].map { try occurrence(service, $0) }, before)
    XCTAssertEqual(try recordsWritten(service), written)
    XCTAssertEqual(
      try occurrence(service, second),
      Occurrence(
        status: "completed", hasCompletionTime: true, repeats: true, rollover: "authorized",
        predecessor: first))
    XCTAssertEqual(try occurrence(service, third).status, "open")
  }

  func testTurningTheRepeatOffOnTheCurrentOccurrenceStillEndsTheSeries() async throws {
    let service = try makeService()
    let first = try await makeDailyTask(service)
    _ = try await service.completeTask(id: first)
    let second = try next(service, after: first)
    _ = try await service.completeTask(id: second)
    let third = try next(service, after: second)

    _ = try await service.removeTaskRecurrence(taskID: third)

    XCTAssertEqual(
      try occurrence(service, third),
      Occurrence(
        status: "open", hasCompletionTime: false, repeats: false, rollover: "none",
        predecessor: nil))
    XCTAssertEqual(try occurrence(service, second).status, "completed")
    XCTAssertEqual(try occurrence(service, second).rollover, "ended")
    XCTAssertEqual(try occurrence(service, first).status, "completed")
  }

  func testTurningTheRepeatOffPastASkippedOccurrenceWithdrawsTheOpenOne() async throws {
    let service = try makeService()
    let first = try await makeDailyTask(service)
    _ = try await service.completeTask(id: first)
    let second = try next(service, after: first)
    _ = try await service.cancelTask(id: second)
    let third = try next(service, after: second)
    XCTAssertEqual(try occurrence(service, third).status, "open")

    _ = try await service.removeTaskRecurrence(taskID: first)

    XCTAssertEqual(try occurrence(service, first).status, "completed")
    XCTAssertTrue(try occurrence(service, first).hasCompletionTime)
    XCTAssertFalse(try occurrence(service, first).repeats)
    XCTAssertEqual(try occurrence(service, second).status, "cancelled")
    XCTAssertEqual(try occurrence(service, third).status, "cancelled")
  }

  func testAfterTheSeriesEndedTheRepeatComesOffFromTheLatestOccurrenceBack() async throws {
    let service = try makeService()
    let first = try await makeDailyTask(service)
    _ = try await service.completeTask(id: first)
    let second = try next(service, after: first)
    _ = try await service.completeTask(id: second)
    let third = try next(service, after: second)
    _ = try await service.removeTaskRecurrence(taskID: third)

    // The series has no open occurrence left, and `second` is its latest.
    await assertRepeatOffRefused(service, on: first, becauseOf: second)

    _ = try await service.removeTaskRecurrence(taskID: second)
    _ = try await service.removeTaskRecurrence(taskID: first)
    for id in [first, second] {
      let done = try occurrence(service, id)
      XCTAssertEqual(done.status, "completed")
      XCTAssertTrue(done.hasCompletionTime)
      XCTAssertFalse(done.repeats)
      XCTAssertNil(done.predecessor)
    }
    XCTAssertEqual(try occurrence(service, third).status, "open")
  }

  func testACompletedOccurrencePastASkippedOneRefusesAndRestoresTheSkippedOne() async throws {
    let service = try makeService()
    let first = try await makeDailyTask(service)
    _ = try await service.completeTask(id: first)
    let second = try next(service, after: first)
    _ = try await service.cancelTask(id: second)
    let third = try next(service, after: second)
    _ = try await service.completeTask(id: third)
    let fourth = try next(service, after: third)
    let ids = [first, second, third, fourth]
    let before = try ids.map { try occurrence(service, $0) }
    let written = try recordsWritten(service)

    await assertRepeatOffRefused(service, on: first, becauseOf: third)
    XCTAssertEqual(try recordsWritten(service), written)

    // The skipped occurrence was written before the refusal; the rollback
    // puts back its record of the occurrence after it.
    XCTAssertEqual(try ids.map { try occurrence(service, $0) }, before)
    XCTAssertEqual(try occurrence(service, second).rollover, "authorized")
  }

  func testCancellingSeriesInABatchSkipsATaskWithACompletedLaterOccurrence() async throws {
    let service = try makeService()
    let (first, second) = try await makeReopenedTaskWithACompletedNextOccurrence(service)
    let other = try await service.createTask(title: "Buy soil", notes: "").id
    let before = try [first, second].map { try occurrence(service, $0) }

    let result = try await service.batchCancelTasks(ids: [first, other], cancelSeries: true)

    XCTAssertEqual(result.skipped, [first])
    XCTAssertEqual(result.cancelled.map(\.id), [other])
    XCTAssertEqual(try [first, second].map { try occurrence(service, $0) }, before)
  }
}
