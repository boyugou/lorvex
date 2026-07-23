import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexWorkflow

/// Parity port of `lorvex_workflow::lifecycle::tests::primitives` —
/// `complete_task` / `cancel_task` / `reopen_task` /
/// `append_to_task_body` / reminder LWW-trim behavior.
///
/// Tests that exercise spawn-successor or cancel-recurring-successors
/// indirectly through a recurring task are deferred to the next port
/// slice — see `LifecycleTransitions` notes in `PORT_STATUS.md`.
final class LifecyclePrimitivesTests: XCTestCase {
  private let testVersion = "1711234567890_0001_a1b2c3d4a1b2c3d4"

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

  private func insertRecurringTask(
    _ writer: any DatabaseWriter, id: String, status: String,
    groupId: String, due: String
  ) throws {
    try writer.write { db in
      try db.execute(
        sql:
          "INSERT INTO tasks (id, title, status, due_date, canonical_occurrence_date, "
          + " recurrence, recurrence_group_id, recurrence_rollover_state, "
          + " version, created_at, updated_at, completed_at) "
          + "VALUES (?1, ?1, ?2, ?3, ?3, '{\"FREQ\":\"DAILY\"}', ?4, "
          + "        CASE WHEN ?2 IN ('completed', 'cancelled') THEN 'ended' ELSE 'none' END, "
          + "        '0000000000000_0000_0000000000000000', "
          + "        '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', "
          + "        CASE WHEN ?2 = 'completed' THEN '2026-01-01T00:00:00Z' END)",
        arguments: [id, status, due, groupId])
    }
  }

  // MARK: - body

  func testAppendToTaskBodyOnEmptyBody() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTask(store.writer, id: "t1", status: "open")
    let result = try store.writer.write { db in
      try LifecycleBody.appendToTaskBody(
        db, taskId: tid("t1"), text: "hello world",
        version: testVersion, now: "2026-03-26T10:00:00Z")
    }
    XCTAssertEqual(result, "hello world")
    let body: String? = try store.writer.read { db in
      try String.fetchOne(db, sql: "SELECT body FROM tasks WHERE id = 't1'")
    }
    XCTAssertEqual(body, "hello world")
  }

  func testAppendToTaskBodyOnExistingBody() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTask(store.writer, id: "t1", status: "open")
    try store.writer.write { db in
      try db.execute(
        sql: "UPDATE tasks SET body = 'existing notes' WHERE id = 't1'")
    }
    let result = try store.writer.write { db in
      try LifecycleBody.appendToTaskBody(
        db, taskId: tid("t1"), text: "new note",
        version: testVersion, now: "2026-03-26T10:00:00Z")
    }
    XCTAssertEqual(result, "existing notes\n\nnew note")
  }

  func testAppendToTaskBodyOnNullBody() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTask(store.writer, id: "t1", status: "open")
    let result = try store.writer.write { db in
      try LifecycleBody.appendToTaskBody(
        db, taskId: tid("t1"), text: "first note",
        version: testVersion, now: "2026-03-26T10:00:00Z")
    }
    XCTAssertEqual(result, "first note")
  }

  func testAppendToTaskBodyUpdatesTimestampAndVersion() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTask(store.writer, id: "t1", status: "open")
    let now = "2026-04-01T12:00:00Z"
    _ = try store.writer.write { db in
      try LifecycleBody.appendToTaskBody(
        db, taskId: tid("t1"), text: "note",
        version: testVersion, now: now)
    }
    let row = try store.writer.read { db in
      try Row.fetchOne(
        db, sql: "SELECT updated_at, version FROM tasks WHERE id = 't1'")
    }
    XCTAssertEqual(row?[0] as String?, now)
    XCTAssertEqual(row?[1] as String?, testVersion)
  }

  func testAppendToTaskBodyRejectsCombinedOverCap() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTask(store.writer, id: "t1", status: "open")
    let now = "2026-04-01T12:00:00Z"
    let nearCap = String(repeating: "a", count: ValidationLimits.maxBodyLength - 10)
    _ = try store.writer.write { db in
      try LifecycleBody.appendToTaskBody(
        db, taskId: tid("t1"), text: nearCap,
        version: testVersion, now: now)
    }
    XCTAssertThrowsError(
      try store.writer.write { db in
        try LifecycleBody.appendToTaskBody(
          db, taskId: tid("t1"),
          text: String(repeating: "b", count: 20),
          version: testVersion, now: now)
      }
    ) { error in
      guard case StoreError.validation(let msg) = error else {
        XCTFail("expected validation error, got \(error)")
        return
      }
      XCTAssertTrue(msg.contains("body"))
    }
  }

  func testAppendToTaskBodyRejectsStaleVersion() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTask(store.writer, id: "t1", status: "open")
    let newer = "9999913599999_0000_ffffffffffffffff"
    try store.writer.write { db in
      try db.execute(
        sql: "UPDATE tasks SET body = 'remote body', version = ?1 WHERE id = 't1'",
        arguments: [newer])
    }
    XCTAssertThrowsError(
      try store.writer.write { db in
        try LifecycleBody.appendToTaskBody(
          db, taskId: tid("t1"), text: "stale local note",
          version: testVersion, now: "2026-04-01T12:00:00Z")
      }
    ) { error in
      XCTAssertEqual(
        error as? StoreError, .staleVersion(entity: "task", id: "t1"))
    }
    let row = try store.writer.read { db in
      try Row.fetchOne(
        db, sql: "SELECT body, version FROM tasks WHERE id = 't1'")
    }
    XCTAssertEqual(row?[0] as String?, "remote body")
    XCTAssertEqual(row?[1] as String?, newer)
  }

  // MARK: - dependencies via cancel

  func testCancelTaskRemovesFromDependents() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTask(store.writer, id: "t1", status: "open")
    try insertTask(store.writer, id: "t2", status: "open")
    try store.writer.write { db in
      try db.execute(
        sql:
          "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at) "
          + "VALUES ('t2', 't1', '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z')"
      )
    }
    let result = try store.writer.write { db in
      try LifecycleStatus.cancelTask(
        db, taskId: tid("t1"),
        now: "2026-03-26T10:00:00Z",
        reminderVersion: "0000000000000_0000_a0a0a0a0a0a0a0a0")
    }
    XCTAssertTrue(result.updated)
    XCTAssertEqual(result.affectedDependentIds, ["t2"])
    let count: Int? = try store.writer.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM task_dependencies WHERE depends_on_task_id = 't1'"
      )
    }
    XCTAssertEqual(count, 0)
  }

  // MARK: - recurrence primitives (primitive-level, no spawn)

  func testCancelRecurringTaskPreservesRecurrenceGroupId() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertRecurringTask(
      store.writer, id: "r1", status: "open",
      groupId: "grp-abc", due: "2026-03-25")
    _ = try store.writer.write { db in
      try LifecycleStatus.cancelTask(
        db, taskId: tid("r1"),
        now: "2026-03-26T10:00:00Z",
        reminderVersion: "0000000000000_0000_a0a0a0a0a0a0a0a0")
    }
    let row = try store.writer.read { db in
      try Row.fetchOne(
        db,
        sql: "SELECT status, recurrence_group_id FROM tasks WHERE id = 'r1'")
    }
    XCTAssertEqual(row?[0] as String?, "cancelled")
    XCTAssertEqual(row?[1] as String?, "grp-abc")
  }

  func testCancelOneRecurringSiblingDoesNotAffectOthers() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertRecurringTask(
      store.writer, id: "r1", status: "open",
      groupId: "grp-shared", due: "2026-03-25")
    try insertRecurringTask(
      store.writer, id: "r2", status: "open",
      groupId: "grp-shared", due: "2026-03-26")
    try insertRecurringTask(
      store.writer, id: "r3", status: "open",
      groupId: "grp-shared", due: "2026-03-27")
    _ = try store.writer.write { db in
      try LifecycleStatus.cancelTask(
        db, taskId: tid("r2"),
        now: "2026-03-26T10:00:00Z",
        reminderVersion: "0000000000000_0000_a0a0a0a0a0a0a0a0")
    }
    let statuses: [(String, String)] = try store.writer.read { db in
      try Row.fetchAll(
        db,
        sql:
          "SELECT id, status FROM tasks WHERE recurrence_group_id = 'grp-shared' ORDER BY id"
      ).map { ($0[0], $0[1]) }
    }
    XCTAssertEqual(statuses.map { $0.0 }, ["r1", "r2", "r3"])
    XCTAssertEqual(statuses.map { $0.1 }, ["open", "cancelled", "open"])
  }

  func testCancelAlreadyCancelledRecurringIsIdempotent() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertRecurringTask(
      store.writer, id: "r1", status: "cancelled",
      groupId: "grp-idem", due: "2026-03-25")
    let result = try store.writer.write { db in
      try LifecycleStatus.cancelTask(
        db, taskId: tid("r1"),
        now: "2026-03-26T10:00:00Z",
        reminderVersion: "0000000000000_0000_a0a0a0a0a0a0a0a0")
    }
    XCTAssertFalse(result.updated)
  }

  func testReopenCancelledRecurringPreservesGroup() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertRecurringTask(
      store.writer, id: "r1", status: "cancelled",
      groupId: "grp-reopen", due: "2026-03-25")
    let result = try store.writer.write { db in
      try LifecycleStatus.reopenTask(
        db, taskId: tid("r1"),
        now: "2026-03-26T10:00:00Z",
        reminderVersion: "0000000000000_0000_a0a0a0a0a0a0a0a0")
    }
    XCTAssertTrue(result.updated)
    let row = try store.writer.read { db in
      try Row.fetchOne(
        db,
        sql: "SELECT status, recurrence_group_id FROM tasks WHERE id = 'r1'")
    }
    XCTAssertEqual(row?[0] as String?, "open")
    XCTAssertEqual(row?[1] as String?, "grp-reopen")
  }

  // MARK: - reminders

  func testCompleteCancelsActiveReminders() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTask(store.writer, id: "t1", status: "open")
    try store.writer.write { db in
      try db.execute(
        sql:
          "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at) "
          + "VALUES ('r1', 't1', '2026-04-01T09:00:00Z', "
          + "        '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z')"
      )
    }
    _ = try store.writer.write { db in
      try LifecycleStatus.completeTask(
        db, taskId: tid("t1"),
        now: "2026-03-26T10:00:00Z",
        reminderVersion: "0000000000000_0000_a0a0a0a0a0a0a0a0")
    }
    let cancelled: String? = try store.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT cancelled_at FROM task_reminders WHERE id = 'r1'")
    }
    XCTAssertNotNil(cancelled)
  }

  func testReopenDoesNotRestoreCancelledReminders() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTask(store.writer, id: "t1", status: "open")
    try store.writer.write { db in
      try db.execute(
        sql:
          "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at) "
          + "VALUES ('r1', 't1', '2026-04-01T09:00:00Z', "
          + "        '0000000000000_0000_aaaa000000000000', '2026-01-01T00:00:00Z')")
      try db.execute(
        sql:
          "INSERT INTO task_reminder_delivery_state (reminder_id, delivery_state, updated_at) "
          + "VALUES ('r1', 'delivered', '2026-01-01T00:00:00Z')")
    }
    _ = try store.writer.write { db in
      try LifecycleStatus.completeTask(
        db, taskId: tid("t1"),
        now: "2026-03-26T10:00:00Z",
        reminderVersion: "0000000000000_0000_c000000000000001")
    }
    let result = try store.writer.write { db in
      try LifecycleStatus.reopenTask(
        db, taskId: tid("t1"),
        now: "2026-03-27T10:00:00Z",
        reminderVersion: "0000000000001_0000_0e0e000000000001")
    }
    XCTAssertTrue(result.updated)
    XCTAssertTrue(result.reopenedReminderIds.isEmpty)
    let row = try store.writer.read { db in
      try Row.fetchOne(
        db, sql: "SELECT cancelled_at, version FROM task_reminders WHERE id = 'r1'"
      )
    }
    XCTAssertNotNil(row?[0] as String?)
    XCTAssertEqual(row?[1] as String?, "0000000000000_0000_c000000000000001")
    let delivered: Int? = try store.writer.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM task_reminder_delivery_state WHERE reminder_id = 'r1'"
      )
    }
    XCTAssertEqual(delivered, 1)
  }

  func testReopenLeavesDismissedRemindersAlone() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTask(store.writer, id: "t1", status: "completed")
    try store.writer.write { db in
      try db.execute(
        sql:
          "INSERT INTO task_reminders (id, task_id, reminder_at, dismissed_at, version, created_at) "
          + "VALUES ('r1', 't1', '2026-04-01T09:00:00Z', '2026-03-25T12:00:00Z', "
          + "        '0000000000000_0000_5eed000000000000', '2026-01-01T00:00:00Z')"
      )
    }
    let result = try store.writer.write { db in
      try LifecycleStatus.reopenTask(
        db, taskId: tid("t1"),
        now: "2026-03-27T10:00:00Z",
        reminderVersion: "0000000000001_0000_0e0e000000000001")
    }
    XCTAssertTrue(result.updated)
    XCTAssertTrue(result.reopenedReminderIds.isEmpty)
    let dismissedAt: String? = try store.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT dismissed_at FROM task_reminders WHERE id = 'r1'")
    }
    XCTAssertNotNil(dismissedAt)
  }

  // MARK: - status primitives

  func testCompleteTaskSetsStatusAndClearsDeferral() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTask(store.writer, id: "t1", status: "open")
    try store.writer.write { db in
      try db.execute(
        sql:
          "UPDATE tasks SET last_deferred_at = '2026-01-01T00:00:00Z' WHERE id = 't1'"
      )
    }
    let result = try store.writer.write { db in
      try LifecycleStatus.completeTask(
        db, taskId: tid("t1"),
        now: "2026-03-26T10:00:00Z",
        reminderVersion: "0000000000000_0000_a0a0a0a0a0a0a0a0")
    }
    XCTAssertTrue(result.updated)
    let row = try store.writer.read { db in
      try Row.fetchOne(
        db,
        sql: "SELECT status, last_deferred_at FROM tasks WHERE id = 't1'")
    }
    XCTAssertEqual(row?[0] as String?, "completed")
    XCTAssertNil(row?[1] as String?)
  }

  func testCompleteTaskRejectsStaleVersion() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTask(store.writer, id: "t1", status: "open")
    let newer = "9999913599999_0000_ffffffffffffffff"
    try store.writer.write { db in
      try db.execute(
        sql: "UPDATE tasks SET version = ?1 WHERE id = 't1'",
        arguments: [newer])
    }
    let stale = "0000000000000_0000_a0a0a0a0a0a0a0a0"
    XCTAssertThrowsError(
      try store.writer.write { db in
        try LifecycleStatus.completeTask(
          db, taskId: tid("t1"),
          now: "2026-03-26T10:00:00Z", reminderVersion: stale)
      }
    ) { error in
      XCTAssertEqual(
        error as? StoreError, .staleVersion(entity: "task", id: "t1"))
    }
    let row = try store.writer.read { db in
      try Row.fetchOne(
        db, sql: "SELECT status, version FROM tasks WHERE id = 't1'")
    }
    XCTAssertEqual(row?[0] as String?, "open")
    XCTAssertEqual(row?[1] as String?, newer)
  }

  func testCancelTaskRejectsStaleVersion() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTask(store.writer, id: "t1", status: "open")
    let newer = "9999913599999_0000_ffffffffffffffff"
    try store.writer.write { db in
      try db.execute(
        sql: "UPDATE tasks SET version = ?1 WHERE id = 't1'",
        arguments: [newer])
    }
    let stale = "0000000000000_0000_a0a0a0a0a0a0a0a0"
    XCTAssertThrowsError(
      try store.writer.write { db in
        try LifecycleStatus.cancelTask(
          db, taskId: tid("t1"),
          now: "2026-03-26T10:00:00Z", reminderVersion: stale)
      }
    ) { error in
      guard case StoreError.staleVersion = error else {
        XCTFail("expected staleVersion, got \(error)")
        return
      }
    }
    let status: String? = try store.writer.read { db in
      try String.fetchOne(db, sql: "SELECT status FROM tasks WHERE id = 't1'")
    }
    XCTAssertEqual(status, "open")
  }

  func testReopenTaskRejectsStaleVersion() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTask(store.writer, id: "t1", status: "completed")
    let newer = "9999913599999_0000_ffffffffffffffff"
    try store.writer.write { db in
      try db.execute(
        sql: "UPDATE tasks SET version = ?1 WHERE id = 't1'",
        arguments: [newer])
    }
    let stale = "0000000000000_0000_a0a0a0a0a0a0a0a0"
    XCTAssertThrowsError(
      try store.writer.write { db in
        try LifecycleStatus.reopenTask(
          db, taskId: tid("t1"),
          now: "2026-03-26T10:00:00Z", reminderVersion: stale)
      }
    ) { error in
      guard case StoreError.staleVersion = error else {
        XCTFail("expected staleVersion, got \(error)")
        return
      }
    }
    let status: String? = try store.writer.read { db in
      try String.fetchOne(db, sql: "SELECT status FROM tasks WHERE id = 't1'")
    }
    XCTAssertEqual(status, "completed")
  }

  func testCompleteAlreadyCompletedReturnsNotUpdated() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTask(store.writer, id: "t1", status: "completed")
    let result = try store.writer.write { db in
      try LifecycleStatus.completeTask(
        db, taskId: tid("t1"),
        now: "2026-03-26T10:00:00Z",
        reminderVersion: "0000000000000_0000_a0a0a0a0a0a0a0a0")
    }
    XCTAssertFalse(result.updated)
  }

  func testReopenTaskClearsCompletionAndDeferralState() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTask(store.writer, id: "t1", status: "completed")
    try store.writer.write { db in
      try db.execute(
        sql:
          "UPDATE tasks SET completed_at = '2026-03-01T00:00:00Z', "
          + "planned_date = '2026-03-01', "
          + "last_deferred_at = '2026-02-28T00:00:00Z', "
          + "defer_count = 2 WHERE id = 't1'")
    }
    let result = try store.writer.write { db in
      try LifecycleStatus.reopenTask(
        db, taskId: tid("t1"),
        now: "2026-03-26T10:00:00Z",
        reminderVersion: "0000000000000_0000_a0a0a0a0a0a0a0a0")
    }
    XCTAssertTrue(result.updated)
    let row = try store.writer.read { db in
      try Row.fetchOne(
        db,
        sql:
          "SELECT status, completed_at, planned_date, last_deferred_at, defer_count FROM tasks WHERE id = 't1'"
      )
    }
    XCTAssertEqual(row?[0] as String?, "open")
    XCTAssertNil(row?[1] as String?)
    XCTAssertNil(row?[2] as String?)
    XCTAssertNil(row?[3] as String?)
    XCTAssertEqual(row?[4] as Int64?, 0)
  }

  func testReopenAlreadyOpenReturnsNotUpdated() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTask(store.writer, id: "t1", status: "open")
    let result = try store.writer.write { db in
      try LifecycleStatus.reopenTask(
        db, taskId: tid("t1"),
        now: "2026-03-26T10:00:00Z",
        reminderVersion: "0000000000000_0000_a0a0a0a0a0a0a0a0")
    }
    XCTAssertFalse(result.updated)
  }

  func testReopenCancelledTaskWorks() throws {
    let store = try WorkflowTestSupport.freshStore()
    try insertTask(store.writer, id: "t1", status: "cancelled")
    let result = try store.writer.write { db in
      try LifecycleStatus.reopenTask(
        db, taskId: tid("t1"),
        now: "2026-03-26T10:00:00Z",
        reminderVersion: "0000000000000_0000_a0a0a0a0a0a0a0a0")
    }
    XCTAssertTrue(result.updated)
    let status: String? = try store.writer.read { db in
      try String.fetchOne(db, sql: "SELECT status FROM tasks WHERE id = 't1'")
    }
    XCTAssertEqual(status, "open")
  }
}
