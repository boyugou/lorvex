import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// DEFECT 8 (schema audit F1-1) regression: the horizon GC hard-deletes expired
/// pending-inbox rows (including unknown-entity_type HOLD rows) with no conflict
/// signal, so a device more than the horizon behind on app version silently loses
/// newer-peer records. The `reseed_required` conflict vocabulary exists in the
/// schema but had no Apple writer. The post-apply GC must now, before deleting
/// expired rows, write a `reseed_required` conflict-log row and a
/// `sync_checkpoints['reseed_required']='true'` marker so the loss is visible.
final class PendingInboxReseedSignalTests: XCTestCase {

  private func insertAgedPendingRow(_ db: Database, entityId: String) throws {
    try db.execute(
      sql: """
        INSERT INTO sync_pending_inbox (
            envelope, reason, missing_entity_type, missing_entity_id,
            envelope_entity_type, envelope_entity_id, envelope_version,
            first_attempted_at, last_attempted_at, attempt_count
         ) VALUES (?, ?, ?, ?, ?, ?, ?, '2000-01-01T00:00:00.000Z', '2000-01-01T00:00:00.000Z', 1)
        """,
      arguments: [
        #"{"entity_type":"task","entity_id":"\#(entityId)"}"#, "fk_unresolved",
        EntityName.list, "01966a3f-7c8b-7d4e-8f3a-0000000000ff",
        EntityName.task, entityId, "1711234567890_0000_a1b2c3d4a1b2c3d4",
      ])
  }

  func testExpiredPendingInboxWritesReseedRequiredSignalBeforeDeletion() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try self.insertAgedPendingRow(db, entityId: "01966a3f-7c8b-7d4e-8f3a-0000000000a1")
      XCTAssertEqual(try PendingInbox.countPending(db), 1)

      SyncRetention.runPostApplyGC(
        db, syncedAt: SyncTimestampFormat.syncTimestampNow())

      // The expired row was reaped (unchanged behavior).
      XCTAssertEqual(try PendingInbox.countPending(db), 0, "the expired row is GC'd")

      // A reseed_required conflict-log row makes the loss visible.
      let conflicts =
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM sync_conflict_log WHERE resolution_type = 'reseed_required'")
        ?? 0
      XCTAssertGreaterThanOrEqual(conflicts, 1, "a reseed_required conflict row is written")

      // And a checkpoint marker the host can surface.
      let marker = try String.fetchOne(
        db, sql: "SELECT value FROM sync_checkpoints WHERE key = 'reseed_required'")
      XCTAssertEqual(marker, "true", "the reseed_required checkpoint marker is set")
    }
  }

  /// Insert an aged pending row carrying an arbitrary `reason` (defaults to a
  /// budget-exempt aggregate-invariant HOLD message) so retention treats it as a
  /// by-design hold rather than an orphan.
  private func insertAgedRowWithReason(_ db: Database, entityId: String, reason: String) throws {
    try db.execute(
      sql: """
        INSERT INTO sync_pending_inbox (
            envelope, reason, missing_entity_type, missing_entity_id,
            envelope_entity_type, envelope_entity_id, envelope_version,
            first_attempted_at, last_attempted_at, attempt_count
         ) VALUES (?, ?, NULL, NULL, ?, ?, ?, '2000-01-01T00:00:00.000Z', '2000-01-01T00:00:00.000Z', 1)
        """,
      arguments: [
        #"{"entity_type":"list","entity_id":"\#(entityId)"}"#, reason,
        EntityName.list, entityId, "1711234567890_0000_a1b2c3d4a1b2c3d4",
      ])
  }

  /// SYNC-MED-3: an expired budget-exempt HOLD row (a correct standing refusal or
  /// a not-yet-understood future record) must NOT raise `reseed_required` — a
  /// full reseed re-pulls the same record and re-creates the same hold, so the
  /// signal would loop a futile reseed prompt. It is also retained, not reaped:
  /// the hold is the only local copy of the record (retention coverage in
  /// `PendingInboxHoldRetentionTests`).
  func testExpiredBudgetExemptHoldDoesNotRaiseReseed() throws {
    let holdReasons = [
      DeferralReason.aggregateInvariantBlocked(
        entityType: .list, entityId: "l-ghost", invariant: "at_least_one_list"
      ).message,
      DeferralReason.schemaTooNew(remoteVersion: 99, localVersion: 1).message,
      PendingInboxDrain.entityTypeTooNewReason,
    ]
    for (idx, reason) in holdReasons.enumerated() {
      let store = try SyncTestSupport.freshStore()
      try store.writer.write { db in
        try self.insertAgedRowWithReason(
          db, entityId: "01966a3f-7c8b-7d4e-8f3a-00000000b1\(idx)", reason: reason)
        XCTAssertEqual(try PendingInbox.countPending(db), 1)

        SyncRetention.runPostApplyGC(
          db, syncedAt: SyncTimestampFormat.syncTimestampNow())

        // Retained past the horizon (the row is the only local copy)…
        XCTAssertEqual(
          try PendingInbox.countPending(db), 1,
          "the expired hold is retained, not reaped (reason: \(reason))")
        // …and no reseed signal is raised for a by-design hold.
        let conflicts =
          try Int64.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM sync_conflict_log WHERE resolution_type = 'reseed_required'")
          ?? -1
        XCTAssertEqual(conflicts, 0, "a budget-exempt hold must not raise reseed (reason: \(reason))")
        let marker = try String.fetchOne(
          db, sql: "SELECT value FROM sync_checkpoints WHERE key = 'reseed_required'")
        XCTAssertNil(marker, "no reseed checkpoint for a by-design hold (reason: \(reason))")
      }
    }
  }

  /// The exclusion is scoped: a genuine orphan (`fk_unresolved` / missing
  /// dependency) alongside a budget-exempt hold still raises reseed exactly once —
  /// the hold does not, but the orphan does.
  func testGenuineOrphanStillRaisesReseedAlongsideExemptHold() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try self.insertAgedRowWithReason(
        db, entityId: "01966a3f-7c8b-7d4e-8f3a-00000000b201",
        reason: DeferralReason.aggregateInvariantBlocked(
          entityType: .list, entityId: "l-ghost", invariant: "at_least_one_list"
        ).message)
      try self.insertAgedPendingRow(db, entityId: "01966a3f-7c8b-7d4e-8f3a-00000000b202")

      SyncRetention.runPostApplyGC(
        db, syncedAt: SyncTimestampFormat.syncTimestampNow())

      let marker = try String.fetchOne(
        db, sql: "SELECT value FROM sync_checkpoints WHERE key = 'reseed_required'")
      XCTAssertEqual(marker, "true", "the genuine orphan still raises reseed")
    }
  }

  /// No expired rows → no reseed signal (the GC's normal quiet path).
  func testNoReseedSignalWhenNothingExpired() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      SyncRetention.runPostApplyGC(
        db, syncedAt: SyncTimestampFormat.syncTimestampNow())
      let conflicts =
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM sync_conflict_log WHERE resolution_type = 'reseed_required'")
        ?? 0
      XCTAssertEqual(conflicts, 0)
      let marker = try String.fetchOne(
        db, sql: "SELECT value FROM sync_checkpoints WHERE key = 'reseed_required'")
      XCTAssertNil(marker)
    }
  }
}
