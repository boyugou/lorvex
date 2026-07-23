import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// D2 convergence coverage: composite-edge operations addressed at a MERGED
/// parent (loser) must remap through the parent's permanent alias before the
/// tombstone/LWW gate, for BOTH upsert and delete.
///
/// Scenario (tags). Device B (offline) creates tag `work` = `tagB`, upserts edge
/// `T:tagB`, then deletes edge `T:tagB` (both pushed). Device A already has tag
/// `work` = `tagA` (min id). On A the tag merge collapses `tagB` into `tagA`
/// (`tagB` → permanent alias). The edge upsert and delete both name the
/// merged loser `tagB`; each must operate on the surviving `T:tagA` edge so the
/// device converges with B (task UNTAGGED) — in EITHER edge arrival order.
///
/// Before the fix a delete `T:tagB` finds no `T:tagB` edge (the upsert was
/// remapped to `T:tagA`), no-ops, and tombstones the wrong id — leaving the
/// remapped `T:tagA` edge to survive and resurrect the deleted relationship.
final class ApplyCompositeEdgeRedirectTests: XCTestCase {

  private let taskT = "01966a3f-7c8b-7d4e-8f3a-000000000001"
  // tagA < tagB lexicographically, so the min-id merge keeps tagA.
  private let tagA = "01966a3f-7c8b-7d4e-8f3a-0000000000aa"
  private let tagB = "01966a3f-7c8b-7d4e-8f3a-0000000000bb"

  private let vTagA = "1711234560000_0000_a1b2c3d4a1b2c3d4"
  private let vTagB = "1711234561000_0000_a1b2c3d4a1b2c3d4"
  private let edgeV1 = "1711234562000_0000_dead00000000beef"  // upsert (device B)
  private let edgeV2 = "1711234563000_0000_dead00000000beef"  // delete (device B, later)
  private let zeroVersion = "0000000000000_0000_0000000000000000"

  private var registry: EntityApplierRegistry {
    EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
  }

  private func tagPayload(_ display: String) -> String {
    """
    {"display_name":"\(display)","lookup_key":"\(display)","color":null,"created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z"}
    """
  }

  private func tagEnvelope(_ id: String, _ version: String) throws -> SyncEnvelope {
    try SyncTestSupport.completeEnvelope(
      entityType: .tag, entityId: id, operation: .upsert, version: try Hlc.parse(version),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion, payload: tagPayload("work"),
      deviceId: "device-remote")
  }

  private func edgeEnvelope(
    _ tagId: String, _ op: SyncOperation, _ version: String
  ) throws -> SyncEnvelope {
    try SyncTestSupport.completeEnvelope(
      entityType: .taskTag, entityId: "\(taskT):\(tagId)", operation: op,
      version: try Hlc.parse(version), payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: "{\"task_id\":\"\(taskT)\",\"tag_id\":\"\(tagId)\",\"created_at\":\"2026-03-27T09:00:00Z\"}",
      deviceId: "device-remote")
  }

  private func taskTagCountForT(_ db: Database) throws -> Int64 {
    try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM task_tags WHERE task_id = ?", arguments: [taskT])
      ?? -1
  }

  private func tagExists(_ db: Database, _ id: String) throws -> Bool {
    (try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM tags WHERE id = ?", arguments: [id]) ?? 0) > 0
  }

  /// Drive Device A's apply stream for a given edge arrival order and return the
  /// number of `task_tags` rows left on task T (0 == converged / untagged).
  private func runDeviceA(edgeOrder: [(SyncOperation, String)]) throws -> Int64 {
    let store = try SyncTestSupport.freshStore()
    return try store.writer.write { db in
      // Task T exists locally.
      try db.execute(
        sql:
          "INSERT INTO tasks (id, title, status, version, created_at, updated_at) VALUES (?, 'T', 'open', ?, '', '')",
        arguments: [self.taskT, self.zeroVersion])

      // Device A already has tag `work` = tagA; then tagB arrives and merges in
      // (min-id tagA wins, tagB → permanent alias → tagA).
      _ = try Apply.applyEnvelope(db, registry: self.registry, envelope: try self.tagEnvelope(self.tagA, self.vTagA))
      _ = try Apply.applyEnvelope(db, registry: self.registry, envelope: try self.tagEnvelope(self.tagB, self.vTagB))

      // Sanity: the merge fired — tagA survives, tagB has a permanent alias.
      XCTAssertTrue(try self.tagExists(db, self.tagA), "winner tagA must survive the merge")
      XCTAssertFalse(try self.tagExists(db, self.tagB), "loser tagB must be merged away")
      let redirect = try EntityRedirect.get(
        db, sourceType: EntityName.tag, sourceId: self.tagB)?.targetId
      XCTAssertEqual(redirect, self.tagA, "tagB must carry a permanent alias to tagA")

      // Apply the two edge envelopes (authored against the loser tagB),
      // mirroring the ingest contract: a `.deferred` result is parked in the
      // pending inbox. Then drain so any FK-deferred upsert is remapped +
      // applied.
      for (op, version) in edgeOrder {
        let env = try self.edgeEnvelope(self.tagB, op, version)
        let result = try Apply.applyEnvelope(db, registry: self.registry, envelope: env)
        if case let .deferred(reason) = result {
          try PendingInboxDrain.enqueueDeferred(db, envelope: env, reason: reason)
        }
      }
      _ = try PendingInboxDrain.drainPendingInbox(db, registry: self.registry)

      return try self.taskTagCountForT(db)
    }
  }

  /// Upsert-before-delete: the edge is created on the loser, then deleted on the
  /// loser. After remap, both target `T:tagA`; the delete removes it.
  func testUpsertThenDeleteConvergesToUntagged() throws {
    let count = try runDeviceA(edgeOrder: [(.upsert, edgeV1), (.delete, edgeV2)])
    XCTAssertEqual(count, 0, "T must be UNTAGGED after upsert-then-delete of the merged-loser edge")
  }

  /// Delete-before-upsert: the delete lands first (tombstoning `T:tagA`), then
  /// the stale upsert must lose the tombstone gate rather than resurrect the edge.
  func testDeleteThenUpsertConvergesToUntagged() throws {
    let count = try runDeviceA(edgeOrder: [(.delete, edgeV2), (.upsert, edgeV1)])
    XCTAssertEqual(count, 0, "T must be UNTAGGED after delete-then-upsert of the merged-loser edge")
  }

  /// Commutativity: both arrival orders converge to the identical state.
  func testBothArrivalOrdersConverge() throws {
    let upsertFirst = try runDeviceA(edgeOrder: [(.upsert, edgeV1), (.delete, edgeV2)])
    let deleteFirst = try runDeviceA(edgeOrder: [(.delete, edgeV2), (.upsert, edgeV1)])
    XCTAssertEqual(upsertFirst, deleteFirst, "both edge arrival orders must converge identically")
    XCTAssertEqual(upsertFirst, 0)
  }

  /// Regression guard: a plain edge upsert + delete with NO parent merge still
  /// converges (edge deleted) through the full pipeline.
  func testNonMergedEdgeUpsertThenDeleteStillConverges() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try db.execute(
        sql:
          "INSERT INTO tasks (id, title, status, version, created_at, updated_at) VALUES (?, 'T', 'open', ?, '', '')",
        arguments: [self.taskT, self.zeroVersion])
      _ = try Apply.applyEnvelope(db, registry: self.registry, envelope: try self.tagEnvelope(self.tagA, self.vTagA))

      _ = try Apply.applyEnvelope(
        db, registry: self.registry, envelope: try self.edgeEnvelope(self.tagA, .upsert, self.edgeV1))
      XCTAssertEqual(try self.taskTagCountForT(db), 1, "edge must land when no merge is involved")

      _ = try Apply.applyEnvelope(
        db, registry: self.registry, envelope: try self.edgeEnvelope(self.tagA, .delete, self.edgeV2))
      XCTAssertEqual(try self.taskTagCountForT(db), 0, "non-merged edge delete must remove the edge")
    }
  }
}
