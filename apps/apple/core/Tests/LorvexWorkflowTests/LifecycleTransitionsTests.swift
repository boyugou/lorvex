import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexWorkflow

/// Parity port of `lorvex_workflow::lifecycle::tests::transitions`,
/// scoped to cases that DON'T exercise the recurrence-spawn or
/// cancel-recurring-successors injection points. Tests that require
/// the full spawn/cancel-successor pipeline are deferred to the next
/// port slice — they land alongside the real
/// ``RecurrenceSpawnHandler``.
///
/// Swift uses `precondition(db.isInsideTransaction)` for the transaction
/// guard; the four Rust `#[should_panic]` autocommit-guard tests are
/// not portable through XCTest (precondition traps the process) and are
/// deferred to the next slice along with broader test infrastructure.
final class LifecycleTransitionsTests: XCTestCase {
  private func tid(_ s: String) -> TaskId { TaskId(trusted: s) }

  private func seedTask(
    _ writer: any DatabaseWriter, id: String, status: String
  ) throws {
    try writer.write { db in
      try db.execute(
        sql:
          "INSERT INTO tasks (id, title, status, version, created_at, updated_at, completed_at) "
          + "VALUES (?1, ?1, ?2, '0000000000000_0000_0000000000000000', "
          + "        '2026-04-20T00:00:00Z', '2026-04-20T00:00:00Z', "
          + "        CASE WHEN ?2 = 'completed' THEN '2026-04-20T00:00:00Z' END)",
        arguments: [id, status])
    }
  }

  func testCompletionRejectsCancelledTaskAtSharedLayer() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTask(store.writer, id: "cancelled-to-completed", status: "cancelled")
    XCTAssertThrowsError(
      try store.writer.write { db in
        try LifecycleTransitions.applyCompletionTransition(
          db, taskId: tid("cancelled-to-completed"),
          now: "2026-04-20T09:00:00Z",
          reminderVersion: "0000000000001_0000_a0a0a0a0a0a0a0a0")
      }
    ) { error in
      guard case StoreError.validation = error else {
        XCTFail("expected validation, got \(error)")
        return
      }
    }
    let status: String? = try store.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT status FROM tasks WHERE id = 'cancelled-to-completed'")
    }
    XCTAssertEqual(status, "cancelled")
  }

  func testCancellationRejectsCompletedTaskAtSharedLayer() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTask(store.writer, id: "completed-to-cancelled", status: "completed")
    XCTAssertThrowsError(
      try store.writer.write { db in
        try LifecycleTransitions.applyCancelTransition(
          db, taskId: tid("completed-to-cancelled"),
          now: "2026-04-20T09:00:00Z",
          reminderVersion: "0000000000001_0000_a0a0a0a0a0a0a0a0",
          cancelSeries: false, seriesClearVersion: nil)
      }
    ) { error in
      guard case StoreError.validation = error else {
        XCTFail("expected validation, got \(error)")
        return
      }
    }
    let status: String? = try store.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT status FROM tasks WHERE id = 'completed-to-cancelled'")
    }
    XCTAssertEqual(status, "completed")
  }

  func testGenericLifecycleTransitionRejectsTerminalToTerminal() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTask(store.writer, id: "generic-terminal-drift", status: "completed")
    XCTAssertThrowsError(
      try store.writer.write { db in
        try LifecycleTransitions.applyLifecycleTransition(
          db,
          taskId: tid("generic-terminal-drift"),
          oldStatus: .completed,
          newStatus: .cancelled,
          now: "2026-04-20T09:00:00Z",
          reminderVersion: "0000000000001_0000_a0a0a0a0a0a0a0a0")
      }
    ) { error in
      guard case StoreError.validation = error else {
        XCTFail("expected validation, got \(error)")
        return
      }
    }
  }

  func testCompletionRejectsUnparseablePersistedStatusBeforeMutation() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      try db.execute(sql: "PRAGMA ignore_check_constraints = ON")
      try db.execute(
        sql:
          "INSERT INTO tasks (id, title, status, version, created_at, updated_at) "
          + "VALUES ('corrupt-status', 'Corrupt status', 'in_review', "
          + "        '0000000000000_0000_0000000000000000', "
          + "        '2026-04-20T00:00:00Z', '2026-04-20T00:00:00Z')")
      try db.execute(sql: "PRAGMA ignore_check_constraints = OFF")
    }
    XCTAssertThrowsError(
      try store.writer.write { db in
        try LifecycleTransitions.applyCompletionTransition(
          db, taskId: tid("corrupt-status"),
          now: "2026-04-20T09:00:00Z",
          reminderVersion: "0000000000001_0000_a0a0a0a0a0a0a0a0")
      }
    ) { error in
      guard case StoreError.invariant(let msg) = error else {
        XCTFail("expected invariant, got \(error)")
        return
      }
      XCTAssertTrue(msg.contains("corrupt-status"))
      XCTAssertTrue(msg.contains("in_review"))
    }
    let row = try store.writer.read { db in
      try Row.fetchOne(
        db, sql: "SELECT status, completed_at FROM tasks WHERE id = 'corrupt-status'"
      )
    }
    XCTAssertEqual(row?[0] as String?, "in_review")
    XCTAssertNil(row?[1] as String?)
  }

  // MARK: - non-recurring orchestrator happy paths through Noop handler

  /// A non-recurring task transitions cleanly through the completion
  /// orchestrator without ever touching the
  /// ``RecurrenceSpawnHandler`` — the guard `if let rule =
  /// snap.recurrence, !rule.isEmpty` short-circuits the spawn branch
  /// so even the throwing default handler is never called.
  func testCompletionTransitionForNonRecurringTask() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTask(store.writer, id: "plain", status: "open")
    let result = try store.writer.write { db in
      try LifecycleTransitions.applyCompletionTransition(
        db, taskId: tid("plain"),
        now: "2026-04-20T09:00:00Z",
        reminderVersion: "0000000000001_0000_a0a0a0a0a0a0a0a0")
    }
    XCTAssertTrue(result.updated)
    XCTAssertNil(result.spawnedSuccessorId)
  }

  func testCancelTransitionForNonRecurringTask() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTask(store.writer, id: "plain", status: "open")
    let result = try store.writer.write { db in
      try LifecycleTransitions.applyCancelTransition(
        db, taskId: tid("plain"),
        now: "2026-04-20T09:00:00Z",
        reminderVersion: "0000000000001_0000_a0a0a0a0a0a0a0a0",
        cancelSeries: false, seriesClearVersion: nil)
    }
    XCTAssertTrue(result.updated)
    XCTAssertNil(result.spawnedSuccessorId)
  }

  func testReopenTransitionForNonRecurringTask() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTask(store.writer, id: "plain", status: "completed")
    let result = try store.writer.write { db in
      try LifecycleTransitions.applyReopenTransition(
        db, taskId: tid("plain"),
        oldStatus: .completed,
        now: "2026-04-20T09:00:00Z",
        reminderVersion: "0000000000001_0000_a0a0a0a0a0a0a0a0")
    }
    XCTAssertTrue(result.updated)
    XCTAssertTrue(result.transition.cancelledSuccessorIds.isEmpty)
  }

  func testApplyLifecycleTransitionForNonRecurringTask() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTask(store.writer, id: "plain", status: "open")
    let result = try store.writer.write { db in
      try LifecycleTransitions.applyLifecycleTransition(
        db, taskId: tid("plain"),
        oldStatus: .open, newStatus: .completed,
        now: "2026-04-20T09:00:00Z",
        reminderVersion: "0000000000001_0000_a0a0a0a0a0a0a0a0")
    }
    XCTAssertNil(result.spawnedSuccessorId)
    let status: String? = try store.writer.read { db in
      try String.fetchOne(db, sql: "SELECT status FROM tasks WHERE id = 'plain'")
    }
    XCTAssertEqual(status, "completed")
  }

  /// Reopen of a non-recurring task does NOT invoke the
  /// cancel-successors injection point (the guard `snap.recurrence !=
  /// nil` short-circuits), so the no-op handler doesn't throw and the
  /// reopen lands cleanly.
  func testReopenNonRecurringDoesNotCancelSuccessors() throws {
    let store = try WorkflowTestSupport.freshStore()
    try seedTask(store.writer, id: "plain", status: "completed")
    let result = try store.writer.write { db in
      try LifecycleTransitions.applyReopenTransition(
        db, taskId: tid("plain"),
        oldStatus: .completed,
        now: "2026-04-20T09:00:00Z",
        reminderVersion: "0000000000001_0000_a0a0a0a0a0a0a0a0")
    }
    XCTAssertTrue(result.updated)
    XCTAssertTrue(result.transition.cancelledSuccessorIds.isEmpty)
  }

  // MARK: - cancel_series clear branch (non-spawn path of cancel)

  func testCancelSeriesClearsRecurrenceFields() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      try db.execute(
        sql:
          "INSERT INTO tasks (id, title, status, due_date, canonical_occurrence_date, "
          + " recurrence, recurrence_group_id, version, created_at, updated_at) "
          + "VALUES ('r1', 'r1', 'open', '2026-03-25', '2026-03-25', "
          + "        '{\"FREQ\":\"DAILY\"}', 'grp-clear', "
          + "        '0000000000000_0000_0000000000000000', "
          + "        '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')")
    }
    let result = try store.writer.write { db in
      try LifecycleTransitions.applyCancelTransition(
        db, taskId: tid("r1"),
        now: "2026-03-26T10:00:00Z",
        reminderVersion: "0000000000001_0000_a0a0a0a0a0a0a0a0",
        cancelSeries: true,
        seriesClearVersion: "0000000000002_0000_a0a0a0a0a0a0a0a0")
    }
    XCTAssertTrue(result.updated)
    XCTAssertNil(result.spawnedSuccessorId)
    let row = try store.writer.read { db in
      try Row.fetchOne(
        db,
        sql:
          "SELECT status, recurrence, recurrence_group_id, canonical_occurrence_date FROM tasks WHERE id = 'r1'"
      )
    }
    XCTAssertEqual(row?[0] as String?, "cancelled")
    XCTAssertNil(row?[1] as String?)
    XCTAssertNil(row?[2] as String?)
    XCTAssertNil(row?[3] as String?)
  }

  func testCancelSeriesRequiresClearVersion() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      try db.execute(
        sql:
          "INSERT INTO tasks (id, title, status, due_date, canonical_occurrence_date, "
          + " recurrence, recurrence_group_id, version, created_at, updated_at) "
          + "VALUES ('r1', 'r1', 'open', '2026-03-25', '2026-03-25', "
          + "        '{\"FREQ\":\"DAILY\"}', 'grp-clear', "
          + "        '0000000000000_0000_0000000000000000', "
          + "        '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')")
    }
    XCTAssertThrowsError(
      try store.writer.write { db in
        try LifecycleTransitions.applyCancelTransition(
          db, taskId: tid("r1"),
          now: "2026-03-26T10:00:00Z",
          reminderVersion: "0000000000001_0000_a0a0a0a0a0a0a0a0",
          cancelSeries: true, seriesClearVersion: nil)
      }
    ) { error in
      guard case StoreError.invariant = error else {
        XCTFail("expected invariant, got \(error)")
        return
      }
    }
  }
}
