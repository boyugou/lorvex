import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// DEFECT 6 regression: a task_dependency cycle-break verdict must PROPAGATE to
/// the server. When two peers each add an edge that, merged, closes a cycle, the
/// deterministic HLC-min loser is deleted + tombstoned locally on the peer that
/// holds it — but that peer never enqueued an outbox delete, so the loser's
/// server record stayed a live upsert. A brand-new device (or a
/// changeTokenExpired full replay) that later sees the loser live while the
/// winner has been deleted RESURRECTS the dropped edge — permanent divergence.
final class CycleBreakPropagationTests: XCTestCase {
  private var registry: EntityApplierRegistry {
    EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
  }

  private let t1 = "01966a3f-7c8b-7d4e-8f3a-00000000b001"
  private let t2 = "01966a3f-7c8b-7d4e-8f3a-00000000b002"
  private let v1 = "1711234567890_0000_a1b2c3d4a1b2c3d4"  // E1 t1->t2 (SCC-min, loses)
  private let v2 = "1711234567899_0000_a1b2c3d4a1b2c3d4"  // E2 t2->t1 (newer, wins)

  private func seedTask(_ db: Database, _ id: String) throws {
    try db.execute(
      sql: """
        INSERT INTO tasks (id, list_id, title, status, version, created_at, updated_at, defer_count)
        VALUES (?, 'inbox', 'T', 'open', '0000000000000_0000_0000000000000000',
                '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z', 0)
        """,
      arguments: [id])
  }

  func testCycleBreakLoserIsPropagatedAsDeleteNotLeftLiveUpsert() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try self.seedTask(db, self.t1)
      try self.seedTask(db, self.t2)

      // Device A authors E1 (t1->t2): the edge row plus its queued outbound upsert.
      try db.execute(
        sql: """
          INSERT INTO task_dependencies (task_id, depends_on_task_id, created_at, version)
          VALUES (?, ?, '2026-01-01T00:00:00.000Z', ?)
          """,
        arguments: [self.t1, self.t2, self.v1])
      try OutboxEnqueue.enqueuePayloadUpsert(
        db, entityType: EdgeName.taskDependency, entityId: "\(self.t1):\(self.t2)",
        payload: .object([
          "created_at": .string("2026-01-01T00:00:00.000Z"),
          "depends_on_task_id": .string(self.t2),
          "task_id": .string(self.t1),
        ]),
        context: OutboxWriteContext(
          version: self.v1, deviceId: "device-a"))

      // A receives B's E2 (t2->t1) at a higher HLC → closes a cycle → E1 (SCC-min)
      // loses and is dropped locally.
      let e2 = try SyncTestSupport.completeEnvelope(
        entityType: .taskDependency, entityId: "\(self.t2):\(self.t1)", operation: .upsert,
        version: try Hlc.parse(self.v2), payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: #"{"created_at":"2026-01-01T00:00:01.000Z"}"#, deviceId: "device-b")
      XCTAssertEqual(try Apply.applyEnvelope(db, registry: self.registry, envelope: e2), .applied)

      let e1Present =
        (try Int64.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM task_dependencies WHERE task_id=? AND depends_on_task_id=?",
          arguments: [self.t1, self.t2]) ?? 0) > 0
      XCTAssertFalse(e1Present, "the loser edge E1 is dropped locally")

      // THE FIX: A's outbound for E1 is a DELETE (the propagated tombstone),
      // superseding the queued upsert — so no live upsert survives to resurrect
      // E1 on a fresh replaying peer.
      let e1Ops = try String.fetchAll(
        db,
        sql: "SELECT operation FROM sync_outbox WHERE entity_type='task_dependency' AND entity_id=?",
        arguments: ["\(self.t1):\(self.t2)"])
      XCTAssertTrue(
        e1Ops.contains(SyncNaming.opDelete),
        "the cycle-break loser is propagated to the server as a delete; got \(e1Ops)")
      XCTAssertFalse(
        e1Ops.contains(SyncNaming.opUpsert),
        "no live upsert for the loser survives outbound; got \(e1Ops)")

      // And the delete carries a version that dominates the loser's — so it wins
      // LWW against the loser's live server record.
      let deleteVersion = try String.fetchOne(
        db,
        sql: """
          SELECT version FROM sync_outbox
          WHERE entity_type='task_dependency' AND entity_id=? AND operation='delete'
          """,
        arguments: ["\(self.t1):\(self.t2)"])
      XCTAssertEqual(deleteVersion, self.v2, "the loser delete rides the winning decision HLC")
    }
  }

  /// End-to-end convergence: a fresh peer that replays the propagated tombstone
  /// (loser delete) plus the winner edge does NOT resurrect the loser, even when
  /// the delete arrives before a stray upsert would (the resurrection-prone order).
  func testFreshPeerDoesNotResurrectLoserAfterPropagation() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try self.seedTask(db, self.t1)
      try self.seedTask(db, self.t2)

      // The propagated loser tombstone (delete @ v2) lands first...
      let loserDelete = try SyncTestSupport.completeEnvelope(
        entityType: .taskDependency, entityId: "\(self.t1):\(self.t2)", operation: .delete,
        version: try Hlc.parse(self.v2), payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: "{}", deviceId: "device-a")
      XCTAssertEqual(try Apply.applyEnvelope(db, registry: self.registry, envelope: loserDelete), .applied)

      // ...then a stale loser upsert (@ v1) arrives — it must be rejected by the
      // tombstone, not resurrect the edge.
      let staleLoserUpsert = try SyncTestSupport.completeEnvelope(
        entityType: .taskDependency, entityId: "\(self.t1):\(self.t2)", operation: .upsert,
        version: try Hlc.parse(self.v1), payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: #"{"created_at":"2026-01-01T00:00:00.000Z"}"#, deviceId: "device-a")
      _ = try Apply.applyEnvelope(db, registry: self.registry, envelope: staleLoserUpsert)

      let e1Present =
        (try Int64.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM task_dependencies WHERE task_id=? AND depends_on_task_id=?",
          arguments: [self.t1, self.t2]) ?? 0) > 0
      XCTAssertFalse(e1Present, "the propagated tombstone keeps the loser dead on a fresh peer")
    }
  }
}
