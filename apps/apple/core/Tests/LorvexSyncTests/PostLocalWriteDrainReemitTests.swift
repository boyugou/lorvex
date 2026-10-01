import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// A host-level local-write finalizer must drive the same convergence re-emit the
/// inbound apply driver drives from a pending-inbox drain summary.
///
/// When a local write unblocks a parked list-delete whose replay re-homes tasks to
/// inbox (via `trg_lists_before_delete`, which bumps no version and enqueues no
/// outbox row), the re-home must be re-enqueued as a fresh-HLC task upsert so peers
/// converge. Low-level enqueue deliberately never drains: only the top-level host
/// owns both the pending removal and every resulting convergence obligation.
final class PostLocalWriteDrainReemitTests: XCTestCase {
  private let listL = "01966a3f-7c8b-7d4e-8f3a-00000000d001"
  private let taskT = "01966a3f-7c8b-7d4e-8f3a-00000000d002"
  private let parentP = "01966a3f-7c8b-7d4e-8f3a-00000000d003"

  private func seed(_ db: Database) throws {
    try db.execute(
      sql: """
        INSERT INTO lists (id, name, version, created_at, updated_at)
        VALUES (?, 'L', '0000000000000_0000_0000000000000000',
                '2026-04-19T08:00:00.000Z', '2026-04-19T08:00:00.000Z')
        """, arguments: [listL])
    // T lives in the non-inbox list L — the re-home candidate.
    try db.execute(
      sql: """
        INSERT INTO tasks (id, list_id, title, status, version, created_at, updated_at, defer_count)
        VALUES (?, ?, 'T', 'open', '0000000000000_0000_0000000000000000',
                '2026-04-19T08:00:00.000Z', '2026-04-19T08:00:00.000Z', 0)
        """, arguments: [taskT, listL])
    // P lives in inbox; the local write to P is what unblocks the parked drain
    // (its `missing_entity_id` points at P).
    try db.execute(
      sql: """
        INSERT INTO tasks (id, list_id, title, status, version, created_at, updated_at, defer_count)
        VALUES (?, 'inbox', 'P', 'open', '0000000000000_0000_0000000000000000',
                '2026-04-19T08:00:00.000Z', '2026-04-19T08:00:00.000Z', 0)
        """, arguments: [parentP])
  }

  /// A peer list-delete for L, parked in the pending inbox "waiting on" P. Its
  /// version dominates L's seeded version so the replay applies and re-homes T.
  private func parkListDelete(_ db: Database) throws {
    let envelope = SyncEnvelope(
      entityType: .list, entityId: listL, operation: .delete,
      version: try! Hlc.parse("1711234567890_0000_a1b2c3d4a1b2c3d4"),
      payloadSchemaVersion: 1,
      payload: #"{"id":"\#(listL)","name":"L","version":"1711234567890_0000_a1b2c3d4a1b2c3d4"}"#,
      deviceId: "peer-device")
    try PendingInboxDrain.enqueuePending(
      db, envelope: envelope, reason: "waiting",
      missingEntityType: EntityName.task, missingEntityID: parentP)
  }

  private func localUpsertP(
    _ db: Database, hlc: HlcState, reconcilePending: Bool
  ) throws {
    let payload = try OutboxEnqueue.readEntityPayloadSnapshot(
      db, entityType: EntityKind.task.asString, entityId: parentP)
    try OutboxEnqueue.enqueuePayloadUpsert(
      db, entityType: EntityKind.task.asString, entityId: parentP, payload: payload,
      context: OutboxWriteContext(
        version: hlc.generate().description, deviceId: "local-device"))
    guard reconcilePending else { return }
    let summary = try PendingInboxDrain.drainPendingInbox(
      db, registry: EntityApplierRegistry(
        appliers: EntityApplierRegistry.defaultEntityAppliers()))
    let mint: (Hlc?) -> String = { floor in
      if let floor { hlc.updateOnReceive(remote: floor, physicalMs: 0) }
      return hlc.generate(withPhysicalMs: 0).description
    }
    try ListDeleteRehome.reenqueueRehomed(
      db, taskIds: summary.listDeleteRehomedTaskIds,
      mintVersion: mint, deviceId: "local-device")
    for target in summary.absenceReemitTargets {
      let outcome = try ConvergenceEmitter.enqueueCurrentSnapshot(
        db, entityType: target.entityType, entityId: target.entityId,
        mintVersion: mint, deviceId: "local-device")
      if outcome == .enqueued {
        try AbsencePreserveReemit.recordConvergenceReemitEnqueued(db, target: target)
      }
    }
    for obligation in summary.repairObligations {
      try ApplyRepair.fulfill(
        db, obligation: obligation, mintVersion: mint, deviceId: "local-device")
    }
  }

  private func taskListId(_ db: Database, _ id: String) throws -> String? {
    try String.fetchOne(db, sql: "SELECT list_id FROM tasks WHERE id = ?", arguments: [id])
  }

  private func taskUpsertOutboxCount(_ db: Database, _ id: String) throws -> Int64 {
    try Int64.fetchOne(
      db,
      sql: """
        SELECT COUNT(*) FROM sync_outbox
        WHERE entity_type = 'task' AND entity_id = ? AND operation = 'upsert'
        """,
      arguments: [id]) ?? -1
  }

  /// With the session-HLC minter supplied, the drain's replay of the parked
  /// list-delete re-homes T to inbox AND re-enqueues it as a fresh task upsert so
  /// the move propagates to peers.
  func testPostLocalWriteDrainReemitsListDeleteRehome() throws {
    let store = try SyncTestSupport.freshStore()
    let hlc = try HlcState(deviceSuffix: "aaaaaaaaaaaaaaaa")
    try store.writer.write { db in
      try seed(db)
      try parkListDelete(db)
      try localUpsertP(db, hlc: hlc, reconcilePending: true)

      // The drain replayed the list-delete: L is gone and T re-homed to inbox.
      XCTAssertEqual(
        try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM lists WHERE id = ?", arguments: [listL]),
        0, "the replayed list-delete removed L")
      XCTAssertEqual(try taskListId(db, taskT), "inbox", "T re-homed to inbox")

      // The re-home was propagated: exactly one fresh task upsert for T carrying
      // list_id=inbox.
      XCTAssertEqual(
        try taskUpsertOutboxCount(db, taskT), 1,
        "the post-local-write drain must re-emit the re-homed task upsert")
      let row = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT payload FROM sync_outbox
            WHERE entity_type = 'task' AND entity_id = ? AND operation = 'upsert'
            """,
          arguments: [taskT]))
      let payload: String = row["payload"]
      XCTAssertTrue(
        payload.contains("\"list_id\":\"inbox\""),
        "the re-home upsert carries list_id=inbox; got \(payload)")
    }
  }

  /// Low-level enqueue never consumes pending work without a host-level owner.
  func testLowLevelEnqueueLeavesPendingAndCanonicalStateUntouched() throws {
    let store = try SyncTestSupport.freshStore()
    let hlc = try HlcState(deviceSuffix: "aaaaaaaaaaaaaaaa")
    try store.writer.write { db in
      try seed(db)
      try parkListDelete(db)
      try localUpsertP(db, hlc: hlc, reconcilePending: false)

      XCTAssertEqual(try taskListId(db, taskT), listL)
      XCTAssertEqual(try PendingInbox.countPending(db), 1)
      XCTAssertEqual(
        try taskUpsertOutboxCount(db, taskT), 0,
        "enqueue alone must not consume or partially fulfill pending convergence")
    }
  }
}
