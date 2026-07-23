import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Ports the parity `#[test]` cases for the independent-child appliers (Rust
/// `child/tests.rs`): task_reminder insert/LWW/delivery-state-reset/delete.
final class ApplyChildTests: XCTestCase {

  private let vOld = "1711234567000_0000_dec0000100000001"
  private let vMid = "1711234568000_0000_dec0000100000001"
  private let vNew = "1711234569000_0000_dec0000100000001"
  private let zeroVersion = "0000000000000_0000_0000000000000000"

  private func withDB(_ body: (Database) throws -> Void) throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in try body(db) }
  }

  private func insertTask(_ db: Database, _ id: String) throws {
    try db.execute(
      sql: """
        INSERT INTO tasks (id, title, status, version, created_at, updated_at)
        VALUES (?, 'T', 'open', ?, '', '')
        """,
      arguments: [id, zeroVersion])
  }

  private func taskReminderPayload(taskId: String, reminderAt: String) -> String {
    """
    {"task_id":"\(taskId)","reminder_at":"\(reminderAt)","dismissed_at":null,"cancelled_at":null,"created_at":"2026-01-01T00:00:00Z"}
    """
  }

  private func countTaskReminders(_ db: Database) throws -> Int64 {
    try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM task_reminders") ?? -1
  }

  private func reminderAt(_ db: Database, _ id: String) throws -> String? {
    try String.fetchOne(db, sql: "SELECT reminder_at FROM task_reminders WHERE id = ?", arguments: [id])
  }

  private func reminderVersion(_ db: Database, _ id: String) throws -> String? {
    try String.fetchOne(db, sql: "SELECT version FROM task_reminders WHERE id = ?", arguments: [id])
  }

  private func countDeliveryState(_ db: Database, _ reminderId: String) throws -> Int64 {
    try Int64.fetchOne(
      db, sql: "SELECT COUNT(*) FROM task_reminder_delivery_state WHERE reminder_id = ?",
      arguments: [reminderId]) ?? -1
  }

  private func insertDeliveredState(_ db: Database, _ reminderId: String) throws {
    try db.execute(
      sql: """
        INSERT INTO task_reminder_delivery_state
          (reminder_id, delivery_state, last_delivered_at, last_armed_at, updated_at)
        VALUES (?, 'delivered', '2026-03-15T09:01:00Z', '2026-03-15T09:01:00Z', '2026-03-15T09:01:00Z')
        """,
      arguments: [reminderId])
  }

  // MARK: - task_reminder upsert

  func testTaskReminderUpsertInsertsNewReminder() throws {
    try withDB { db in
      try self.insertTask(db, "task-1")
      let payload = self.taskReminderPayload(taskId: "task-1", reminderAt: "2026-03-15T09:00:00Z")
      try ApplyChild.applyTaskReminderUpsert(
        db, entityId: "rem-001", payload: payload, version: self.vMid, tieBreak: .rejectEqual)
      XCTAssertEqual(try self.countTaskReminders(db), 1)
      XCTAssertEqual(try self.reminderAt(db, "rem-001"), "2026-03-15T09:00:00.000Z")
    }
  }

  func testTaskReminderUpsertWithOffsetPersistsCanonicalUtcTimestamp() throws {
    try withDB { db in
      try self.insertTask(db, "task-1")
      let payload = self.taskReminderPayload(
        taskId: "task-1", reminderAt: "2026-12-01T09:00:00-05:00")
      try ApplyChild.applyTaskReminderUpsert(
        db, entityId: "rem-001", payload: payload, version: self.vMid, tieBreak: .rejectEqual)
      XCTAssertEqual(try self.reminderAt(db, "rem-001"), "2026-12-01T14:00:00.000Z")

      let due = try TaskRepo.Reminders.getDueTaskReminders(
        db, now: "2026-12-02T00:00:00.000Z", limit: 10)
      XCTAssertEqual(due.rows.count, 1)
      XCTAssertEqual(due.rows[0].reminderAt.asString, "2026-12-01T14:00:00.000Z")
    }
  }

  func testTaskReminderUpsertUpdatesWhenVersionIsNewer() throws {
    try withDB { db in
      try self.insertTask(db, "task-1")
      try ApplyChild.applyTaskReminderUpsert(
        db, entityId: "rem-001",
        payload: self.taskReminderPayload(taskId: "task-1", reminderAt: "2026-03-15T09:00:00Z"),
        version: self.vOld, tieBreak: .rejectEqual)
      try ApplyChild.applyTaskReminderUpsert(
        db, entityId: "rem-001",
        payload: self.taskReminderPayload(taskId: "task-1", reminderAt: "2026-03-16T10:00:00Z"),
        version: self.vNew, tieBreak: .rejectEqual)
      XCTAssertEqual(try self.countTaskReminders(db), 1)
      XCTAssertEqual(try self.reminderAt(db, "rem-001"), "2026-03-16T10:00:00.000Z")
      XCTAssertEqual(try self.reminderVersion(db, "rem-001"), self.vNew)
    }
  }

  func testTaskReminderUpsertClearsDeliveryStateWhenTimeChanges() throws {
    try withDB { db in
      try self.insertTask(db, "task-1")
      try ApplyChild.applyTaskReminderUpsert(
        db, entityId: "rem-001",
        payload: self.taskReminderPayload(taskId: "task-1", reminderAt: "2026-03-15T09:00:00Z"),
        version: self.vOld, tieBreak: .rejectEqual)
      try self.insertDeliveredState(db, "rem-001")
      XCTAssertEqual(try self.countDeliveryState(db, "rem-001"), 1)

      try ApplyChild.applyTaskReminderUpsert(
        db, entityId: "rem-001",
        payload: self.taskReminderPayload(taskId: "task-1", reminderAt: "2026-04-01T10:00:00Z"),
        version: self.vNew, tieBreak: .rejectEqual)
      XCTAssertEqual(try self.reminderAt(db, "rem-001"), "2026-04-01T10:00:00.000Z")
      XCTAssertEqual(
        try self.countDeliveryState(db, "rem-001"), 0,
        "delivery_state row must be cleared when reminder_at is edited")
    }
  }

  func testTaskReminderUpsertPreservesDeliveryStateWhenTimeUnchanged() throws {
    try withDB { db in
      try self.insertTask(db, "task-1")
      try ApplyChild.applyTaskReminderUpsert(
        db, entityId: "rem-001",
        payload: self.taskReminderPayload(taskId: "task-1", reminderAt: "2026-03-15T09:00:00Z"),
        version: self.vOld, tieBreak: .rejectEqual)
      try self.insertDeliveredState(db, "rem-001")
      try ApplyChild.applyTaskReminderUpsert(
        db, entityId: "rem-001",
        payload: self.taskReminderPayload(taskId: "task-1", reminderAt: "2026-03-15T09:00:00Z"),
        version: self.vNew, tieBreak: .rejectEqual)
      XCTAssertEqual(
        try self.countDeliveryState(db, "rem-001"), 1,
        "delivery_state must be preserved when reminder_at is unchanged")
    }
  }

  func testTaskReminderUpsertPreservesDeliveryStateOnFormatOnlyCanonicalization() throws {
    try withDB { db in
      try self.insertTask(db, "task-1")
      try db.execute(
        sql: """
          INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at)
          VALUES ('rem-legacy-format', 'task-1', '2026-03-15T09:00:00Z', ?, '2026-01-01T00:00:00Z')
          """,
        arguments: [self.vOld])
      try self.insertDeliveredState(db, "rem-legacy-format")

      try ApplyChild.applyTaskReminderUpsert(
        db, entityId: "rem-legacy-format",
        payload: self.taskReminderPayload(taskId: "task-1", reminderAt: "2026-03-15T09:00:00.000Z"),
        version: self.vNew, tieBreak: .rejectEqual)
      XCTAssertEqual(try self.reminderAt(db, "rem-legacy-format"), "2026-03-15T09:00:00.000Z")
      XCTAssertEqual(
        try self.countDeliveryState(db, "rem-legacy-format"), 1,
        "format-only canonicalization must not re-fire a delivered reminder")
    }
  }

  func testTaskReminderUpsertFreshInsertLeavesDeliveryStateAbsent() throws {
    try withDB { db in
      try self.insertTask(db, "task-1")
      try ApplyChild.applyTaskReminderUpsert(
        db, entityId: "rem-001",
        payload: self.taskReminderPayload(taskId: "task-1", reminderAt: "2026-03-15T09:00:00Z"),
        version: self.vMid, tieBreak: .rejectEqual)
      XCTAssertEqual(try self.countDeliveryState(db, "rem-001"), 0)
    }
  }

  // MARK: - task_reminder delete

  func testTaskReminderDeleteRemovesReminder() throws {
    try withDB { db in
      try self.insertTask(db, "task-1")
      try ApplyChild.applyTaskReminderUpsert(
        db, entityId: "rem-001",
        payload: self.taskReminderPayload(taskId: "task-1", reminderAt: "2026-03-15T09:00:00Z"),
        version: self.vMid, tieBreak: .rejectEqual)
      XCTAssertEqual(try self.countTaskReminders(db), 1)
      try ApplyChild.applyTaskReminderDelete(db, entityId: "rem-001", version: self.vNew)
      XCTAssertEqual(try self.countTaskReminders(db), 0)
    }
  }

  func testTaskReminderStaleDeleteIsRefusedByInRowLwwGuard() throws {
    try withDB { db in
      try self.insertTask(db, "task-1")
      try ApplyChild.applyTaskReminderUpsert(
        db, entityId: "rem-stay",
        payload: self.taskReminderPayload(taskId: "task-1", reminderAt: "2026-03-15T09:00:00Z"),
        version: self.vNew, tieBreak: .rejectEqual)
      XCTAssertEqual(try self.countTaskReminders(db), 1)

      try ApplyChild.applyTaskReminderDelete(db, entityId: "rem-stay", version: self.vOld)
      XCTAssertEqual(
        try self.countTaskReminders(db), 1,
        "stale delete (V_OLD) MUST NOT remove a child row at V_NEW")
    }
  }

}
