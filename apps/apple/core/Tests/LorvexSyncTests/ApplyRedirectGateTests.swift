import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Regression coverage for the redirect-flow safety gates in
/// ``ApplyRedirectFlow/applyRedirectedTombstone(_:registry:envelope:ts:acceptance:applyTs:)``.
///
/// A permanent alias X→Y means the entity once addressed as X was merged into
/// the surviving winner Y. Two stale envelopes that arrive against X must NOT be
/// blindly remapped onto Y:
///
/// 1. A redirected DELETE for X would destroy the surviving winner Y. The
///    delete-drop gate skips it (recording a `redirected_delete_dropped`
///    conflict) instead of applying.
/// 2. A redirected UPSERT for X must respect a REAL delete tombstone on the
///    target Y: a stale upsert at/below the tombstone version must not resurrect
///    the deleted row.
final class ApplyRedirectGateTests: XCTestCase {

  private let suffix = "a1b2c3d4a1b2c3d4"
  private func v(_ ms: UInt64, _ ctr: UInt32 = 0) -> String {
    "\(String(format: "%013d", ms))_\(String(format: "%04d", ctr))_\(suffix)"
  }

  /// Winner Y (survives the merge) and loser X (redirected into Y). Both are
  /// canonical UUIDs so the apply entry-point's entity_id validation admits them.
  private let winnerY = "aaaaaaaa-aaaa-7aaa-8aaa-aaaaaaaaaaaa"
  private let loserX = "ffffffff-ffff-7fff-8fff-ffffffffffff"

  private func withDB(_ body: (Database) throws -> Void) throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in try body(db) }
  }

  private func tagPayload(_ displayName: String) -> String {
    """
    {"display_name":"\(displayName)","lookup_key":"\(displayName.lowercased())","color":null,"created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z"}
    """
  }

  private func upsertTag(_ db: Database, _ id: String, _ display: String, _ version: String) throws {
    try ApplyTagMerge.applyTagUpsert(
      db, entityId: id, payload: self.tagPayload(display), version: version, tieBreak: .rejectEqual,
      applyTs: "seed")
  }

  private func tagExists(_ db: Database, _ id: String) throws -> Bool {
    try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM tags WHERE id = ?", arguments: [id]) ?? 0 > 0
  }

  private func envelope(
    _ id: String, _ op: SyncOperation, _ version: String, _ display: String = "Stale"
  ) throws -> SyncEnvelope {
    try SyncTestSupport.completeEnvelope(
      entityType: .tag, entityId: id, operation: op, version: try Hlc.parse(version),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion, payload: self.tagPayload(display),
      deviceId: "device-remote")
  }

  // MARK: - Gate 1: redirected DELETE is dropped

  /// A permanent alias redirects X→Y; a peer that never saw the merge replays a
  /// DELETE for X at a LATER HLC. The delete-drop gate must skip it (not remap),
  /// leave the winner Y intact, and record a `redirected_delete_dropped`
  /// conflict-log row.
  func testRedirectedDeleteIsDroppedAndWinnerSurvives() throws {
    try withDB { db in
      // Winner Y survives the merge.
      try self.upsertTag(db, self.winnerY, "Winner", self.v(100))
      try SyncTestSupport.seedEntityRedirect(
        db, sourceType: .tag, sourceId: self.loserX, targetId: self.winnerY,
        version: self.v(200))

      // Peer replays a stale DELETE for X at a LATER HLC than the merge version.
      let env = try self.envelope(self.loserX, .delete, self.v(300))
      let result = try Apply.applyEnvelope(
        db, registry: EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers()),
        envelope: env)

      // Skipped (NOT remapped): the delete must not propagate to the winner.
      guard case let .skipped(reason, winnerVersion) = result else {
        return XCTFail("expected .skipped, got \(result)")
      }
      XCTAssertTrue(reason.contains("dropped"), "unexpected skip reason: \(reason)")
      XCTAssertEqual(winnerVersion, try Hlc.parse(self.v(200)))

      // Winner Y is untouched.
      XCTAssertTrue(try self.tagExists(db, self.winnerY), "merge winner must survive a redirected delete")

      // Conflict-log row records the drop, attributed to the original loser id.
      let row = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT entity_id, winner_version, loser_version, resolution_type
            FROM sync_conflict_log WHERE resolution_type = ?
            """,
          arguments: [ResolutionName.redirectedDeleteDropped]))
      XCTAssertEqual(row["entity_id"] as String?, self.loserX)
      XCTAssertEqual(row["winner_version"] as String?, self.v(200))
      XCTAssertEqual(row["loser_version"] as String?, self.v(300))
    }
  }

  // MARK: - Gate 2: redirected UPSERT blocked by target's real tombstone

  /// A merge redirects X→Y, and Y is subsequently DELETED for real. A late
  /// pre-merge UPSERT addressed at X (redirecting to Y) with version <= the
  /// delete tombstone must be skipped — never resurrecting the deleted target.
  func testRedirectedUpsertBlockedByTargetRealTombstone() throws {
    try withDB { db in
      try SyncTestSupport.seedEntityRedirect(
        db, sourceType: .tag, sourceId: self.loserX, targetId: self.winnerY,
        version: self.v(200))
      // Target Y carries a REAL delete tombstone at a high version.
      try Tombstone.createTombstone(
        db, entityType: EntityName.tag, entityId: self.winnerY, version: self.v(500), deletedAt: "del-ts")

      // Stale pre-merge UPSERT for X at version <= the target's delete tombstone.
      let env = try self.envelope(self.loserX, .upsert, self.v(400), "Resurrected")
      let result = try Apply.applyEnvelope(
        db, registry: EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers()),
        envelope: env)

      guard case let .skipped(reason, winnerVersion) = result else {
        return XCTFail("expected .skipped, got \(result)")
      }
      XCTAssertTrue(reason.contains("tombstoned"), "unexpected skip reason: \(reason)")
      XCTAssertEqual(winnerVersion, try Hlc.parse(self.v(500)))

      // Target Y must NOT be resurrected.
      XCTAssertFalse(
        try self.tagExists(db, self.winnerY), "stale redirected upsert must not resurrect a real tombstone")

      // The skip is surfaced as a tombstone_wins conflict against the target id.
      let row = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT entity_id, winner_version, resolution_type
            FROM sync_conflict_log WHERE resolution_type = ?
            """,
          arguments: [ResolutionName.tombstoneWins]))
      XCTAssertEqual(row["entity_id"] as String?, self.winnerY)
      XCTAssertEqual(row["winner_version"] as String?, self.v(500))
    }
  }
}
