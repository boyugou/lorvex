import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Coverage for ``ApplyPromote/promotePayloadShadows(_:registry:)`` — the
/// forward-compat shadow replay that runs at startup once the local build
/// understands a previously-shadowed payload schema version.
final class ApplyPromoteTests: XCTestCase {

  private let taskId = "aaaaaaaa-aaaa-7aaa-8aaa-aaaaaaaaaaaa"

  private func withDB(_ body: (Database) throws -> Void) throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in try body(db) }
  }

  private func registry() -> EntityApplierRegistry {
    EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
  }

  /// Seed a live task row at `version` with a NULL body (the truncated state an
  /// older parser landed).
  private func seedTask(_ db: Database, version: String, title: String = "Shadow task") throws {
    try db.execute(
      sql: """
        INSERT INTO tasks (id, title, status, list_id, version, created_at, updated_at)
        VALUES (?, ?, 'open', 'inbox', ?, '2026-03-27T09:00:00Z', '2026-03-27T09:00:00Z')
        """,
      arguments: [taskId, title, version])
  }

  /// Insert a shadow row directly carrying an owned key (`body`) the live row
  /// left NULL. The real writer (`upsertShadow`) strips owned keys, so a stored
  /// shadow only ever holds keys that were forward-compat (not owned) when
  /// written; this fixture simulates such a key after a schema upgrade made it
  /// owned, to exercise promotion's authoritative reconstruction.
  private func insertShadow(
    _ db: Database, version: String, schemaVersion: Int = 1,
    body: String = "Recovered from shadow"
  ) throws {
    let payload = """
      {"id":"\(taskId)","title":"Shadow task","status":"open","list_id":"inbox",\
      "body":"\(body)","created_at":"2026-03-27T09:00:00Z",\
      "updated_at":"2026-03-27T09:00:00Z"}
      """
    try db.execute(
      sql: """
        INSERT INTO sync_payload_shadow
          (entity_type, entity_id, base_version, payload_schema_version,
           raw_payload_json, source_device_id, updated_at)
        VALUES ('task', ?, ?, ?, ?, 'device-remote', '2026-03-27T09:00:00Z')
        """,
      arguments: [taskId, version, schemaVersion, payload])
  }

  private func shadowCount(_ db: Database) throws -> Int {
    try Int.fetchOne(
      db, sql: "SELECT COUNT(*) FROM sync_payload_shadow WHERE entity_id = ?",
      arguments: [taskId]) ?? 0
  }

  private func object(_ raw: String) throws -> [String: JSONValue] {
    guard let parsed = JSONValue.parse(raw), case .object(let object) = parsed else {
      XCTFail("expected JSON object: \(raw)")
      return [:]
    }
    return object
  }

  private final class CapturingTaskApplier: EntityApplier, @unchecked Sendable {
    private(set) var payloads: [String] = []
    var handledEntityTypes: [String] { [EntityName.task] }

    func applyUpsert(
      _ db: Database, envelope: SyncEnvelope, tieBreak: LwwTieBreak, applyTs: String
    ) throws -> EntityApplyOutcome {
      payloads.append(envelope.payload)
      return .applied
    }

    func applyDelete(
      _ db: Database, envelope: SyncEnvelope, applyTs: String
    ) throws -> EntityApplyOutcome {
      return .applied
    }
  }

  /// A corrupt shadow base cannot prove that its future fields are obsolete.
  /// Promotion logs the blocked repair and retains the only preserved copy.
  func testPromotionRetainsCorruptBaseVersionWithoutDispatch() throws {
    try withDB { db in
      try SyncTestSupport.seedIgnoringCheckConstraints(db) {
        try self.insertShadow(db, version: "not-a-valid-hlc")
      }
      XCTAssertEqual(try self.shadowCount(db), 1)
      let applier = CapturingTaskApplier()

      let promoted = try ApplyPromote.promotePayloadShadows(
        db, registry: EntityApplierRegistry(appliers: [applier]))

      XCTAssertEqual(promoted, 0, "a corrupt-base shadow cannot promote")
      XCTAssertEqual(
        try self.shadowCount(db), 1, "the corrupt-base shadow is retained for repair")
      XCTAssertTrue(applier.payloads.isEmpty)
      let logged =
        try Int.fetchOne(
          db,
          sql:
            "SELECT COUNT(*) FROM error_logs WHERE source = 'sync.apply.promote_shadow_corrupt_base_version'"
        ) ?? 0
      XCTAssertEqual(logged, 1, "the blocked promotion must be logged for diagnosability")
    }
  }

  /// The equal-version case: promotion reconstructs from the live canonical row
  /// and overlays owned keys from the shadow's preserved forward-compat values.
  /// Here the live row was truncated to a NULL `body`
  /// while the shadow still carries the value, so promotion must repair `body` —
  /// not overwrite it with the live NULL and then reap the shadow (which would
  /// lose the value permanently).
  func testPromotionFillsTruncatedOwnedFieldFromShadow() throws {
    try withDB { db in
      let v = "1711234567890_0201_deadbeefdeadbeef"
      try seedTask(db, version: v)
      try insertShadow(db, version: v)

      XCTAssertEqual(try ApplyPromote.promotePayloadShadows(db, registry: registry()), 1)

      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT body FROM tasks WHERE id = ?", arguments: [taskId]),
        "Recovered from shadow")
      XCTAssertEqual(try shadowCount(db), 0)
    }
  }

  /// A migration may add a newly understood column with a non-NULL default.
  /// That placeholder was never authored by the peer and must not override the
  /// value preserved in an equal-version payload shadow.
  func testPromotionOverridesMigrationDefaultWithPreservedShadowValue() throws {
    try withDB { db in
      let v = "1711234567890_0201_deadbeefdeadbeef"
      try seedTask(db, version: v)
      try db.execute(
        sql: "UPDATE tasks SET body = 'migration-default' WHERE id = ?",
        arguments: [taskId])
      try insertShadow(db, version: v, body: "Remote authored value")

      XCTAssertEqual(try ApplyPromote.promotePayloadShadows(db, registry: registry()), 1)
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT body FROM tasks WHERE id = ?", arguments: [taskId]),
        "Remote authored value")
      XCTAssertEqual(try shadowCount(db), 0)
    }
  }

  func testPromotionReconstructsRealStrippedShadowBeforeDispatch() throws {
    try withDB { db in
      let v = "1711234567890_0201_deadbeefdeadbeef"
      try seedTask(db, version: v, title: "Known title")
      let remotePayload = """
        {"id":"\(taskId)","title":"Remote title","status":"open","list_id":"inbox",\
        "body":"Remote body","created_at":"2026-03-27T09:00:00Z",\
        "updated_at":"2026-03-27T09:00:00Z","future_payload_key":"preserved"}
        """
      try PayloadShadow.upsertShadow(
        db, entityType: EntityName.task, entityID: taskId, baseVersion: v,
        payloadSchemaVersion: 1, rawPayloadJSON: remotePayload, sourceDeviceID: "device-remote")
      let stored = try XCTUnwrap(
        PayloadShadow.getShadow(db, entityType: EntityName.task, entityID: taskId))
      let storedObject = try object(stored.rawPayloadJSON)
      XCTAssertNil(storedObject["title"])
      XCTAssertEqual(storedObject["future_payload_key"], .string("preserved"))

      let applier = CapturingTaskApplier()
      XCTAssertEqual(
        try ApplyPromote.promotePayloadShadows(
          db, registry: EntityApplierRegistry(appliers: [applier])),
        1)

      let payload = try XCTUnwrap(applier.payloads.first)
      let promoted = try object(payload)
      XCTAssertEqual(promoted["id"], .string(taskId))
      XCTAssertEqual(promoted["title"], .string("Known title"))
      XCTAssertEqual(promoted["status"], .string("open"))
      XCTAssertEqual(promoted["future_payload_key"], .string("preserved"))
      XCTAssertEqual(try shadowCount(db), 0)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM error_logs WHERE source = 'sync.apply.promote_shadow_failed'"),
        0)
    }
  }

  /// A shadow whose schema version is still ahead of this build is left
  /// untouched for a future upgrade.
  func testFutureSchemaVersionShadowIsLeftInPlace() throws {
    try withDB { db in
      let v = "1711234567890_0201_deadbeefdeadbeef"
      try seedTask(db, version: v)
      try insertShadow(db, version: v, schemaVersion: 99)

      XCTAssertEqual(try ApplyPromote.promotePayloadShadows(db, registry: registry()), 0)
      XCTAssertEqual(try shadowCount(db), 1)
    }
  }

  /// A live/shadow version mismatch is not proof that a legacy writer understood
  /// the future field. Retain and diagnose instead of authoritatively discarding.
  func testNewerLiveRowRetainsMismatchedShadowWithoutDispatch() throws {
    try withDB { db in
      try seedTask(db, version: "1711234567890_0300_deadbeefdeadbeef", title: "Newer local title")
      try insertShadow(db, version: "1711234567890_0200_deadbeefdeadbeef")
      let applier = CapturingTaskApplier()

      XCTAssertEqual(
        try ApplyPromote.promotePayloadShadows(
          db, registry: EntityApplierRegistry(appliers: [applier])), 0)

      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT title FROM tasks WHERE id = ?", arguments: [taskId]),
        "Newer local title")
      XCTAssertEqual(try shadowCount(db), 1)
      XCTAssertTrue(applier.payloads.isEmpty)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM error_logs WHERE source = ?",
          arguments: ["sync.apply.promote_shadow_version_mismatch"]),
        1)
    }
  }

  /// A REAL delete tombstone at/above the shadow's version wins: the shadow is
  /// dropped and the deleted entity is not resurrected.
  func testTombstonedTargetDropsShadowWithoutResurrection() throws {
    try withDB { db in
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: taskId,
        version: "1711234567890_0500_deadbeefdeadbeef", deletedAt: "2026-03-27T10:00:00Z")
      try insertShadow(db, version: "1711234567890_0200_deadbeefdeadbeef")

      XCTAssertEqual(try ApplyPromote.promotePayloadShadows(db, registry: registry()), 0)

      XCTAssertEqual(try shadowCount(db), 0, "shadow under a real tombstone must be reaped")
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM tasks WHERE id = ?", arguments: [taskId]),
        0, "promotion must not resurrect a tombstoned row")
    }
  }

  /// A shadow newer than a tombstone is not a complete resurrection payload:
  /// it contains only the fields the older runtime could not parse. Without an
  /// equal-version live row, promotion must retain both pieces of evidence and
  /// must not lift the deletion barrier merely because the shadow HLC is newer.
  func testNewerShadowWithoutLiveRowRetainsOlderTombstoneAndDoesNotDispatch() throws {
    try withDB { db in
      let tombstoneVersion = "1711234567890_0100_deadbeefdeadbeef"
      let shadowVersion = "1711234567890_0200_deadbeefdeadbeef"
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: taskId,
        version: tombstoneVersion, deletedAt: "2026-03-27T10:00:00Z")
      try insertShadow(db, version: shadowVersion)
      let applier = CapturingTaskApplier()

      XCTAssertEqual(
        try ApplyPromote.promotePayloadShadows(
          db, registry: EntityApplierRegistry(appliers: [applier])), 0)
      XCTAssertEqual(try shadowCount(db), 1)
      XCTAssertTrue(applier.payloads.isEmpty)
      XCTAssertEqual(
        try String.fetchOne(
          db,
          sql: "SELECT version FROM sync_tombstones WHERE entity_type = ? AND entity_id = ?",
          arguments: [EntityName.task, taskId]),
        tombstoneVersion)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM error_logs
            WHERE source = 'sync.apply.promote_shadow_unavailable_live_payload'
            """),
        1)
    }
  }

  /// With the matching known row present, the same newer shadow is a complete
  /// concurrent resurrection. Promotion may then lift the older tombstone and
  /// apply the reconstructed payload atomically.
  func testNewerShadowWithEqualLiveRowLiftsOlderTombstoneOnlyOnPromotion() throws {
    try withDB { db in
      let tombstoneVersion = "1711234567890_0100_deadbeefdeadbeef"
      let shadowVersion = "1711234567890_0200_deadbeefdeadbeef"
      try seedTask(db, version: shadowVersion)
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: taskId,
        version: tombstoneVersion, deletedAt: "2026-03-27T10:00:00Z")
      try insertShadow(db, version: shadowVersion)

      XCTAssertEqual(try ApplyPromote.promotePayloadShadows(db, registry: registry()), 1)
      XCTAssertEqual(try shadowCount(db), 0)
      XCTAssertNil(
        try String.fetchOne(
          db,
          sql: "SELECT version FROM sync_tombstones WHERE entity_type = ? AND entity_id = ?",
          arguments: [EntityName.task, taskId]))
      XCTAssertEqual(
        try String.fetchOne(db, sql: "SELECT body FROM tasks WHERE id = ?", arguments: [taskId]),
        "Recovered from shadow")
    }
  }

  func testMissingLiveRowRetainsShadowWithDiagnosticAndNoDispatch() throws {
    try withDB { db in
      try insertShadow(db, version: "1711234567890_0200_deadbeefdeadbeef")
      let applier = CapturingTaskApplier()

      XCTAssertEqual(
        try ApplyPromote.promotePayloadShadows(
          db, registry: EntityApplierRegistry(appliers: [applier])), 0)

      XCTAssertEqual(try shadowCount(db), 1)
      XCTAssertTrue(applier.payloads.isEmpty)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM error_logs
            WHERE source = 'sync.apply.promote_shadow_unavailable_live_payload'
            """),
        1)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM error_logs WHERE source = 'sync.apply.promote_shadow_failed'"),
        0)
    }
  }

  func testOlderLiveRowRetainsMismatchedShadowWithoutDispatch() throws {
    try withDB { db in
      try seedTask(db, version: "1711234567890_0100_deadbeefdeadbeef")
      try insertShadow(db, version: "1711234567890_0200_deadbeefdeadbeef")
      let applier = CapturingTaskApplier()

      XCTAssertEqual(
        try ApplyPromote.promotePayloadShadows(
          db, registry: EntityApplierRegistry(appliers: [applier])), 0)

      XCTAssertEqual(try shadowCount(db), 1)
      XCTAssertTrue(applier.payloads.isEmpty)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM error_logs
            WHERE source = 'sync.apply.promote_shadow_version_mismatch'
            """),
        1)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM error_logs WHERE source = 'sync.apply.promote_shadow_failed'"),
        0)
    }
  }

  func testCorruptLiveVersionRetainsShadowWithoutDispatch() throws {
    try withDB { db in
      let shadowVersion = "1711234567890_0200_deadbeefdeadbeef"
      try seedTask(db, version: shadowVersion)
      try insertShadow(db, version: shadowVersion)
      try SyncTestSupport.seedIgnoringCheckConstraints(db) {
        try db.execute(
          sql: "UPDATE tasks SET version = 'not-a-valid-hlc' WHERE id = ?",
          arguments: [taskId])
      }
      let applier = CapturingTaskApplier()

      XCTAssertEqual(
        try ApplyPromote.promotePayloadShadows(
          db, registry: EntityApplierRegistry(appliers: [applier])), 0)
      XCTAssertEqual(try shadowCount(db), 1)
      XCTAssertTrue(applier.payloads.isEmpty)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql:
            "SELECT COUNT(*) FROM error_logs WHERE source = 'sync.apply.local_version_corruption'"),
        1)
    }
  }

  /// The SQLite storage domain must match SyncEnvelope's nonzero UInt32 wire
  /// domain so no ordinary writer can persist a value that later traps or is
  /// silently normalized during promotion.
  func testPayloadShadowSchemaVersionCheckMatchesEnvelopeDomain() throws {
    try withDB { db in
      let version = "1711234567890_0200_deadbeefdeadbeef"
      for invalid in [-1, 0, Int(UInt32.max) + 1] {
        XCTAssertThrowsError(
          try insertShadow(db, version: version, schemaVersion: invalid),
          "schema unexpectedly accepted payload_schema_version \(invalid)")
      }

      try insertShadow(db, version: version, schemaVersion: Int(UInt32.max))
      XCTAssertEqual(try shadowCount(db), 1, "UInt32.max is a valid stored wire value")
    }
  }

  /// Legacy/manual rows can predate the schema CHECK. Promotion validates them
  /// before UInt32 conversion, retains the only preserved future fields, and
  /// emits a diagnostic instead of trapping startup maintenance.
  func testPromotionRetainsOutOfRangeSchemaVersionsWithoutTrapping() throws {
    let invalidVersions = [-1, 0, Int(UInt32.max) + 1]
    for invalid in invalidVersions {
      try withDB { db in
        let version = "1711234567890_0200_deadbeefdeadbeef"
        try SyncTestSupport.seedIgnoringCheckConstraints(db) {
          try self.insertShadow(db, version: version, schemaVersion: invalid)
        }
        let applier = CapturingTaskApplier()

        XCTAssertEqual(
          try ApplyPromote.promotePayloadShadows(
            db, registry: EntityApplierRegistry(appliers: [applier])), 0)
        XCTAssertEqual(try self.shadowCount(db), 1)
        XCTAssertTrue(applier.payloads.isEmpty)
        XCTAssertEqual(
          try Int.fetchOne(
            db,
            sql: """
              SELECT COUNT(*) FROM error_logs
              WHERE source = 'sync.apply.promote_shadow_invalid_schema_version'
              """),
          1)
      }
    }
  }
}
