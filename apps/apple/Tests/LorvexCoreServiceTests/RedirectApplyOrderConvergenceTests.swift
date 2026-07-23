import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync
import XCTest

@testable import LorvexCore

/// Bug 3: within-batch redirect re-derivation via upsert-before-delete ordering.
///
/// A full-resync batch from a peer that already merged a duplicate carries the live
/// winner's `upsert` AND the merged-away loser's ordinary `delete` tombstone.
/// ``SwiftLorvexCoreService`` applies inbound envelopes in a stable
/// upsert-before-delete partition (``SwiftLorvexCoreService/orderedForApply(_:)``),
/// so the winner upsert's post-upsert dedup-merge tail sees the still-live loser
/// sharing the natural key, derives the `loser → winner` redirect locally, and the
/// loser's `delete` then observes the independently derived permanent alias.
/// This holds no matter which order the batch presents the two envelopes — the
/// regression pinned here is that a delete-first batch used to plain-tombstone the
/// loser before deriving the alias, so a later edge naming the loser could not remap
/// onto the winner.
///
/// `applyInbound` (not `Apply.applyEnvelope`) is the entry under test because the
/// upsert-before-delete sort lives only in that batch driver; direct
/// `applyEnvelope` unit tests pick their own order and are unaffected.
final class RedirectApplyOrderConvergenceTests: XCTestCase {

  private func makeService() throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    let store = try LorvexStore.openInMemory(schemaSQL: schemaSQL)
    return SwiftLorvexCoreService(store: store)
  }

  // Canonical UUIDs (the envelope path enforces id format). `winner` sorts before
  // `loser`, so `min(id)` keeps the winner as the surviving identity.
  private let winner = "00000000-0000-7000-8000-00000000000a"
  private let loser = "ffffffff-ffff-7fff-8fff-ffffffffffff"
  private let taskX = "00000000-0000-7000-8000-0000000000f1"
  private let vLoser = "1711234567000_0000_dec0000200000002"
  private let vWinner = "1711234568000_0000_dec0000100000001"
  private let vDelete = "1711234569000_0000_dec0000300000003"
  private let vEdge = "1711234570000_0000_dec0000400000004"

  private func tagUpsertEnv(_ id: String, _ version: String) throws -> SyncEnvelope {
    let payload =
      try SyncCanonicalize.canonicalizeJSON(
        .object([
          "display_name": .string("Shared"),
          "lookup_key": .string("shared"),
          "color": .null,
          "created_at": .string("2026-04-01T00:00:00.000Z"),
          "updated_at": .string("2026-04-01T00:00:00.000Z"),
        ]))
    return try CurrentSyncEnvelopeTestSupport.complete(
      SyncEnvelope(
        entityType: .tag, entityId: id, operation: .upsert, version: try Hlc.parse(version),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion, payload: payload,
        deviceId: "device-remote"))
  }

  private func tagDeleteEnv(_ id: String, _ version: String) -> SyncEnvelope {
    SyncEnvelope(
      entityType: .tag, entityId: id, operation: .delete, version: try! Hlc.parse(version),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: "{\"version\":\"\(version)\"}",
      deviceId: "device-remote")
  }

  private func entityRedirectEnv(
    sourceId: String, targetId: String, version: String
  ) throws -> SyncEnvelope {
    let payload = try SyncCanonicalize.canonicalizeJSON(
      .object([
        "source_id": .string(sourceId),
        "source_type": .string(EntityName.tag),
        "target_id": .string(targetId),
        "version": .string(version),
      ]))
    return try CurrentSyncEnvelopeTestSupport.complete(
      SyncEnvelope(
        entityType: .entityRedirect,
        entityId: EntityRedirect.wireEntityId(sourceType: .tag, sourceId: sourceId),
        operation: .upsert, version: try Hlc.parse(version),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion, payload: payload,
        deviceId: "device-remote"))
  }

  private func taskTagUpsertEnv(
    _ taskId: String, _ tagId: String, _ version: String
  ) throws -> SyncEnvelope {
    try CurrentSyncEnvelopeTestSupport.complete(
      SyncEnvelope(
        entityType: .taskTag, entityId: "\(taskId):\(tagId)", operation: .upsert,
        version: try Hlc.parse(version), payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: "{\"task_id\":\"\(taskId)\",\"tag_id\":\"\(tagId)\",\"created_at\":\"2026-04-01T00:00:00.000Z\"}",
        deviceId: "device-remote"))
  }

  func testBatchOrderingEstablishesOrdinaryTargetsAndDeathsBeforeExplicitAliases() throws {
    let targetUpsert = try tagUpsertEnv(winner, vWinner)
    let targetDelete = tagDeleteEnv(winner, vDelete)
    let alias = try entityRedirectEnv(
      sourceId: loser, targetId: winner, version: vDelete)

    let ordered = SwiftLorvexCoreService.orderedForApply(
      [alias, targetDelete, targetUpsert])

    XCTAssertEqual(ordered.map(\.entityType), [.tag, .tag, .entityRedirect])
    XCTAssertEqual(ordered.map(\.operation), [.upsert, .delete, .upsert])
  }

  private func run(deleteFirst: Bool) throws -> (redirect: String?, edgeTagId: String?) {
    let service = try makeService()
    // Local copies so the @Sendable write/read closures don't capture `self`.
    let (winner, loser, taskX) = (self.winner, self.loser, self.taskX)
    let (vLoser, vWinner, vDelete, vEdge) = (self.vLoser, self.vWinner, self.vDelete, self.vEdge)

    // Seed a task for the later edge FK, and the live loser tag.
    try service.write { db in
      try db.execute(
        sql: """
          INSERT INTO tasks (id, title, status, list_id, version, created_at, updated_at, defer_count)
          VALUES (?, 'X', 'open', 'inbox', ?, '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z', 0)
          """,
        arguments: [taskX, vLoser])
    }
    _ = try service.applyInbound([try tagUpsertEnv(loser, vLoser)], undecodable: 0)

    // The full-resync batch: the live winner's upsert + the loser's delete, in the
    // requested source order.
    let batch =
      deleteFirst
      ? [tagDeleteEnv(loser, vDelete), try tagUpsertEnv(winner, vWinner)]
      : [try tagUpsertEnv(winner, vWinner), tagDeleteEnv(loser, vDelete)]
    _ = try service.applyInbound(batch, undecodable: 0)

    // A later edge that names the loser must remap onto the winner.
    _ = try service.applyInbound([try taskTagUpsertEnv(taskX, loser, vEdge)], undecodable: 0)

    return try service.read { db in
      let redirect = try String.fetchOne(
        db,
        sql: "SELECT target_id FROM sync_entity_redirects WHERE source_type = ? AND source_id = ?",
        arguments: [EntityName.tag, loser])
      let edgeTagId = try String.fetchOne(
        db, sql: "SELECT tag_id FROM task_tags WHERE task_id = ?", arguments: [taskX])
      return (redirect, edgeTagId)
    }
  }

  func testWithinBatchRedirectReDerivesRegardlessOfSourceOrder() throws {
    let upsertFirst = try run(deleteFirst: false)
    let deleteFirst = try run(deleteFirst: true)

    XCTAssertEqual(
      upsertFirst.redirect, winner, "the loser must carry a permanent alias to the winner")
    XCTAssertEqual(
      upsertFirst.edgeTagId, winner, "a later edge naming the loser remaps onto the winner")

    XCTAssertEqual(
      deleteFirst.redirect, winner,
      "a delete-first source batch still yields the independent alias (Bug 3 fix)")
    XCTAssertEqual(
      deleteFirst.edgeTagId, winner, "the delete-first edge also remaps onto the winner")

    XCTAssertEqual(
      upsertFirst.redirect, deleteFirst.redirect, "both source orders converge on the redirect")
    XCTAssertEqual(upsertFirst.edgeTagId, deleteFirst.edgeTagId)
  }
}
