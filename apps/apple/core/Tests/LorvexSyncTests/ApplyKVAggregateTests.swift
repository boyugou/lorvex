import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Coverage for the KV-shaped aggregate appliers (memory / preference). These
/// pin the contract-critical behaviors named in the handler docs: memory content
/// byte-clamp + truncation conflict-log, and preference local-only filtering on
/// both paths.
final class ApplyKVAggregateTests: XCTestCase {

  private let vMid = "1711234568000_0000_dec0000100000001"
  private let vNew = "1711234569000_0000_dec0000100000001"

  private func withDB(_ body: (Database) throws -> Void) throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in try body(db) }
  }

  // MARK: - memory

  func testMemoryUpsertStoresScrubbedContent() throws {
    try withDB { db in
      let payload = try SyncCanonicalize.canonicalizeJSON(
        .object([
          "key": .string("fav-color"), "content": .string("hello world"),
          "updated_at": .string("2026-04-01T00:00:00Z"),
        ]))
      try ApplyKVAggregate.applyMemoryUpsert(
        db, entityId: "mem-1", payload: payload, version: self.vMid, tieBreak: .rejectEqual,
        loserDeviceId: "dev", applyTs: "2026-04-01T00:00:00Z")
      // The row is addressed by the opaque envelope id; the human key comes from
      // the payload and remains the lookup handle.
      let row = try XCTUnwrap(
        try Row.fetchOne(
          db, sql: "SELECT id, content FROM memories WHERE key = ?", arguments: ["fav-color"]))
      XCTAssertEqual(row["id"] as String, "mem-1")
      XCTAssertEqual(row["content"] as String, "hello world")
    }
  }

  func testMemoryUpsertClampsOversizeContentAndLogsTruncation() throws {
    try withDB { db in
      let big = String(repeating: "x", count: Memory.maxMemoryContentLength + 100)
      let payload = try SyncCanonicalize.canonicalizeJSON(
        .object([
          "key": .string("k"), "content": .string(big),
          "updated_at": .string("2026-04-01T00:00:00Z"),
        ]))
      try ApplyKVAggregate.applyMemoryUpsert(
        db, entityId: "mem-1", payload: payload, version: self.vMid, tieBreak: .rejectEqual,
        loserDeviceId: "dev", applyTs: "2026-04-01T00:00:00Z")
      let stored = try XCTUnwrap(
        try String.fetchOne(db, sql: "SELECT content FROM memories WHERE key = ?", arguments: ["k"])
      )
      XCTAssertLessThanOrEqual(Array(stored.utf8).count, Memory.maxMemoryContentLength)
      XCTAssertTrue(stored.hasSuffix(Memory.memoryTruncationSentinel))
      // The conflict row is attributed to the opaque routing id, not the key.
      XCTAssertEqual(
        try Int64.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM sync_conflict_log
             WHERE entity_type = 'memory' AND entity_id = 'mem-1' AND resolution_type = 'content_truncated'
            """), 1)
    }
  }

  func testMemoryDeleteRemovesRow() throws {
    try withDB { db in
      let payload = try SyncCanonicalize.canonicalizeJSON(
        .object([
          "key": .string("k"), "content": .string("v"),
          "updated_at": .string("2026-04-01T00:00:00Z"),
        ]))
      try ApplyKVAggregate.applyMemoryUpsert(
        db, entityId: "mem-1", payload: payload, version: self.vMid, tieBreak: .rejectEqual,
        loserDeviceId: "dev", applyTs: "2026-04-01T00:00:00Z")
      try ApplyKVAggregate.applyMemoryDelete(db, entityId: "mem-1", version: self.vNew)
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM memories WHERE key = ?", arguments: ["k"]), 0)
    }
  }

  // MARK: - preference

  func testPreferenceUpsertStoresSyncedKey() throws {
    try withDB { db in
      let payload = try SyncCanonicalize.canonicalizeJSON(
        .object([
          "value": .string("America/New_York"), "updated_at": .string("2026-04-01T00:00:00Z"),
        ]))
      try ApplyKVAggregate.applyPreferenceUpsert(
        db, entityId: "timezone", payload: payload, version: self.vMid, tieBreak: .rejectEqual)
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT value FROM preferences WHERE key = ?", arguments: ["timezone"]),
        "\"America/New_York\"")
    }
  }

  func testPreferenceUpsertIgnoresLocalOnlyKey() throws {
    try withDB { db in
      let payload = try SyncCanonicalize.canonicalizeJSON(
        .object(["value": .bool(true), "updated_at": .string("2026-04-01T00:00:00Z")]))
      try ApplyKVAggregate.applyPreferenceUpsert(
        db, entityId: "theme", payload: payload, version: self.vMid, tieBreak: .rejectEqual)
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM preferences WHERE key = ?", arguments: ["theme"]), 0)
    }
  }

  func testPreferenceDeleteIgnoresLocalOnlyKey() throws {
    try withDB { db in
      try db.execute(
        sql:
          "INSERT INTO preferences (key, value, updated_at, version) VALUES ('theme', 'true', '', ?)",
        arguments: [self.vMid])
      let outcome = try ApplyKVAggregate.applyPreferenceDelete(
        db, entityId: "theme", version: self.vNew)
      // Local-only delete is a no-op that returns the typed skip (not `.applied`),
      // so the dispatcher/finalizer mints no tombstone; the row survives.
      XCTAssertEqual(outcome, .deleteSkippedLocalOnly)
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM preferences WHERE key = ?", arguments: ["theme"]), 1)
    }
  }

  func testControlPlanePreferenceEnvelopeFailsClosedWithoutEntitySideEffects() throws {
    let registry = EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
    try withDB { db in
      let key = PreferenceKeys.prefAiChangelogRetentionPolicy
      let payload = try SyncCanonicalize.canonicalizeJSON(.object([
        "key": .string(key),
        "value": .string("off"),
        "updated_at": .string("2026-04-01T00:00:00.000Z"),
        "version": .string(self.vNew),
      ]))
      let envelope = SyncEnvelope(
        entityType: .preference, entityId: key, operation: .upsert,
        version: try Hlc.parse(self.vNew),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: payload, deviceId: "remote-device")

      XCTAssertThrowsError(try Apply.applyEnvelope(db, registry: registry, envelope: envelope)) {
        guard case ApplyError.invalidPayload(let message) = $0 else {
          return XCTFail("expected invalidPayload, got \($0)")
        }
        XCTAssertTrue(message.contains("outside enum"))
      }
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM preferences WHERE key = ?", arguments: [key]),
        0)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM sync_payload_shadow WHERE entity_type = ? AND entity_id = ?",
          arguments: [EntityName.preference, key]),
        0)
      XCTAssertFalse(
        try Tombstone.isTombstoned(db, entityType: EntityName.preference, entityId: key))
      XCTAssertEqual(ChangelogRetentionPolicy.read(db), .maximum)
    }
  }

  /// A DELETE for a local-only preference key whose version DOMINATES the
  /// surviving local row must NOT mint a tombstone. Local-only keys never
  /// round-trip through sync, so a tombstone here would break the
  /// "tombstone ⇒ row dead" invariant diagnostics/GC assume — the row is still
  /// alive. Because the version out-ranks the live row, the dispatcher's
  /// post-handler LWW re-check cannot catch it; the delete arm must itself return
  /// a typed skip so `finalizeEntityOutcome` takes the skip path and mints no
  /// tombstone.
  ///
  /// Driven at the dispatcher + finalize seam because the `apply_envelope`
  /// entry-point's entity-id validator rejects a local-only key before dispatch
  /// (the "filtered both directions" defense); this arm is the defense-in-depth
  /// net for a direct dispatch or a future filter-set drift.
  func testLocalOnlyPreferenceDeleteDoesNotMintTombstoneOverLiveRow() throws {
    let registry = EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
    try withDB { db in
      try db.execute(
        sql:
          "INSERT INTO preferences (key, value, updated_at, version) VALUES ('theme', 'true', '', ?)",
        arguments: [self.vMid])

      let envelope = SyncEnvelope(
        entityType: .preference, entityId: "theme", operation: .delete,
        version: try Hlc.parse(self.vNew), payloadSchemaVersion: 1,
        payload: #"{"key":"theme","value":true,"updated_at":"2026-04-01T00:00:00Z"}"#,
        deviceId: "device-remote")

      let outcome = try ApplyDispatch.dispatch(
        db, registry: registry, envelope: envelope, tieBreak: .rejectEqual,
        applyTs: "2026-04-01T00:00:00Z")
      let result = try ApplyDeleteFlow.finalizeEntityOutcome(
        db, envelope: envelope, outcome: outcome,
        applyTs: "2026-04-01T00:00:00Z")
      guard case .skipped = result else {
        return XCTFail("local-only preference delete must skip, got \(result)")
      }

      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM preferences WHERE key = ?", arguments: ["theme"]), 1,
        "the live local-only row must survive")
      XCTAssertFalse(
        try Tombstone.isTombstoned(db, entityType: EntityName.preference, entityId: "theme"),
        "no tombstone may be minted for a surviving local-only row")
    }
  }
}
