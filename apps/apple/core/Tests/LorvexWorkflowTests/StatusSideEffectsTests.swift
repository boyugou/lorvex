import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexWorkflow

/// Parity port of `lorvex_workflow::status_side_effects` tests.
final class StatusSideEffectsTests: XCTestCase {
  private func tid(_ s: String) -> TaskId { TaskId(trusted: s) }

  private func insertTask(_ writer: any DatabaseWriter, id: String, status: String) throws {
    try writer.write { db in
      try db.execute(
        sql:
          "INSERT INTO tasks (id, title, status, version, created_at, updated_at, completed_at) "
          + "VALUES (?1, ?1, ?2, '0000000000000_0000_0000000000000000', "
          + "        '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', "
          + "        CASE WHEN ?2 = 'completed' THEN '2026-01-01T00:00:00Z' END)",
        arguments: [id, status])
    }
  }

  func testCompleteCancelsReminders() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTask(store.writer, id: "t1", status: "completed")
    try store.writer.write { db in
      try db.execute(
        sql:
          "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at) "
          + "VALUES ('r1', 't1', '2026-04-01T09:00:00Z', "
          + "        '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z')")
    }
    let result = try store.writer.write { db in
      try StatusSideEffects.applyStatusTransitionSideEffects(
        db, taskId: tid("t1"),
        oldStatus: .open, newStatus: .completed,
        now: "2026-03-26T10:00:00Z",
        reminderVersion: "0000000000000_0000_a0a0a0a0a0a0a0a0")
    }
    XCTAssertEqual(result.cancelledReminderIds, ["r1"])
    XCTAssertTrue(result.affectedDependentIds.isEmpty)
  }

  func testCancelRemovesDepsAndCancelsReminders() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTask(store.writer, id: "t1", status: "cancelled")
    try insertTask(store.writer, id: "t2", status: "open")
    try store.writer.write { db in
      try db.execute(
        sql:
          "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at) "
          + "VALUES ('t2', 't1', '0000000000000_0000_0000000000000000', "
          + "        '2026-01-01T00:00:00Z')")
    }
    let result = try store.writer.write { db in
      try StatusSideEffects.applyStatusTransitionSideEffects(
        db, taskId: tid("t1"),
        oldStatus: .open, newStatus: .cancelled,
        now: "2026-03-26T10:00:00Z",
        reminderVersion: "0000000000000_0000_a0a0a0a0a0a0a0a0")
    }
    XCTAssertEqual(result.affectedDependentIds, ["t2"])

    let depCount: Int? = try store.writer.read { db in
      try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM task_dependencies WHERE depends_on_task_id = 't1'")
    }
    XCTAssertEqual(depCount, 0)
  }

  func testReopenIsNoop() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTask(store.writer, id: "t1", status: "open")
    let result = try store.writer.write { db in
      try StatusSideEffects.applyStatusTransitionSideEffects(
        db, taskId: tid("t1"),
        oldStatus: .completed, newStatus: .open,
        now: "2026-03-26T10:00:00Z",
        reminderVersion: "0000000000000_0000_a0a0a0a0a0a0a0a0")
    }
    XCTAssertTrue(result.cancelledReminderIds.isEmpty)
    XCTAssertTrue(result.affectedDependentIds.isEmpty)
  }
}
