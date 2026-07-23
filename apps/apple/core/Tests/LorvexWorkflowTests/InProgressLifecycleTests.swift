import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexWorkflow

/// Pins the `in_progress` status transition matrix at the workflow layer:
/// start (open → in_progress), pause (in_progress → open, leaving no residue),
/// the terminal replacements, the implicit-pause-on-someday, reopen never
/// restoring in_progress, the dependency-blocked start, and defer keeping the
/// status. The service/MCP happy paths and recurrence-successor-always-open are
/// covered in the app package's service tests.
final class InProgressLifecycleTests: XCTestCase {
  private let v = "1711234567890_0001_a1b2c3d4a1b2c3d4"
  private let reminderV = "0000000000000_0000_a0a0a0a0a0a0a0a0"

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

  private func addDependency(_ writer: any DatabaseWriter, task: String, dependsOn: String) throws {
    try writer.write { db in
      try db.execute(
        sql:
          "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at) "
          + "VALUES (?1, ?2, ?3, '2026-01-01T00:00:00Z')",
        arguments: [task, dependsOn, v])
    }
  }

  private func statusRow(_ store: LorvexStore, _ id: String) throws -> Row {
    try store.writer.read { db in
      try Row.fetchOne(
        db,
        sql:
          "SELECT status, completed_at, planned_date, last_deferred_at, defer_count "
          + "FROM tasks WHERE id = ?1",
        arguments: [id])
    }!
  }

  private func transition(
    _ store: LorvexStore, _ id: String, _ from: TaskStatus, _ to: TaskStatus
  ) throws {
    _ = try store.writer.write { db in
      try LifecycleTransitions.applyLifecycleTransition(
        db, taskId: tid(id), oldStatus: from, newStatus: to,
        now: "2026-03-26T10:00:00Z", reminderVersion: reminderV)
    }
  }

  /// open → in_progress ("start"): the marker goes on and planning metadata is
  /// left untouched (start is a metadata no-op).
  func testStartLeavesPlanningMetadataIntact() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTask(store.writer, id: "t1", status: "open")
    try store.writer.write { db in
      try db.execute(
        sql: "UPDATE tasks SET planned_date = '2026-03-01', defer_count = 2 WHERE id = 't1'")
    }
    try transition(store, "t1", .open, .inProgress)
    let row = try statusRow(store, "t1")
    XCTAssertEqual(row[0] as String?, "in_progress")
    XCTAssertNil(row[1] as String?, "completed_at stays null")
    XCTAssertEqual(row[2] as String?, "2026-03-01", "planned_date preserved")
    XCTAssertEqual(row[4] as Int64?, 2, "defer_count preserved")
  }

  /// in_progress → open ("pause" / un-start): the mis-click recovery leaves no
  /// residue — unlike a reopen from terminal, it must NOT wipe planned_date or
  /// reset defer_count. Start then pause is a metadata round-trip no-op.
  func testPauseLeavesNoResidue() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTask(store.writer, id: "t1", status: "in_progress")
    try store.writer.write { db in
      try db.execute(
        sql:
          "UPDATE tasks SET planned_date = '2026-03-01', defer_count = 2, "
          + "last_deferred_at = '2026-02-28T00:00:00Z' WHERE id = 't1'")
    }
    try transition(store, "t1", .inProgress, .open)
    let row = try statusRow(store, "t1")
    XCTAssertEqual(row[0] as String?, "open")
    XCTAssertEqual(row[2] as String?, "2026-03-01", "planned_date preserved through pause")
    XCTAssertEqual(row[3] as String?, "2026-02-28T00:00:00Z", "last_deferred_at preserved")
    XCTAssertEqual(row[4] as Int64?, 2, "defer_count NOT reset by pause")
  }

  /// in_progress → completed replaces the status; the marker vanishes and
  /// completed_at is stamped.
  func testCompleteFromInProgress() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTask(store.writer, id: "t1", status: "in_progress")
    let result = try store.writer.write { db in
      try LifecycleStatus.completeTask(
        db, taskId: tid("t1"), now: "2026-03-26T10:00:00Z", reminderVersion: reminderV)
    }
    XCTAssertTrue(result.updated)
    let row = try statusRow(store, "t1")
    XCTAssertEqual(row[0] as String?, "completed")
    XCTAssertNotNil(row[1] as String?, "completed_at stamped")
  }

  /// in_progress → cancelled replaces the status; the marker vanishes.
  func testCancelFromInProgress() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTask(store.writer, id: "t1", status: "in_progress")
    let result = try store.writer.write { db in
      try LifecycleStatus.cancelTask(
        db, taskId: tid("t1"), now: "2026-03-26T10:00:00Z", reminderVersion: reminderV)
    }
    XCTAssertTrue(result.updated)
    XCTAssertEqual(try statusRow(store, "t1")[0] as String?, "cancelled")
  }

  /// in_progress → someday is an implicit pause: allowed (not an error), status
  /// becomes someday, and no reopen-style reset fires.
  func testInProgressToSomedayImplicitPause() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTask(store.writer, id: "t1", status: "in_progress")
    try store.writer.write { db in
      try db.execute(sql: "UPDATE tasks SET planned_date = '2026-03-01' WHERE id = 't1'")
    }
    let rows = try store.writer.write { db in
      try LifecycleWriteStatus.writeStatusAndMetadata(
        db, taskId: tid("t1"), oldStatus: .inProgress, newStatus: .someday,
        now: "2026-03-26T10:00:00Z", version: v)
    }
    XCTAssertEqual(rows, 1)
    let row = try statusRow(store, "t1")
    XCTAssertEqual(row[0] as String?, "someday")
    XCTAssertEqual(row[2] as String?, "2026-03-01", "someday does not clear planned_date")
  }

  /// Reopen from a terminal status returns the task to `open`, never to
  /// `in_progress` — resuming a completed started task means starting it again.
  func testReopenNeverRestoresInProgress() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTask(store.writer, id: "t1", status: "in_progress")
    _ = try store.writer.write { db in
      try LifecycleStatus.completeTask(
        db, taskId: tid("t1"), now: "2026-03-26T10:00:00Z", reminderVersion: reminderV)
    }
    let reopen = try store.writer.write { db in
      try LifecycleStatus.reopenTask(
        db, taskId: tid("t1"), now: "2026-03-27T10:00:00Z",
        reminderVersion: "0000000000000_0001_a0a0a0a0a0a0a0a0")
    }
    XCTAssertTrue(reopen.updated)
    XCTAssertEqual(try statusRow(store, "t1")[0] as String?, "open")
  }

  /// Starting a task with an unfinished dependency is rejected with a typed
  /// validation error naming the blocker id; no force-override exists.
  func testStartRejectedWhenDependencyUnfinished() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTask(store.writer, id: "t1", status: "open")
    try insertTask(store.writer, id: "blocker2", status: "open")
    try addDependency(store.writer, task: "t1", dependsOn: "blocker2")
    XCTAssertThrowsError(try transition(store, "t1", .open, .inProgress)) { error in
      guard case StoreError.validation(let message) = error else {
        return XCTFail("expected StoreError.validation, got \(error)")
      }
      XCTAssertTrue(message.contains("blocker2"), "error names the blocker: \(message)")
    }
    XCTAssertEqual(try statusRow(store, "t1")[0] as String?, "open", "start did not apply")
  }

  /// A completed blocker no longer blocks: the start succeeds.
  func testStartAllowedWhenBlockerCompleted() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTask(store.writer, id: "t1", status: "open")
    try insertTask(store.writer, id: "b2", status: "completed")
    try addDependency(store.writer, task: "t1", dependsOn: "b2")
    XCTAssertNoThrow(try transition(store, "t1", .open, .inProgress))
    XCTAssertEqual(try statusRow(store, "t1")[0] as String?, "in_progress")
  }

  /// A cancelled blocker (won't happen) also unblocks the start.
  func testStartAllowedWhenBlockerCancelled() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTask(store.writer, id: "t1", status: "open")
    try insertTask(store.writer, id: "b2", status: "cancelled")
    try addDependency(store.writer, task: "t1", dependsOn: "b2")
    XCTAssertNoThrow(try transition(store, "t1", .open, .inProgress))
    XCTAssertEqual(try statusRow(store, "t1")[0] as String?, "in_progress")
  }

  /// An in_progress blocker still blocks (it is not done): start is rejected.
  func testStartRejectedWhenBlockerInProgress() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTask(store.writer, id: "t1", status: "open")
    try insertTask(store.writer, id: "b2", status: "in_progress")
    try addDependency(store.writer, task: "t1", dependsOn: "b2")
    XCTAssertThrowsError(try transition(store, "t1", .open, .inProgress))
  }

  /// Deferring an in_progress task leaves the status untouched (defer only moves
  /// planned_date and bumps defer_count).
  func testDeferKeepsInProgressStatus() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTask(store.writer, id: "t1", status: "in_progress")
    let result = try store.writer.write { db in
      try TaskDeferral.deferTask(
        db, taskId: tid("t1"),
        patch: TaskDeferral.DeferralPatch(plannedDate: "2026-04-01"),
        version: v, now: "2026-03-26T10:00:00Z",
        nextReminderVersion: { self.reminderV })
    }
    XCTAssertTrue(result.updated)
    let row = try statusRow(store, "t1")
    XCTAssertEqual(row[0] as String?, "in_progress", "defer keeps in_progress")
    XCTAssertEqual(row[2] as String?, "2026-04-01")
    XCTAssertEqual(row[4] as Int64?, 1, "defer_count bumped")
  }
}
