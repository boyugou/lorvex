import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Sync-wedge regression for the `memory` privacy fix: a memory row is routed by
/// its opaque `id`, and the human `key` is a plain secondary `UNIQUE` column.
/// Two devices that create the SAME key offline each mint a distinct `id`, so the
/// second memory trips `memories`' `UNIQUE(key)` on inbound sync. Without
/// convergence that constraint escapes ``ApplyKVAggregate`` as the batch-fatal
/// ``ApplyError/db`` and wedges the whole inbound page.
///
/// The fix mirrors ``ApplyTagMerge``: the collision CONVERGES.
/// `min(id)` wins, the loser is tombstoned with a redirect, its diverging content
/// is captured in the conflict log, and the constraint never surfaces as
/// ``ApplyError/db``.
final class ApplyMemoryMergeTests: XCTestCase {

  private let smallerId = "00000000-0000-7000-8000-000000000001"
  private let largerId = "ffffffff-ffff-7fff-8fff-ffffffffffff"
  private let key = "alex_context"
  private let vEarlier = "1711234567000_0000_dec0000100000001"
  private let vLater = "1711234568000_0000_dec0000200000002"
  private let ts = "2026-04-01T00:00:00.000Z"

  private func withDB(_ body: (Database) throws -> Void) throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in try body(db) }
  }

  private func memPayload(key: String, content: String) throws -> String {
    try SyncCanonicalize.canonicalizeJSON(
      .object([
        "key": .string(key), "content": .string(content),
        "updated_at": .string(ts),
      ]))
  }

  private func applyMem(
    _ db: Database, id: String, version: String, key: String? = nil, content: String
  ) throws {
    try ApplyKVAggregate.applyMemoryUpsert(
      db, entityId: id, payload: try memPayload(key: key ?? self.key, content: content),
      version: version, tieBreak: .rejectEqual, loserDeviceId: "dev", applyTs: ts)
  }

  private func memExists(_ db: Database, _ id: String) throws -> Bool {
    (try Int64.fetchOne(
      db, sql: "SELECT COUNT(*) FROM memories WHERE id = ?", arguments: [id]) ?? 0) > 0
  }

  private func contentOf(_ db: Database, _ id: String) throws -> String? {
    try String.fetchOne(db, sql: "SELECT content FROM memories WHERE id = ?", arguments: [id])
  }

  private func keyOf(_ db: Database, _ id: String) throws -> String? {
    try String.fetchOne(db, sql: "SELECT key FROM memories WHERE id = ?", arguments: [id])
  }

  private func tombstone(_ db: Database, _ id: String) throws -> Tombstone.Record? {
    try Tombstone.getTombstone(db, entityType: EntityName.memory, entityId: id)
  }

  private func redirect(_ db: Database, _ id: String) throws -> EntityRedirect.Record? {
    try EntityRedirect.get(db, sourceType: EntityName.memory, sourceId: id)
  }

  /// The incoming memory owns the SMALLER id, so it wins and keeps its real key.
  func testIncomingSmallerIdWinsAndExistingIsTombstonedWithRedirect() throws {
    try withDB { db in
      try self.applyMem(db, id: self.largerId, version: self.vEarlier, content: "content-A")
      do {
        try self.applyMem(db, id: self.smallerId, version: self.vLater, content: "content-B")
      } catch {
        return XCTFail(
          "colliding memory must converge, not throw (got \(error)); the pre-fix bug "
            + "surfaced ApplyError.db and wedged the inbound batch")
      }

      XCTAssertTrue(try self.memExists(db, self.smallerId))
      XCTAssertFalse(try self.memExists(db, self.largerId), "larger-id memory merged away")
      XCTAssertEqual(try self.keyOf(db, self.smallerId), self.key, "winner keeps the real key")
      XCTAssertEqual(try self.contentOf(db, self.smallerId), "content-B", "winner keeps its content")

      XCTAssertNotNil(try self.tombstone(db, self.largerId))
      XCTAssertEqual(try self.redirect(db, self.largerId)?.targetId, self.smallerId)
      XCTAssertNil(try self.redirect(db, self.smallerId))
    }
  }

  /// The incoming memory owns the LARGER id but the LATER HLC, so it loses
  /// IDENTITY (min id wins) yet wins CONTENT (carried onto the min-id winner). The
  /// surviving min-id row therefore becomes the content-loser, and ITS discarded
  /// content is recorded in the conflict log at ITS own version — PII-redacted, so
  /// a divergent memory can never leak its text into the audit trail.
  func testIncomingLargerIdLosesIdentityButWinsContentAndMinIdDropIsRedacted() throws {
    try withDB { db in
      try self.applyMem(db, id: self.smallerId, version: self.vEarlier, content: "content-A")
      do {
        try self.applyMem(db, id: self.largerId, version: self.vLater, content: "content-B")
      } catch {
        return XCTFail("colliding memory must converge, not throw (got \(error))")
      }

      XCTAssertTrue(try self.memExists(db, self.smallerId))
      XCTAssertFalse(try self.memExists(db, self.largerId))
      XCTAssertEqual(
        try self.contentOf(db, self.smallerId), "content-B",
        "the max-HLC content is carried onto the min-id winner")

      XCTAssertNotNil(try self.tombstone(db, self.largerId))
      XCTAssertEqual(try self.redirect(db, self.largerId)?.targetId, self.smallerId)

      let row = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT loser_version, loser_payload FROM sync_conflict_log
             WHERE entity_type = ? AND entity_id = ? AND resolution_type = ?
            """,
          arguments: [EntityName.memory, self.smallerId, ResolutionName.tagMerge]),
        "the discarded min-id content must be recorded in the conflict log")
      XCTAssertEqual(
        row["loser_version"] as String?, self.vEarlier,
        "the content-loser is the min-id row, so its OWN version is recorded")
      let loserPayload = try XCTUnwrap(row["loser_payload"] as String?)
      XCTAssertFalse(loserPayload.isEmpty)
      XCTAssertFalse(
        loserPayload.contains("content-B"),
        "the surviving content must not land in the conflict log")
      XCTAssertTrue(
        loserPayload.contains("[REDACTED_PII]"),
        "the discarded content is captured but PII-redacted")
    }
  }

  /// Both convergence orders settle on the identical surviving memory id.
  func testBothArrivalOrdersConvergeToSameWinner() throws {
    var orderA = false
    var orderB = false
    try withDB { db in
      try self.applyMem(db, id: self.largerId, version: self.vEarlier, content: "A")
      try self.applyMem(db, id: self.smallerId, version: self.vLater, content: "B")
      orderA = try self.memExists(db, self.smallerId) && !(try self.memExists(db, self.largerId))
    }
    try withDB { db in
      try self.applyMem(db, id: self.smallerId, version: self.vEarlier, content: "A")
      try self.applyMem(db, id: self.largerId, version: self.vLater, content: "B")
      orderB = try self.memExists(db, self.smallerId) && !(try self.memExists(db, self.largerId))
    }
    XCTAssertTrue(orderA, "order A converges to the min-id winner")
    XCTAssertTrue(orderB, "order B converges to the same min-id winner")
  }

  // MARK: - Full inbound batch (no wedge) + replay idempotency

  private func memEnvelope(id: String, version: String, content: String) throws -> SyncEnvelope {
    try SyncTestSupport.completeEnvelope(
      entityType: .memory, entityId: id, operation: .upsert, version: try Hlc.parse(version),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: try self.memPayload(key: self.key, content: content), deviceId: "device-remote")
  }

  private func conflictCount(_ db: Database) throws -> Int64 {
    try Int64.fetchOne(
      db,
      sql: """
        SELECT COUNT(*) FROM sync_conflict_log
         WHERE entity_type = ? AND resolution_type = ?
        """,
      arguments: [EntityName.memory, ResolutionName.tagMerge]) ?? -1
  }

  /// A full inbound page carrying the colliding memory alongside an unrelated
  /// memory must NOT abort — and a REPLAY of the merged-away loser envelope is a
  /// no-op (the permanent alias remaps it to the winner; no second merge, no
  /// duplicate conflict row).
  func testCollidingMemoryDoesNotWedgeBatchAndReplayIsIdempotent() throws {
    let unrelatedId = "dddddddd-dddd-7ddd-8ddd-dddddddddddd"
    let registry = EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
    try withDB { db in
      let r1 = try Apply.applyEnvelope(
        db, registry: registry,
        envelope: try self.memEnvelope(id: self.smallerId, version: self.vEarlier, content: "A"))
      XCTAssertEqual(r1, .applied)

      do {
        _ = try Apply.applyEnvelope(
          db, registry: registry,
          envelope: try self.memEnvelope(id: self.largerId, version: self.vLater, content: "B"))
      } catch let error as ApplyError {
        if case .db = error {
          return XCTFail("collision still surfaced batch-fatal ApplyError.db — sync would wedge")
        }
        return XCTFail("collision threw an unexpected ApplyError: \(error)")
      }

      // Unrelated memory (different key) still applies in the same page.
      let r3 = try Apply.applyEnvelope(
        db, registry: registry,
        envelope: try SyncTestSupport.completeEnvelope(
          entityType: .memory, entityId: unrelatedId, operation: .upsert,
          version: try Hlc.parse(self.vLater),
          payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
          payload: try self.memPayload(key: "other_key", content: "C"), deviceId: "device-remote"))
      XCTAssertEqual(r3, .applied)
      XCTAssertTrue(try self.memExists(db, unrelatedId))

      XCTAssertTrue(try self.memExists(db, self.smallerId))
      XCTAssertFalse(try self.memExists(db, self.largerId))
      XCTAssertEqual(try self.conflictCount(db), 1)

      // Replay the loser envelope: the permanent alias must remap it to the
      // winner, not re-merge or re-log.
      _ = try Apply.applyEnvelope(
        db, registry: registry,
        envelope: try self.memEnvelope(id: self.largerId, version: self.vLater, content: "B"))
      XCTAssertFalse(try self.memExists(db, self.largerId), "replayed loser must not resurrect")
      XCTAssertEqual(
        try self.conflictCount(db), 1, "replay must not add a duplicate merge conflict row")
      XCTAssertNotNil(try self.tombstone(db, self.largerId))
      XCTAssertEqual(try self.redirect(db, self.largerId)?.targetId, self.smallerId)
    }
  }

  // MARK: - max-HLC content convergence

  /// Both apply orders converge on the SAME surviving content — the max-HLC
  /// participant's, carried onto the min-id winner regardless of arrival order.
  func testBothOrdersConvergeOnMaxHlcContent() throws {
    var contentA: String?
    try withDB { db in
      try self.applyMem(db, id: self.smallerId, version: self.vEarlier, content: "A")
      try self.applyMem(db, id: self.largerId, version: self.vLater, content: "B")
      contentA = try self.contentOf(db, self.smallerId)
    }
    var contentB: String?
    try withDB { db in
      try self.applyMem(db, id: self.largerId, version: self.vLater, content: "B")
      try self.applyMem(db, id: self.smallerId, version: self.vEarlier, content: "A")
      contentB = try self.contentOf(db, self.smallerId)
    }
    XCTAssertEqual(contentA, "B", "surviving content is the max-HLC participant's")
    XCTAssertEqual(contentA, contentB, "content converges regardless of apply order")
  }

  /// Equal HLCs keep the min-id row's content (the tiebreak keeps the lower id).
  func testEqualHlcTiebreakKeepsMinIdContent() throws {
    try withDB { db in
      try self.applyMem(db, id: self.smallerId, version: self.vEarlier, content: "A")
      try self.applyMem(db, id: self.largerId, version: self.vEarlier, content: "B")
      XCTAssertEqual(
        try self.contentOf(db, self.smallerId), "A",
        "on an equal-HLC tie the min-id content survives")
    }
  }

  /// An edit targeting the tombstoned loser id after the merge redirects onto the
  /// winner and, at a higher HLC, overwrites the carried content via LWW.
  func testPostMergeEditToTombstonedLoserRedirectsAndWinsViaLww() throws {
    let registry = EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
    try withDB { db in
      _ = try Apply.applyEnvelope(
        db, registry: registry,
        envelope: try self.memEnvelope(id: self.smallerId, version: self.vEarlier, content: "A"))
      _ = try Apply.applyEnvelope(
        db, registry: registry,
        envelope: try self.memEnvelope(id: self.largerId, version: self.vLater, content: "B"))
      XCTAssertEqual(try self.contentOf(db, self.smallerId), "B")

      let vNewest = "1711234569000_0000_dec0000300000003"
      _ = try Apply.applyEnvelope(
        db, registry: registry,
        envelope: try self.memEnvelope(id: self.largerId, version: vNewest, content: "C"))
      XCTAssertEqual(
        try self.contentOf(db, self.smallerId), "C",
        "an edit to the tombstoned loser id redirects onto the winner and wins LWW")
      XCTAssertFalse(try self.memExists(db, self.largerId))
    }
  }

  // MARK: - Bug 2: deterministic merge-stamp suffix (cross-peer version convergence)

  /// A 3-participant slot collision (`V_a=(t,0,sa)`, `V_b=(t,0,sb)` with `sb>sa`,
  /// `V_c=(t,1,sc)` dominating) mints a winner version `(t, 2, sc)` whose suffix is
  /// the dominating participant's own suffix, not the local device's, so two peers
  /// with DIFFERENT device ids converge on a byte-identical winner version and
  /// content regardless of fold order.
  func testThreeWaySlotCollisionConvergesWinnerVersionAcrossPeers() throws {
    let idA = "00000000-0000-7000-8000-00000000000a"
    let idB = "00000000-0000-7000-8000-00000000000b"
    let idC = "00000000-0000-7000-8000-00000000000c"
    let vA = "1711234567000_0000_aaaa000000000001"
    let vB = "1711234567000_0000_bbbb000000000002"
    let vC = "1711234567000_0001_cccc000000000003"
    let expectedVersion = "1711234567000_0002_cccc000000000003"

    func run(deviceId: String, rowOrder: [(String, String)]) throws -> (String?, String?) {
      let store = try SyncTestSupport.freshStore()
      return try store.writer.write { db in
        try SyncCheckpoints.set(db, key: SyncCheckpoints.keyDeviceId, value: deviceId)
        try self.applyMem(db, id: idA, version: vA, key: "key-a", content: "mem-a")
        try self.applyMem(db, id: idB, version: vB, key: "key-b", content: "mem-b")
        try self.applyMem(db, id: idC, version: vC, key: "key-c", content: "mem-c")
        _ = try ApplyMemoryMerge.merger.mergeKnownDuplicate(
          db, rows: rowOrder, triggeringVersion: vC, applyTs: self.ts)
        let version = try String.fetchOne(
          db, sql: "SELECT version FROM memories WHERE id = ?", arguments: [idA])
        return (try self.contentOf(db, idA), version)
      }
    }

    let peerOne = try run(deviceId: "device-one-1111", rowOrder: [(idA, vA), (idB, vB), (idC, vC)])
    let peerTwo = try run(deviceId: "device-two-2222", rowOrder: [(idC, vC), (idB, vB), (idA, vA)])

    XCTAssertEqual(peerOne.0, "mem-c", "content = the dominating participant (V_c), carried onto min id")
    XCTAssertEqual(peerOne.1, expectedVersion, "winner version = (maxHlc.phys, counter+1, maxHlc.suffix)")
    XCTAssertEqual(peerOne.0, peerTwo.0, "content byte-identical across peers with different device ids")
    XCTAssertEqual(
      peerOne.1, peerTwo.1, "winner version byte-identical across peers (deterministic suffix)")
  }
}
