import Foundation
import GRDB
import LorvexStore
import XCTest

@testable import LorvexCore

/// A recurring task's next occurrence is generated when the current one is
/// completed, and the generated row carries an instance key
/// (`<group id>:<canonical occurrence date>`) that the schema ties to the row's
/// group id and occurrence date. Editing the series from such a row, to end it
/// or to move its date, keeps those three columns consistent.
final class RecurringSuccessorEditTests: XCTestCase {
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

  /// A daily task completed once, so its generated next occurrence exists.
  /// Returns the generated occurrence's id.
  private func makeGeneratedOccurrence(_ service: SwiftLorvexCoreService) async throws -> String {
    let created = try await service.createTask(title: "Water the plants", notes: "")
    let parent = try await service.setTaskRecurrence(
      taskID: created.id, rule: TaskRecurrenceRule(freq: .daily, interval: 1))
    _ = try await service.completeTaskReturningTask(id: parent.id)
    return try service.read { db in
      try XCTUnwrap(
        String.fetchOne(
          db, sql: "SELECT recurrence_successor_id FROM tasks WHERE id = ?",
          arguments: [parent.id]))
    }
  }

  private struct RecurrenceColumns {
    var recurrence: String?
    var groupID: String?
    var occurrenceDate: String?
    var instanceKey: String?
    var spawnedFrom: String?
  }

  private func columns(
    _ service: SwiftLorvexCoreService, of id: String
  ) throws -> RecurrenceColumns {
    try service.read { db in
      let row = try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: """
            SELECT recurrence, recurrence_group_id, canonical_occurrence_date,
                   recurrence_instance_key, spawned_from
            FROM tasks WHERE id = ?
            """,
          arguments: [id]))
      return RecurrenceColumns(
        recurrence: row["recurrence"], groupID: row["recurrence_group_id"],
        occurrenceDate: row["canonical_occurrence_date"],
        instanceKey: row["recurrence_instance_key"], spawnedFrom: row["spawned_from"])
    }
  }

  func testAGeneratedOccurrenceCarriesAnInstanceKeyTiedToItsGroupAndDate() async throws {
    let service = try makeService()
    let id = try await makeGeneratedOccurrence(service)

    let stored = try columns(service, of: id)

    XCTAssertNotNil(stored.spawnedFrom)
    XCTAssertEqual(
      stored.instanceKey,
      "\(try XCTUnwrap(stored.groupID)):\(try XCTUnwrap(stored.occurrenceDate))")
  }

  func testRemovingTheRecurrenceOfAGeneratedOccurrenceEndsTheSeries() async throws {
    let service = try makeService()
    let id = try await makeGeneratedOccurrence(service)

    let updated = try await service.removeTaskRecurrence(taskID: id)

    XCTAssertNil(updated.recurrence)
    let stored = try columns(service, of: id)
    XCTAssertNil(stored.recurrence)
    XCTAssertNil(stored.groupID)
    XCTAssertNil(stored.occurrenceDate)
    XCTAssertNil(stored.instanceKey)
    XCTAssertNil(stored.spawnedFrom)
  }

  func testCancellingTheWholeSeriesFromAGeneratedOccurrenceSpawnsNoSuccessor() async throws {
    let service = try makeService()
    let id = try await makeGeneratedOccurrence(service)
    let openBefore = try await service.listTasks(
      status: "open", listID: nil, priority: nil, text: nil, limit: 50, offset: 0
    ).tasks.count

    for operation in RecurringTaskCancelScope.all.coreOperations {
      switch operation {
      case .removeRecurrence: _ = try await service.removeTaskRecurrence(taskID: id)
      case .cancelTask: _ = try await service.cancelTask(id: id)
      }
    }

    let task = try await service.loadTask(id: id)
    XCTAssertEqual(task.status, .cancelled)
    let openAfter = try await service.listTasks(
      status: "open", listID: nil, priority: nil, text: nil, limit: 50, offset: 0
    ).tasks.count
    XCTAssertEqual(openAfter, openBefore - 1)
  }

  func testMovingTheDueDateOfAGeneratedOccurrenceKeepsItsInstanceKeyConsistent() async throws {
    let service = try makeService()
    let id = try await makeGeneratedOccurrence(service)
    let before = try columns(service, of: id)
    let newDue = try XCTUnwrap(
      LorvexDateFormatters.ymdUTC.date(from: "2031-03-14"))

    _ = try await service.updateTask(TaskUpdateDraft(id: id, dueDate: .set(newDue)))

    let stored = try columns(service, of: id)
    XCTAssertEqual(stored.groupID, before.groupID)
    XCTAssertEqual(stored.occurrenceDate, "2031-03-14")
    XCTAssertEqual(
      stored.instanceKey,
      "\(try XCTUnwrap(stored.groupID)):2031-03-14")
    XCTAssertNotNil(stored.spawnedFrom)
  }
}
