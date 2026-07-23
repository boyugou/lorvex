import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Horizon-reap retention for budget-exempt HOLD rows.
///
/// A budget-exempt HOLD (schema-too-new, unknown-entity-type future record, or
/// aggregate-invariant standing refusal) parks data the CloudKit change token
/// has already advanced past — the pending-inbox row is the ONLY local copy.
/// The horizon GC must therefore never reap it: an un-updated device would
/// silently lose the future-schema envelope and later overwrite the peer's
/// newer state with a dominating local HLC. Ordinary deferrals (`fk_unresolved`
/// orphans) are still reaped at the horizon exactly as before.
///
/// Growth stays bounded: superseded parked versions of the same
/// `(entity_type, entity_id)` coalesce at the horizon down to the newest parked
/// version, and a retained hold leaves an `error_logs` breadcrumb (deduped on
/// the retained-count checkpoint) so the standing condition is observable.
final class PendingInboxHoldRetentionTests: XCTestCase {

  private static let agedTimestamp = "2000-01-01T00:00:00.000Z"

  /// Insert a pending row with explicit reason / identity / age.
  private func seedRow(
    _ db: Database, entityType: String = EntityName.task, entityId: String,
    version: String = "1711234567890_0000_a1b2c3d4a1b2c3d4",
    reason: String, firstAttemptedAt: String = agedTimestamp
  ) throws {
    try db.execute(
      sql: """
        INSERT INTO sync_pending_inbox (
            envelope, reason, missing_entity_type, missing_entity_id,
            envelope_entity_type, envelope_entity_id, envelope_version,
            first_attempted_at, last_attempted_at, attempt_count
         ) VALUES (?, ?, NULL, NULL, ?, ?, ?, ?, ?, 1)
        """,
      arguments: [
        #"{"entity_type":"\#(entityType)","entity_id":"\#(entityId)"}"#, reason,
        entityType, entityId, version, firstAttemptedAt, firstAttemptedAt,
      ])
  }

  private func pendingEntityIds(_ db: Database) throws -> Set<String> {
    Set(try String.fetchAll(db, sql: "SELECT envelope_entity_id FROM sync_pending_inbox"))
  }

  private func retainedBreadcrumbCount(_ db: Database) throws -> Int {
    try Int.fetchOne(
      db,
      sql: "SELECT COUNT(*) FROM error_logs WHERE source = ?",
      arguments: ["sync.retention.pending_inbox_hold_retained"]) ?? 0
  }

  /// The core fix: every budget-exempt HOLD flavor survives the horizon reap
  /// while an ordinary expired `fk_unresolved` deferral in the same sweep is
  /// still deleted.
  func testHorizonReapRetainsBudgetExemptHoldsAndReapsOrdinaryDeferral() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try self.seedRow(
        db, entityId: "hold-schema-too-new",
        reason: DeferralReason.schemaTooNew(remoteVersion: 99, localVersion: 1).message)
      try self.seedRow(
        db, entityId: "hold-future-kind",
        reason: PendingInboxDrain.entityTypeTooNewReason)
      try self.seedRow(
        db, entityType: EntityName.list, entityId: "hold-invariant",
        reason: DeferralReason.aggregateInvariantBlocked(
          entityType: .list, entityId: "hold-invariant", invariant: "at_least_one_list"
        ).message)
      try self.seedRow(db, entityId: "orphan-expired", reason: "fk_unresolved")
      XCTAssertEqual(try PendingInbox.countPending(db), 4)

      SyncRetention.runPostApplyGC(
        db, syncedAt: SyncTimestampFormat.syncTimestampNow())

      XCTAssertEqual(
        try self.pendingEntityIds(db),
        ["hold-schema-too-new", "hold-future-kind", "hold-invariant"],
        "the only local copy of a parked future/held envelope must survive the horizon; "
          + "the ordinary orphan is still reaped")
    }
  }

  /// Growth bound: two parked versions of the same entity coalesce at the
  /// horizon down to the newest parked version. The supersede check is scoped
  /// to budget-exempt rows — a newer NON-exempt pending version of the same
  /// entity does not license deleting the hold (that row is itself reapable /
  /// quarantinable, so the hold may still be the only durable copy).
  func testHorizonReapCoalescesSupersededHoldVersions() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      // Entity A: two aged parked versions of the same future record.
      try self.seedRow(
        db, entityId: "entity-a", version: "1711234567890_0000_a1b2c3d4a1b2c3d4",
        reason: PendingInboxDrain.entityTypeTooNewReason)
      try self.seedRow(
        db, entityId: "entity-a", version: "1711234567891_0000_a1b2c3d4a1b2c3d4",
        reason: PendingInboxDrain.entityTypeTooNewReason)
      // Entity B: an aged hold plus a newer NON-exempt deferral of the same
      // entity. The hold must NOT be coalesced away against it.
      try self.seedRow(
        db, entityId: "entity-b", version: "1711234567890_0000_b1b2c3d4b1b2c3d4",
        reason: DeferralReason.schemaTooNew(remoteVersion: 99, localVersion: 1).message)
      try self.seedRow(
        db, entityId: "entity-b", version: "1711234567891_0000_b1b2c3d4b1b2c3d4",
        reason: "fk_unresolved",
        firstAttemptedAt: SyncTimestampFormat.syncTimestampNow())

      SyncRetention.runPostApplyGC(
        db, syncedAt: SyncTimestampFormat.syncTimestampNow())

      let survivingVersionsA = try String.fetchAll(
        db,
        sql: """
          SELECT envelope_version FROM sync_pending_inbox WHERE envelope_entity_id = 'entity-a'
          """)
      XCTAssertEqual(
        survivingVersionsA, ["1711234567891_0000_a1b2c3d4a1b2c3d4"],
        "an expired hold superseded by a newer parked hold version coalesces to the newest")

      let survivingReasonsB = Set(
        try String.fetchAll(
          db,
          sql: "SELECT reason FROM sync_pending_inbox WHERE envelope_entity_id = 'entity-b'"))
      XCTAssertTrue(
        survivingReasonsB.contains { $0.hasPrefix(DeferralReason.schemaTooNewReasonMarker) },
        "a newer non-exempt deferral must not coalesce away the hold (got: \(survivingReasonsB))")
    }
  }

  /// Observability: a hold retained past the horizon leaves an error-level
  /// `error_logs` breadcrumb, deduped on the retained-count checkpoint so an
  /// unchanged standing condition does not breadcrumb on every sweep.
  func testRetainedHoldBreadcrumbDedupesOnUnchangedCount() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try self.seedRow(
        db, entityId: "hold-observable",
        reason: PendingInboxDrain.entityTypeTooNewReason)

      SyncRetention.runPostApplyGC(
        db, syncedAt: SyncTimestampFormat.syncTimestampNow())
      XCTAssertEqual(
        try self.retainedBreadcrumbCount(db), 1,
        "the first sweep retaining a hold past the horizon breadcrumbs once")

      SyncRetention.runPostApplyGC(
        db, syncedAt: SyncTimestampFormat.syncTimestampNow())
      XCTAssertEqual(
        try self.retainedBreadcrumbCount(db), 1,
        "an unchanged retained count must not breadcrumb again")

      try self.seedRow(
        db, entityId: "hold-observable-2",
        reason: DeferralReason.schemaTooNew(remoteVersion: 99, localVersion: 1).message)
      SyncRetention.runPostApplyGC(
        db, syncedAt: SyncTimestampFormat.syncTimestampNow())
      XCTAssertEqual(
        try self.retainedBreadcrumbCount(db), 2,
        "a changed retained count breadcrumbs again")
    }
  }

  /// A fresh (pre-horizon) ordinary deferral is untouched by the sweep — the
  /// exemption narrows the reap, it does not widen it.
  func testRecentOrdinaryDeferralStillRetained() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try self.seedRow(
        db, entityId: "orphan-recent", reason: "fk_unresolved",
        firstAttemptedAt: SyncTimestampFormat.syncTimestampNow())

      SyncRetention.runPostApplyGC(
        db, syncedAt: SyncTimestampFormat.syncTimestampNow())

      XCTAssertEqual(try PendingInbox.countPending(db), 1)
    }
  }
}
