import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

/// Ports `repositories/task/reminders/tests.rs`.
final class TaskRepoRemindersTests: XCTestCase {

  private static let now = "2026-05-03T12:00:00.000Z"

  /// Mirror Rust `TaskBuilder` defaults (`title = "Seed Task"`,
  /// `status = open`, `version`/`created_at` constants). `list_id` falls
  /// through to the schema `NOT NULL DEFAULT 'inbox'`.
  private func seedTask(_ db: Database, _ id: String, status: String = "open") throws {
    try db.execute(
      sql: """
        INSERT INTO tasks (id, title, status, version, created_at, updated_at, completed_at, defer_count) \
        VALUES (?1, 'Seed Task', ?2, '0000000000000_0000_0000000000000000', \
                '2026-03-20T00:00:00.000Z', '2026-03-20T00:00:00.000Z', \
                CASE WHEN ?2 = 'completed' THEN '2026-03-20T00:00:00.000Z' END, 0)
        """,
      arguments: [id, status])
  }

  private func insertReminder(
    _ db: Database, _ id: String, _ taskId: String, _ reminderAt: String,
    dismissedAt: String? = nil, cancelledAt: String? = nil
  ) throws {
    try db.execute(
      sql: """
        INSERT INTO task_reminders \
        (id, task_id, reminder_at, dismissed_at, cancelled_at, version, created_at) \
        VALUES (?1, ?2, ?3, ?4, ?5, '0000000000001_0000_0000000000000001', '2026-05-01T00:00:00.000Z')
        """,
      arguments: [id, taskId, reminderAt, dismissedAt, cancelledAt])
  }

  private func setDeliveryState(_ db: Database, _ reminderId: String, _ state: String) throws {
    try db.execute(
      sql: """
        INSERT INTO task_reminder_delivery_state (reminder_id, delivery_state, updated_at) \
        VALUES (?1, ?2, '2026-05-01T00:00:00.000Z')
        """,
      arguments: [reminderId, state])
  }

  private func recordArmed(
    _ db: Database, _ reminderIds: [String], at armedAt: String = "2026-05-03T10:59:00.000Z"
  ) throws {
    try TaskRepo.Reminders.replaceRemindersArmed(
      db, armedReminderIDs: reminderIds, armedAt: armedAt)
  }

  private func archiveTask(_ db: Database, _ taskId: String) throws {
    try db.execute(
      sql: "UPDATE tasks SET archived_at = '2026-05-02T00:00:00.000Z' WHERE id = ?1",
      arguments: [taskId])
  }

  func testDueRemindersReturnsPendingOpenUndismissed() throws {
    let store = try TestSupport.freshStore()
    let result: TaskRepo.Reminders.ReminderQueryResult = try store.writer.write { db in
      try self.seedTask(db, "task-1")
      try self.insertReminder(db, "rem-1", "task-1", "2026-05-03T11:00:00.000Z")
      return try TaskRepo.Reminders.getDueTaskReminders(db, now: Self.now, limit: 10)
    }
    XCTAssertEqual(result.rows.count, 1)
    XCTAssertEqual(result.rows[0].id, "rem-1")
    XCTAssertEqual(result.rows[0].taskTitle, "Seed Task")
    XCTAssertEqual(result.rows[0].deliveryState, "pending")
    XCTAssertEqual(result.totalMatching, 1)
  }

  func testDueRemindersExcludesFutureReminders() throws {
    let store = try TestSupport.freshStore()
    let result = try store.writer.write { db in
      try self.seedTask(db, "task-1")
      try self.insertReminder(db, "rem-future", "task-1", "2026-05-03T13:00:00.000Z")
      return try TaskRepo.Reminders.getDueTaskReminders(db, now: Self.now, limit: 10)
    }
    XCTAssertTrue(result.rows.isEmpty)
  }

  func testDueRemindersExcludesDismissedCancelledDelivered() throws {
    let store = try TestSupport.freshStore()
    let result = try store.writer.write { db in
      try self.seedTask(db, "task-1")
      try self.insertReminder(
        db, "rem-dismissed", "task-1", "2026-05-03T11:00:00.000Z",
        dismissedAt: "2026-05-03T11:30:00.000Z")
      try self.insertReminder(
        db, "rem-cancelled", "task-1", "2026-05-03T11:00:00.000Z",
        cancelledAt: "2026-05-03T11:30:00.000Z")
      try self.insertReminder(db, "rem-delivered", "task-1", "2026-05-03T11:00:00.000Z")
      try self.setDeliveryState(db, "rem-delivered", "delivered")
      try self.insertReminder(db, "rem-pending", "task-1", "2026-05-03T11:00:00.000Z")
      return try TaskRepo.Reminders.getDueTaskReminders(db, now: Self.now, limit: 10)
    }
    XCTAssertEqual(result.rows.map { $0.id }, ["rem-pending"])
  }

  func testDueRemindersExcludesNonOpenAndArchivedTasks() throws {
    let store = try TestSupport.freshStore()
    let result = try store.writer.write { db in
      try self.seedTask(db, "task-completed", status: "completed")
      try self.seedTask(db, "task-cancelled", status: "cancelled")
      try self.seedTask(db, "task-open")
      try self.seedTask(db, "task-archived")
      try self.archiveTask(db, "task-archived")

      try self.insertReminder(db, "r-c", "task-completed", "2026-05-03T11:00:00.000Z")
      try self.insertReminder(db, "r-x", "task-cancelled", "2026-05-03T11:00:00.000Z")
      try self.insertReminder(db, "r-o", "task-open", "2026-05-03T11:00:00.000Z")
      try self.insertReminder(db, "r-a", "task-archived", "2026-05-03T11:00:00.000Z")
      return try TaskRepo.Reminders.getDueTaskReminders(db, now: Self.now, limit: 10)
    }
    XCTAssertEqual(result.rows.map { $0.id }, ["r-o"])
  }

  func testDueRemindersTruncatesAndSignalsViaNegativeTotal() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.seedTask(db, "task-1")
      for i in 0..<5 {
        try self.insertReminder(db, "rem-\(i)", "task-1", "2026-05-03T11:00:00.000Z")
      }
    }
    try store.writer.read { db in
      let r3 = try TaskRepo.Reminders.getDueTaskReminders(db, now: Self.now, limit: 3)
      XCTAssertEqual(r3.rows.count, 3)
      XCTAssertEqual(r3.totalMatching, -1)

      let r5 = try TaskRepo.Reminders.getDueTaskReminders(db, now: Self.now, limit: 5)
      XCTAssertEqual(r5.rows.count, 5)
      XCTAssertEqual(r5.totalMatching, 5)

      let r100 = try TaskRepo.Reminders.getDueTaskReminders(db, now: Self.now, limit: 100)
      XCTAssertEqual(r100.rows.count, 5)
      XCTAssertEqual(r100.totalMatching, 5)
    }
  }

  func testDueRemindersOrdersByReminderAtThenId() throws {
    let store = try TestSupport.freshStore()
    let result = try store.writer.write { db in
      try self.seedTask(db, "task-1")
      try self.insertReminder(db, "rem-zzz", "task-1", "2026-05-03T11:00:00.000Z")
      try self.insertReminder(db, "rem-aaa", "task-1", "2026-05-03T11:00:00.000Z")
      try self.insertReminder(db, "rem-mmm", "task-1", "2026-05-03T10:00:00.000Z")
      return try TaskRepo.Reminders.getDueTaskReminders(db, now: Self.now, limit: 10)
    }
    XCTAssertEqual(result.rows.map { $0.id }, ["rem-mmm", "rem-aaa", "rem-zzz"])
  }

  func testUpcomingRemindersReturnsWindowStrictlyAfterNow() throws {
    let store = try TestSupport.freshStore()
    let result = try store.writer.write { db in
      try self.seedTask(db, "task-1")
      try self.insertReminder(db, "rem-at-now", "task-1", Self.now)
      try self.insertReminder(db, "rem-in-window", "task-1", "2026-05-03T13:00:00.000Z")
      try self.insertReminder(db, "rem-at-horizon", "task-1", "2026-05-03T14:00:00.000Z")
      try self.insertReminder(db, "rem-after-horizon", "task-1", "2026-05-03T14:00:00.001Z")
      return try TaskRepo.Reminders.getUpcomingTaskRemindersUntil(
        db, now: Self.now, horizon: "2026-05-03T14:00:00.000Z", limit: 10)
    }
    XCTAssertEqual(result.rows.map { $0.id }, ["rem-in-window", "rem-at-horizon"])
  }

  func testUpcomingRemindersTruncatesAndSignalsViaNegativeTotal() throws {
    let store = try TestSupport.freshStore()
    let result = try store.writer.write { db in
      try self.seedTask(db, "task-1")
      for i in 0..<4 {
        try self.insertReminder(db, "rem-\(i)", "task-1", "2026-05-03T13:00:00.000Z")
      }
      return try TaskRepo.Reminders.getUpcomingTaskRemindersUntil(
        db, now: Self.now, horizon: "2026-05-03T14:00:00.000Z", limit: 2)
    }
    XCTAssertEqual(result.rows.count, 2)
    XCTAssertEqual(result.totalMatching, -1)
  }

  /// The delivery reconcile marks an already-elapsed reminder delivered ONLY
  /// once it was actually armed (`last_armed_at` recorded), so
  /// `getDueTaskReminders` stops re-surfacing it, while a not-yet-due reminder
  /// stays pending and is still returned once its own time arrives.
  func testMarkDueRemindersDeliveredSuppressesPastKeepsFuture() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.seedTask(db, "task-1")
      try self.insertReminder(db, "rem-past", "task-1", "2026-05-03T11:00:00.000Z")
      try self.insertReminder(db, "rem-future", "task-1", "2026-05-03T13:00:00.000Z")
      // Both were armed with the OS on a prior reschedule pass.
      try self.recordArmed(db, ["rem-past", "rem-future"])

      // Guard: before any reconcile the elapsed reminder is due-and-pending.
      XCTAssertEqual(
        try TaskRepo.Reminders.getDueTaskReminders(db, now: Self.now, limit: 10).rows.map { $0.id },
        ["rem-past"])

      // Reconcile as of now marks exactly the one elapsed, armed reminder.
      XCTAssertEqual(try TaskRepo.Reminders.markDueRemindersDelivered(db, now: Self.now), 1)
      XCTAssertTrue(
        try TaskRepo.Reminders.getDueTaskReminders(db, now: Self.now, limit: 10).rows.isEmpty)

      // Idempotent: a second reconcile at the same instant marks nothing.
      XCTAssertEqual(try TaskRepo.Reminders.markDueRemindersDelivered(db, now: Self.now), 0)

      // The future reminder was never delivered, so it surfaces once due.
      XCTAssertEqual(
        try TaskRepo.Reminders.getDueTaskReminders(
          db, now: "2026-05-03T13:30:00.000Z", limit: 10
        ).rows.map { $0.id },
        ["rem-future"])
    }
  }

  /// N1 regression: an elapsed reminder whose notification request was never
  /// armed (budgeted out of the pending cap, authorization denied, or an `add`
  /// failure — so no `last_armed_at` stamp) must NOT be marked delivered
  /// merely because its time has passed. It stays pending so the miss remains
  /// visible to assistant/MCP due queries instead of being recorded as a phantom
  /// delivery.
  func testMarkDueRemindersDeliveredLeavesNeverArmedPending() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.seedTask(db, "task-1")
      // Elapsed, live, undismissed, uncancelled — but never armed.
      try self.insertReminder(db, "rem-unarmed", "task-1", "2026-05-03T11:00:00.000Z")

      // Nothing to mark: the reminder was never armed.
      XCTAssertEqual(try TaskRepo.Reminders.markDueRemindersDelivered(db, now: Self.now), 0)
      // It is still surfaced as due-and-pending, not a silent delivery.
      XCTAssertEqual(
        try TaskRepo.Reminders.getDueTaskReminders(db, now: Self.now, limit: 10).rows.map { $0.id },
        ["rem-unarmed"])

      // Once it is actually armed, the reconcile transitions it to delivered.
      try self.recordArmed(db, ["rem-unarmed"])
      XCTAssertEqual(try TaskRepo.Reminders.markDueRemindersDelivered(db, now: Self.now), 1)
      XCTAssertTrue(
        try TaskRepo.Reminders.getDueTaskReminders(db, now: Self.now, limit: 10).rows.isEmpty)
    }
  }

  /// The reconcile honors the live-task guard: a reminder on a completed or
  /// archived task is never marked (those are excluded from the due query too),
  /// even when it was armed.
  func testMarkDueRemindersDeliveredSkipsNonLiveTasks() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.seedTask(db, "task-done", status: "completed")
      try self.seedTask(db, "task-archived")
      try self.archiveTask(db, "task-archived")
      try self.insertReminder(db, "r-done", "task-done", "2026-05-03T11:00:00.000Z")
      try self.insertReminder(db, "r-arch", "task-archived", "2026-05-03T11:00:00.000Z")
      try self.recordArmed(db, ["r-done", "r-arch"])
      XCTAssertEqual(try TaskRepo.Reminders.markDueRemindersDelivered(db, now: Self.now), 0)
    }
  }

  /// The armed record is a replace, not an accumulate: a pending reminder
  /// dropped from a later pass's armed set (its OS request was just removed by
  /// the replace-all scheduler — budgeted out, denied, or add-failed) has its
  /// stale stamp cleared, so its elapse can no longer be recorded as a phantom
  /// delivery and it keeps surfacing as due.
  func testReplaceArmedClearsDroppedPendingReminder() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.seedTask(db, "task-1")
      try self.insertReminder(db, "rem-a", "task-1", "2026-05-03T11:00:00.000Z")
      try self.insertReminder(db, "rem-b", "task-1", "2026-05-03T13:00:00.000Z")
      try self.recordArmed(db, ["rem-a", "rem-b"])

      // The next pass only re-arms rem-b; rem-a's request was dropped.
      try self.recordArmed(db, ["rem-b"])

      // rem-a's elapse is NOT a delivery — it stays due-and-pending.
      XCTAssertEqual(try TaskRepo.Reminders.markDueRemindersDelivered(db, now: Self.now), 0)
      XCTAssertEqual(
        try TaskRepo.Reminders.getDueTaskReminders(db, now: Self.now, limit: 10).rows.map { $0.id },
        ["rem-a"])
    }
  }

  /// Clearing on replace only touches still-pending rows: a reminder already
  /// recorded as delivered keeps its historical armed stamp and delivered
  /// state even when later passes no longer include it.
  func testReplaceArmedPreservesDeliveredRows() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.seedTask(db, "task-1")
      try self.insertReminder(db, "rem-shown", "task-1", "2026-05-03T11:00:00.000Z")
      try self.recordArmed(db, ["rem-shown"])
      XCTAssertEqual(try TaskRepo.Reminders.markDueRemindersDelivered(db, now: Self.now), 1)

      // Delivered reminders drop out of scheduling, so later passes omit them.
      try self.recordArmed(db, [])

      let row = try Row.fetchOne(
        db,
        sql: """
          SELECT delivery_state, last_armed_at FROM task_reminder_delivery_state \
          WHERE reminder_id = 'rem-shown'
          """)
      XCTAssertEqual(row?["delivery_state"] as String?, "delivered")
      XCTAssertNotNil(row?["last_armed_at"] as String?)
    }
  }
}
