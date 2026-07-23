import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Regression coverage for the "a deferred apply is side-effect-free" invariant
/// (FND-APPLY-1): a `.deferred` outcome from
/// ``Apply/applyEnvelope(_:registry:envelope:)`` MUST leave the database
/// byte-identical to before the envelope was attempted.
///
/// The upsert-wins-over-delete tombstone gate mutates the DB (removes an existing
/// tombstone, logs a conflict) BEFORE the later FK gate can defer on a missing
/// parent. Without per-envelope rollback on defer, that removal persists even
/// though the upsert never applied — making inbound convergence order-dependent:
/// depending on whether the delete or the upsert arrives first, the final state
/// differs and a deleted row can be resurrected.
final class ApplyDeferAtomicityTests: XCTestCase {

  private let suffix = "a1b2c3d4a1b2c3d4"
  private func v(_ ms: UInt64, _ ctr: UInt32 = 0) -> String {
    "\(String(format: "%013d", ms))_\(String(format: "%04d", ctr))_\(suffix)"
  }

  // Canonical UUIDv7-shaped ids the apply entry-point's entity_id validation admits.
  private let reminderX = "bbbbbbbb-bbbb-7bbb-8bbb-bbbbbbbbbbbb"
  private let missingTask = "cccccccc-cccc-7ccc-8ccc-cccccccccccc"

  private func registry() -> EntityApplierRegistry {
    EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
  }

  private func withDB(_ body: (Database) throws -> Void) throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in try body(db) }
  }

  /// A `task_reminder` upsert whose `task_id` FK parent is absent, so the FK gate
  /// defers the envelope to the pending inbox.
  private func reminderUpsert(_ id: String, _ version: String) throws -> SyncEnvelope {
    try SyncTestSupport.completeEnvelope(
      entityType: .taskReminder, entityId: id, operation: .upsert,
      version: try Hlc.parse(version),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: "{\"task_id\":\"\(self.missingTask)\"}", deviceId: "device-remote")
  }

  private func conflictCount(_ db: Database) throws -> Int64 {
    try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_conflict_log") ?? -1
  }

  // MARK: - Direct tombstone gate

  /// An upsert that BEATS an existing real tombstone (removing it in the tombstone
  /// gate) but then DEFERS on a missing FK parent must roll the removal back: the
  /// tombstone survives so a later-arriving order cannot resurrect the deleted row,
  /// and no conflict-log row is left for a resolution that has not actually
  /// happened.
  func testDeferredUpsertRollsBackTombstoneRemoval() throws {
    try withDB { db in
      try Tombstone.createTombstone(
        db, entityType: EntityName.taskReminder, entityId: self.reminderX,
        version: self.v(100), deletedAt: "del-ts")

      let env = try self.reminderUpsert(self.reminderX, self.v(200))
      let result = try Apply.applyEnvelope(db, registry: self.registry(), envelope: env)

      guard case .deferred = result else {
        return XCTFail("expected .deferred (missing FK parent), got \(result)")
      }

      // Zero net side effects on defer: the tombstone must survive intact.
      let ts = try Tombstone.getTombstone(
        db, entityType: EntityName.taskReminder, entityId: self.reminderX)
      XCTAssertNotNil(ts, "a deferred upsert must not persist its tombstone removal")
      XCTAssertEqual(ts?.version, self.v(100))
      XCTAssertEqual(
        try self.conflictCount(db), 0,
        "a deferred upsert must not persist a conflict-log row for an unresolved conflict")
    }
  }

}
