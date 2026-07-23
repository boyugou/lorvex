import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

/// Ports the store-layer (raw-SQL CRUD) cases from the Rust
/// `lorvex-sync::pending_inbox::tests` suite. These tests seed via the same
/// INSERT shape directly so the store-layer reads/writes are exercised without
/// coupling raw CRUD coverage to the apply-aware drain path.
final class PendingInboxStoreTests: XCTestCase {
  private let fkUnresolved = ResolutionName.fkUnresolved
  private let entityTask = EntityKind.task.asString
  private let entityTaskReminder = EntityKind.taskReminder.asString

  private func freshDB() throws -> LorvexStore { try TestSupport.freshStore() }

  /// Mirror the `enqueue_pending` INSERT shape. The `envelope` column stores a
  /// minimal JSON object carrying the entity_id so the test can read it back
  /// without pulling in `SyncEnvelope` parsing.
  private func seed(
    _ db: Database, entityType: String, entityID: String, reason: String,
    missingType: String?, missingID: String?
  ) throws {
    let envelopeJSON = "{\"entity_id\":\"\(entityID)\"}"
    try db.execute(
      sql: """
        INSERT INTO sync_pending_inbox
          (envelope, reason, missing_entity_type, missing_entity_id,
           envelope_entity_type, envelope_entity_id, envelope_version,
           first_attempted_at, last_attempted_at, attempt_count)
        VALUES (?, ?, ?, ?, ?, ?, ?,
                strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
                strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
                1)
        """,
      arguments: [
        envelopeJSON, reason, missingType, missingID, entityType, entityID,
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
      ])
  }

  func testSeedAndGetPending() throws {
    let store = try freshDB()
    try store.writer.write { db in
      try self.seed(
        db, entityType: self.entityTaskReminder, entityID: "reminder-001",
        reason: self.fkUnresolved, missingType: self.entityTask,
        missingID: "01966a3f-7c8b-7d4e-8f3a-000000002189")
      let pending = try PendingInbox.getAllPending(db)
      XCTAssertEqual(pending.count, 1)
      XCTAssertEqual(pending[0].reason, self.fkUnresolved)
      XCTAssertEqual(pending[0].missingEntityType, self.entityTask)
      XCTAssertEqual(pending[0].missingEntityID, "01966a3f-7c8b-7d4e-8f3a-000000002189")
      XCTAssertEqual(pending[0].attemptCount, 1)
    }
  }

  func testRemovePendingDeletesEntry() throws {
    let store = try freshDB()
    try store.writer.write { db in
      try self.seed(
        db, entityType: self.entityTaskReminder, entityID: "reminder-001",
        reason: self.fkUnresolved, missingType: self.entityTask, missingID: "x")
      let pending = try PendingInbox.getAllPending(db)
      try PendingInbox.removePending(db, id: pending[0].id)
      XCTAssertTrue(try PendingInbox.getAllPending(db).isEmpty)
    }
  }

  func testCountPendingEmpty() throws {
    let store = try freshDB()
    try store.writer.read { db in
      XCTAssertEqual(try PendingInbox.countPending(db), 0)
    }
  }

  func testCountPendingAfterInserts() throws {
    let store = try freshDB()
    try store.writer.write { db in
      for i in 0..<3 {
        try self.seed(
          db, entityType: self.entityTaskReminder,
          entityID: String(format: "reminder-%03d", i), reason: self.fkUnresolved,
          missingType: self.entityTask, missingID: "id-\(i)")
      }
      XCTAssertEqual(try PendingInbox.countPending(db), 3)
    }
  }

  func testEnqueueWithoutMissingInfo() throws {
    let store = try freshDB()
    try store.writer.write { db in
      try self.seed(
        db, entityType: self.entityTask, entityID: "01966a3f-7c8b-7d4e-8f3a-000000002163",
        reason: "schema_incompatible", missingType: nil, missingID: nil)
      let pending = try PendingInbox.getAllPending(db)
      XCTAssertEqual(pending.count, 1)
      XCTAssertNil(pending[0].missingEntityType)
      XCTAssertNil(pending[0].missingEntityID)
    }
  }

  func testFifoOrdering() throws {
    let store = try freshDB()
    try store.writer.write { db in
      for i in 0..<5 {
        try self.seed(
          db, entityType: self.entityTaskReminder,
          entityID: String(format: "reminder-%03d", i), reason: self.fkUnresolved,
          missingType: self.entityTask, missingID: "id-\(i)")
      }
      let pending = try PendingInbox.getAllPending(db)
      XCTAssertEqual(pending.count, 5)
      for i in 0..<4 {
        XCTAssertLessThan(pending[i].id, pending[i + 1].id, "ordered by id ASC")
      }
    }
  }

  // MARK: - has_pending_for_target (the outbox-enqueue unblock hook)

  func testHasPendingForTargetMatchesAndMisses() throws {
    let store = try freshDB()
    try store.writer.write { db in
      try self.seed(
        db, entityType: self.entityTaskReminder, entityID: "reminder-001",
        reason: self.fkUnresolved, missingType: self.entityTask, missingID: "task-parent")
      XCTAssertTrue(
        try PendingInbox.hasPendingForTarget(
          db, entityType: self.entityTask, entityID: "task-parent"))
      XCTAssertFalse(
        try PendingInbox.hasPendingForTarget(
          db, entityType: self.entityTask, entityID: "different-id"))
      XCTAssertFalse(
        try PendingInbox.hasPendingForTarget(
          db, entityType: self.entityTaskReminder, entityID: "task-parent"))
    }
  }

  // MARK: - expiry_gc

  func testGcExpiredEntriesDeletesPastHorizon() throws {
    let store = try freshDB()
    try store.writer.write { db in
      try self.seed(
        db, entityType: self.entityTaskReminder, entityID: "old-reminder",
        reason: self.fkUnresolved, missingType: nil, missingID: nil)
      try self.seed(
        db, entityType: self.entityTaskReminder, entityID: "new-reminder",
        reason: self.fkUnresolved, missingType: nil, missingID: nil)
      try db.execute(
        sql: """
          UPDATE sync_pending_inbox SET first_attempted_at = '2020-01-01T00:00:00.000Z' \
          WHERE id = (SELECT MIN(id) FROM sync_pending_inbox)
          """)
      let deleted = try PendingInbox.gcExpiredEntries(db, horizonDays: 90)
      XCTAssertEqual(deleted, 1)
      let remaining = try PendingInbox.getAllPending(db)
      XCTAssertEqual(remaining.count, 1)
      XCTAssertEqual(JSONValue.parse(remaining[0].envelopeJSON)?["entity_id"].asString, "new-reminder")
    }
  }

  func testGcExpiredEntriesKeepsRecent() throws {
    let store = try freshDB()
    try store.writer.write { db in
      try self.seed(
        db, entityType: self.entityTaskReminder, entityID: "reminder-001",
        reason: self.fkUnresolved, missingType: nil, missingID: nil)
      XCTAssertEqual(try PendingInbox.gcExpiredEntries(db, horizonDays: 90), 0)
      XCTAssertEqual(try PendingInbox.getAllPending(db).count, 1)
    }
  }

  // MARK: - reattempt accounting

  func testRecordReattemptBumpsCount() throws {
    let store = try freshDB()
    try store.writer.write { db in
      try self.seed(
        db, entityType: self.entityTaskReminder, entityID: "reminder-001",
        reason: self.fkUnresolved, missingType: self.entityTask, missingID: "x")
      let id = try PendingInbox.getAllPending(db)[0].id
      try PendingInbox.recordReattempt(db, id: id)
      XCTAssertEqual(try PendingInbox.readAttemptCount(db, id: id), 2)
    }
  }

  func testRecordReattemptBusyDoesNotBumpCount() throws {
    let store = try freshDB()
    try store.writer.write { db in
      try self.seed(
        db, entityType: self.entityTaskReminder, entityID: "reminder-001",
        reason: self.fkUnresolved, missingType: self.entityTask, missingID: "x")
      let id = try PendingInbox.getAllPending(db)[0].id
      try PendingInbox.recordReattemptBusy(db, id: id)
      XCTAssertEqual(try PendingInbox.readAttemptCount(db, id: id), 1)
    }
  }

  func testRecordReattemptWithErrorReturnsPriorAndBumps() throws {
    let store = try freshDB()
    try store.writer.write { db in
      try self.seed(
        db, entityType: self.entityTaskReminder, entityID: "reminder-001",
        reason: self.fkUnresolved, missingType: self.entityTask, missingID: "x")
      let id = try PendingInbox.getAllPending(db)[0].id
      let firstPrior = try PendingInbox.recordReattemptWithError(db, id: id, newError: "boom-1")
      XCTAssertNil(firstPrior)
      let secondPrior = try PendingInbox.recordReattemptWithError(db, id: id, newError: "boom-2")
      XCTAssertEqual(secondPrior, "boom-1")
      XCTAssertEqual(try PendingInbox.readAttemptCount(db, id: id), 3)
    }
  }
}
