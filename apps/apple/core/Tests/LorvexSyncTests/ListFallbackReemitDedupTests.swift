import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// SYNC17-HIGH-1 regression: the `resolveListId` list-fallback convergence
/// re-emit must fire AT MOST ONCE per `(entity_id, payload_list_id)` per device.
///
/// Two devices whose fallback targets are mutually tombstoned (A holds
/// `inbox`+tombstone(L); B holds L+tombstone(inbox)) otherwise re-resolve each
/// other's re-emits forever: every hop mints a strictly greater HLC (always
/// applies, never LWW-skipped) and re-triggers convergence re-emit detection on
/// the peer. Without a dedup ledger the flap is unbounded. The dedicated durable
/// claim ledger bounds it to one re-emit per side.
///
/// The absence-preserve re-emit arm is deliberately NOT deduped (it is proven not
/// to loop), so a repeated attendee-omitting envelope keeps re-emitting.
final class ListFallbackReemitDedupTests: XCTestCase {
  private var registry: EntityApplierRegistry {
    EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
  }

  private let taskT = "01966a3f-7c8b-7d4e-8f3a-00000000f001"
  private let listL = "01966a3f-7c8b-7d4e-8f3a-00000000f0a1"
  private let listL2 = "01966a3f-7c8b-7d4e-8f3a-00000000f0a2"

  private func taskEnvelope(
    listId: String, version: String, title: String = "T", contentVersion: String? = nil
  ) -> SyncEnvelope {
    let base = try! SyncTestSupport.completeEnvelope(
      entityType: .task, entityId: taskT, operation: .upsert,
      version: try! Hlc.parse(version), payloadSchemaVersion: 1,
      payload: """
        {"list_id":"\(listId)","title":"\(title)","status":"open",\
        "created_at":"2026-01-01T09:00:00.000Z","updated_at":"2026-01-01T09:00:00.000Z",\
        "defer_count":0}
        """,
      deviceId: "device-001")
    guard let contentVersion,
      case .object(var payload)? = JSONValue.parse(base.payload)
    else { return base }
    payload["content_version"] = .string(contentVersion)
    return SyncEnvelope(
      entityType: base.entityType, entityId: base.entityId, operation: base.operation,
      version: base.version, payloadSchemaVersion: base.payloadSchemaVersion,
      payload: try! SyncCanonicalize.canonicalizeJSON(.object(payload)),
      deviceId: base.deviceId)
  }

  private func ordinaryListTombstone(_ db: Database, _ listId: String, version: String) throws {
    try Tombstone.createTombstone(
      db, entityType: EntityName.list, entityId: listId,
      version: version, deletedAt: "2026-01-01T09:00:01.000Z")
  }

  private func taskListId(_ db: Database) throws -> String? {
    try String.fetchOne(db, sql: "SELECT list_id FROM tasks WHERE id = ?", arguments: [taskT])
  }

  private func reemitLedgerCount(_ db: Database) throws -> Int64 {
    try Int64.fetchOne(
      db,
      sql: """
        SELECT COUNT(*) FROM sync_list_fallback_reemit_claims
         WHERE task_id = ?
        """,
      arguments: [taskT]) ?? -1
  }

  /// A task naming a tombstoned list rehomes to inbox and re-emits ONCE; every
  /// later apply of a strictly-newer envelope naming the SAME list rehomes again
  /// but must NOT re-emit — the dedup ledger short-circuits the ping-pong. Pre-fix
  /// `convergenceReemitTarget` returned non-nil on every hop (unbounded re-emit).
  func testListFallbackReemitDedupesPerEntityAndListPreventingPingPong() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try self.ordinaryListTombstone(
        db, self.listL, version: "1711234567000_0000_a1b2c3d4a1b2c3d4")

      // Hop 1: apply the task naming L → rehomes to inbox → first re-emit fires.
      let env1 = self.taskEnvelope(listId: self.listL, version: "1711234567890_0000_a1b2c3d4a1b2c3d4")
      guard case .applied = try Apply.applyEnvelope(db, registry: self.registry, envelope: env1) else {
        return XCTFail("env1 must apply (rehome to inbox)")
      }
      XCTAssertEqual(try self.taskListId(db), "inbox")
      let target1 = try XCTUnwrap(
        AbsencePreserveReemit.convergenceReemitTarget(db, envelope: env1),
        "the first list-fallback divergence must re-emit")
      XCTAssertEqual(
        try self.reemitLedgerCount(db), 0,
        "detection must not claim the ledger before the re-emit enqueue succeeds")
      try AbsencePreserveReemit.recordConvergenceReemitEnqueued(db, target: target1)

      // Hop 2: a strictly-newer envelope naming the SAME tombstoned list. Applies
      // (never LWW-skipped) and rehomes again, but the re-emit is deduped.
      let env2 = self.taskEnvelope(listId: self.listL, version: "1711234567891_0000_a1b2c3d4a1b2c3d4")
      guard case .applied = try Apply.applyEnvelope(db, registry: self.registry, envelope: env2) else {
        return XCTFail("env2 must apply")
      }
      XCTAssertNil(
        try AbsencePreserveReemit.convergenceReemitTarget(db, envelope: env2),
        "a second hop naming the same list must NOT re-emit (deduped) — pre-fix this looped forever")

      // Hop 3: still deduped.
      let env3 = self.taskEnvelope(listId: self.listL, version: "1711234567892_0000_a1b2c3d4a1b2c3d4")
      _ = try Apply.applyEnvelope(db, registry: self.registry, envelope: env3)
      XCTAssertNil(
        try AbsencePreserveReemit.convergenceReemitTarget(db, envelope: env3),
        "subsequent hops stay deduped")

      XCTAssertEqual(
        try self.reemitLedgerCount(db), 1,
        "exactly one list-fallback ledger row for (task, L)")
    }
  }

  /// The dedup key is `(entity_id, payload_list_id)`: a task that later names a
  /// DIFFERENT tombstoned list re-emits once for that new list even after the
  /// first list was claimed.
  func testListFallbackReemitClaimIsPerPayloadList() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try self.ordinaryListTombstone(
        db, self.listL, version: "1711234567000_0000_a1b2c3d4a1b2c3d4")
      try self.ordinaryListTombstone(
        db, self.listL2, version: "1711234567001_0000_a1b2c3d4a1b2c3d4")

      let env1 = self.taskEnvelope(listId: self.listL, version: "1711234567890_0000_a1b2c3d4a1b2c3d4")
      _ = try Apply.applyEnvelope(db, registry: self.registry, envelope: env1)
      let target1 = try XCTUnwrap(
        AbsencePreserveReemit.convergenceReemitTarget(db, envelope: env1))
      try AbsencePreserveReemit.recordConvergenceReemitEnqueued(db, target: target1)

      let env2 = self.taskEnvelope(listId: self.listL, version: "1711234567891_0000_a1b2c3d4a1b2c3d4")
      _ = try Apply.applyEnvelope(db, registry: self.registry, envelope: env2)
      XCTAssertNil(try AbsencePreserveReemit.convergenceReemitTarget(db, envelope: env2))

      // The same task now names a DIFFERENT tombstoned list → a distinct ledger key.
      let env3 = self.taskEnvelope(listId: self.listL2, version: "1711234567892_0000_a1b2c3d4a1b2c3d4")
      _ = try Apply.applyEnvelope(db, registry: self.registry, envelope: env3)
      let target3 = try XCTUnwrap(
        AbsencePreserveReemit.convergenceReemitTarget(db, envelope: env3),
        "a re-emit for a different payload list_id fires once")
      try AbsencePreserveReemit.recordConvergenceReemitEnqueued(db, target: target3)

      let env4 = self.taskEnvelope(listId: self.listL2, version: "1711234567893_0000_a1b2c3d4a1b2c3d4")
      _ = try Apply.applyEnvelope(db, registry: self.registry, envelope: env4)
      XCTAssertNil(try AbsencePreserveReemit.convergenceReemitTarget(db, envelope: env4))

      XCTAssertEqual(
        try self.reemitLedgerCount(db), 2,
        "one ledger row per distinct (task, payload list_id)")
    }
  }

  func testClaimedListFallbackDoesNotSuppressIndependentTaskRegisterDivergence() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      let v1 = "1711234567890_0000_a1b2c3d4a1b2c3d4"
      let localV2 = "1711234567891_0000_b1b2c3d4a1b2c3d4"
      let inboundV3 = "1711234567892_0000_a1b2c3d4a1b2c3d4"
      try self.ordinaryListTombstone(
        db, self.listL, version: "1711234567000_0000_a1b2c3d4a1b2c3d4")

      let first = self.taskEnvelope(listId: self.listL, version: v1)
      _ = try Apply.applyEnvelope(db, registry: self.registry, envelope: first)
      let firstTarget = try XCTUnwrap(
        AbsencePreserveReemit.convergenceReemitTarget(db, envelope: first))
      try AbsencePreserveReemit.recordConvergenceReemitEnqueued(db, target: firstTarget)

      // A local content write advances only the content register. A later
      // transport envelope still names the already-claimed tombstoned list but
      // carries the older content register, so list normalization must not hide
      // the independent joined-title divergence.
      try db.execute(
        sql: """
          UPDATE tasks
             SET title = 'Local title', content_version = ?, version = ?,
                 updated_at = '2026-01-01T09:00:02.000Z'
           WHERE id = ?
          """,
        arguments: [localV2, localV2, self.taskT])
      let later = self.taskEnvelope(
        listId: self.listL, version: inboundV3,
        title: "Stale remote title", contentVersion: v1)
      _ = try Apply.applyEnvelope(db, registry: self.registry, envelope: later)

      let groupedTarget = try XCTUnwrap(
        AbsencePreserveReemit.convergenceReemitTarget(db, envelope: later))
      XCTAssertNil(
        groupedTarget.listFallbackPayloadListId,
        "the remaining register divergence is not governed by the list ledger")
      XCTAssertEqual(try self.reemitLedgerCount(db), 1)
    }
  }

  /// Claims are correctness state, not age-bounded diagnostics. Their lifecycle
  /// ends when the owning task does, via the schema FK cascade.
  func testListFallbackClaimCascadesWhenOwningTaskIsDeleted() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try self.ordinaryListTombstone(
        db, self.listL, version: "1711234567000_0000_a1b2c3d4a1b2c3d4")
      let envelope = self.taskEnvelope(
        listId: self.listL, version: "1711234567890_0000_a1b2c3d4a1b2c3d4")
      _ = try Apply.applyEnvelope(db, registry: self.registry, envelope: envelope)
      let target = try XCTUnwrap(
        AbsencePreserveReemit.convergenceReemitTarget(db, envelope: envelope))
      try AbsencePreserveReemit.recordConvergenceReemitEnqueued(db, target: target)
      XCTAssertEqual(try self.reemitLedgerCount(db), 1)

      try db.execute(sql: "DELETE FROM tasks WHERE id = ?", arguments: [self.taskT])
      XCTAssertEqual(
        try self.reemitLedgerCount(db), 0,
        "task lifecycle deletion must not leak a permanent re-emit claim")
    }
  }
}
