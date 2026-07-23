import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Ports the parity `#[test]` cases for the `tag` applier + duplicate-tag merge
/// (Rust `tag/tests.rs`): upsert insert/LWW, lookup_key re-derivation, delete +
/// idempotent + stale-guard, and the merge contract (min-id-winner, task_tags
/// re-point, loser tombstone with redirect, winner-version stamping, observer
/// feedback, ceiling error, and the divergence conflict-log).
final class ApplyTagMergeTests: XCTestCase {

  /// Thread-safe capture box for the `@Sendable` observer closure.
  private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ v: T) { value = v }
    func mutate(_ f: (inout T) -> Void) {
      lock.lock()
      defer { lock.unlock() }
      f(&value)
    }
    func get() -> T {
      lock.lock()
      defer { lock.unlock() }
      return value
    }
  }

  private let vOld = "1711234567000_0000_dec0000100000001"
  private let vMid = "1711234568000_0000_dec0000100000001"
  private let vNew = "1711234569000_0000_dec0000100000001"

  private func withDB(_ body: (Database) throws -> Void) throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in try body(db) }
  }

  /// `lookup_key` is intentionally NOT trusted from the payload — `apply_tag_upsert`
  /// re-derives it from `display_name`. Pass it anyway for byte-shape parity.
  private func tagPayload(_ displayName: String, _ lookupKey: String, _ color: String?) -> String {
    let colorJSON = color.map { "\"\($0)\"" } ?? "null"
    return """
      {"display_name":"\(displayName)","lookup_key":"\(lookupKey)","color":\(colorJSON),"created_at":"2026-01-01T00:00:00.000Z","updated_at":"2026-01-01T00:00:00.000Z"}
      """
  }

  private func countTags(_ db: Database) throws -> Int64 {
    try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM tags") ?? -1
  }

  private func tagDisplayName(_ db: Database, _ id: String) throws -> String? {
    try String.fetchOne(db, sql: "SELECT display_name FROM tags WHERE id = ?", arguments: [id])
  }

  private func tagVersion(_ db: Database, _ id: String) throws -> String? {
    try String.fetchOne(db, sql: "SELECT version FROM tags WHERE id = ?", arguments: [id])
  }

  private func upsert(
    _ db: Database, _ id: String, _ payload: String, _ version: String,
    _ tieBreak: LwwTieBreak = .rejectEqual,
    applyTs: String = "2026-01-01T00:00:00.000Z"
  ) throws {
    try ApplyTagMerge.applyTagUpsert(
      db, entityId: id, payload: payload, version: version, tieBreak: tieBreak, applyTs: applyTs)
  }

  // MARK: - upsert

  func testUpsertInsertsNewTag() throws {
    try withDB { db in
      try self.upsert(db, "tag-001", self.tagPayload("Urgent", "urgent", "#ff0000"), self.vMid)
      XCTAssertEqual(try self.countTags(db), 1)
      XCTAssertEqual(try self.tagDisplayName(db, "tag-001"), "Urgent")
    }
  }

  func testUpsertRederivesLookupKeyFromDisplayNameIgnoringPayloadValue() throws {
    try withDB { db in
      try self.upsert(
        db, "tag-work", self.tagPayload("WORK", "not-the-canonical-key", nil), self.vMid)
      let stored = try String.fetchOne(
        db, sql: "SELECT lookup_key FROM tags WHERE id = ?", arguments: ["tag-work"])
      XCTAssertEqual(
        stored, "work",
        "apply must ignore the payload lookup_key and re-derive from display_name")
    }
  }

  func testUpsertUpdatesWhenVersionIsNewer() throws {
    try withDB { db in
      try self.upsert(db, "tag-001", self.tagPayload("OldName", "urgent", nil), self.vOld)
      try self.upsert(db, "tag-001", self.tagPayload("NewName", "urgent", "#00ff00"), self.vNew)
      XCTAssertEqual(try self.countTags(db), 1)
      XCTAssertEqual(try self.tagDisplayName(db, "tag-001"), "NewName")
      XCTAssertEqual(try self.tagVersion(db, "tag-001"), self.vNew)
    }
  }

  func testUpsertSkipsWhenVersionIsOlder() throws {
    try withDB { db in
      try self.upsert(db, "tag-001", self.tagPayload("Current", "urgent", nil), self.vNew)
      try self.upsert(db, "tag-001", self.tagPayload("Stale", "urgent", nil), self.vOld)
      XCTAssertEqual(try self.tagDisplayName(db, "tag-001"), "Current")
      XCTAssertEqual(try self.tagVersion(db, "tag-001"), self.vNew)
    }
  }

  // MARK: - delete

  func testDeleteRemovesExistingTag() throws {
    try withDB { db in
      try self.upsert(db, "tag-del", self.tagPayload("Bye", "bye", nil), self.vMid)
      XCTAssertEqual(try self.countTags(db), 1)
      try ApplyTagMerge.applyTagDelete(db, entityId: "tag-del", version: self.vNew)
      XCTAssertEqual(try self.countTags(db), 0)
    }
  }

  func testDeleteIsIdempotentForMissingTag() throws {
    try withDB { db in
      try ApplyTagMerge.applyTagDelete(db, entityId: "nonexistent", version: self.vNew)
      XCTAssertEqual(try self.countTags(db), 0)
    }
  }

  func testStaleDeleteEnvelopeIsRefusedByInRowLwwGuard() throws {
    try withDB { db in
      try self.upsert(db, "tag-stay", self.tagPayload("Stay", "stay", nil), self.vNew)
      XCTAssertEqual(try self.countTags(db), 1)
      try ApplyTagMerge.applyTagDelete(db, entityId: "tag-stay", version: self.vOld)
      XCTAssertEqual(
        try self.countTags(db), 1, "stale delete (V_OLD) MUST NOT remove a row at V_NEW")
    }
  }

  // MARK: - merge

  /// Identity stays with the min id (`aaa`) and its `task_tags` edge, while the
  /// higher-HLC loser's CONTENT is carried onto that surviving id.
  func testMergeKeepsSmallerIdAndCarriesMaxHlcLoserContent() throws {
    try withDB { db in
      try self.upsert(
        db, "00000000-0000-7000-8000-000000000001", self.tagPayload("WinnerTag", "unused", nil),
        self.vMid)
      try db.execute(
        sql:
          "INSERT INTO tasks (id, title, status, version, created_at, updated_at) VALUES ('task-1', 'T', 'open', '0000000000000_0000_0000000000000000', '', '')"
      )
      try db.execute(
        sql:
          "INSERT INTO task_tags (task_id, tag_id, created_at, version) VALUES ('task-1', '00000000-0000-7000-8000-000000000001', '2026-01-01', '0000000000000_0000_0000000000000000')"
      )

      try self.upsert(
        db, "ffffffff-ffff-7fff-8fff-ffffffffffff",
        self.tagPayload("winnertag", "unused", "#111111"), self.vNew)

      XCTAssertEqual(try self.countTags(db), 1)
      // Identity = min id (aaa); content = max-HLC participant (zzz), carried onto aaa.
      XCTAssertEqual(
        try self.tagDisplayName(db, "00000000-0000-7000-8000-000000000001"), "winnertag")
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT color FROM tags WHERE id = '00000000-0000-7000-8000-000000000001'"),
        "#111111")
      XCTAssertNil(try self.tagDisplayName(db, "ffffffff-ffff-7fff-8fff-ffffffffffff"))

      XCTAssertNotNil(
        try Tombstone.getTombstone(
          db, entityType: EntityName.tag,
          entityId: "ffffffff-ffff-7fff-8fff-ffffffffffff"))
      XCTAssertEqual(
        try EntityRedirect.get(
          db, sourceType: EntityName.tag,
          sourceId: "ffffffff-ffff-7fff-8fff-ffffffffffff")?.targetId,
        "00000000-0000-7000-8000-000000000001")

      let tagId = try String.fetchOne(
        db, sql: "SELECT tag_id FROM task_tags WHERE task_id = 'task-1'")
      XCTAssertEqual(tagId, "00000000-0000-7000-8000-000000000001")
    }
  }

  func testFutureSchemaCollisionDefersWithoutMutatingExistingWinner() throws {
    let smallerId = "00000000-0000-7000-8000-000000000001"
    let largerId = "ffffffff-ffff-7fff-8fff-ffffffffffff"
    let registry = EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
    try withDB { db in
      let earlier = try SyncTestSupport.completeEnvelope(
        entityType: .tag, entityId: smallerId, operation: .upsert,
        version: try Hlc.parse(self.vMid),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: self.tagPayload("Shared", "ignored", "#111111"),
        deviceId: "device-earlier")
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: registry, envelope: earlier), .applied)

      let futurePayload = try SyncCanonicalize.canonicalizeJSON(
        .object([
          "display_name": .string("shared"),
          "color": .string("#222222"),
          "created_at": .string("2026-01-01T00:00:00Z"),
          "updated_at": .string("2026-01-01T00:00:01Z"),
          "future_field": .string("preserve-me"),
        ]))
      let future = try SyncTestSupport.completeEnvelope(
        entityType: .tag, entityId: largerId, operation: .upsert,
        version: try Hlc.parse(self.vNew),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion + 1,
        payload: futurePayload, deviceId: "device-future")
      guard
        case .deferred(.aggregateInvariantBlocked(let kind, let entityId, let invariant)) =
          try Apply.applyEnvelope(db, registry: registry, envelope: future)
      else { return XCTFail("future-shadow collision must defer") }
      XCTAssertEqual(kind, .tag)
      XCTAssertEqual(entityId, smallerId)
      XCTAssertTrue(invariant.contains("schema-aware cross-id merge"))

      XCTAssertEqual(try self.countTags(db), 1)
      XCTAssertEqual(try self.tagDisplayName(db, smallerId), "Shared")
      XCTAssertNil(try self.tagDisplayName(db, largerId))
      XCTAssertNil(
        try PayloadShadow.getShadow(db, entityType: EntityName.tag, entityID: largerId))
      XCTAssertNil(
        try EntityRedirect.get(db, sourceType: EntityName.tag, sourceId: largerId))
      XCTAssertNil(
        try Tombstone.getTombstone(db, entityType: EntityName.tag, entityId: largerId))
    }
  }

  func testKnownSchemaCollisionDefersWhenExistingParticipantHasFutureShadow() throws {
    let smallerId = "00000000-0000-7000-8000-000000000001"
    let largerId = "ffffffff-ffff-7fff-8fff-ffffffffffff"
    let registry = EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
    try withDB { db in
      let futurePayload = try SyncCanonicalize.canonicalizeJSON(
        .object([
          "display_name": .string("Shared"),
          "color": .string("#111111"),
          "created_at": .string("2026-01-01T00:00:00Z"),
          "updated_at": .string("2026-01-01T00:00:00Z"),
          "future_field": .string("losing-value"),
        ]))
      let futureEarlier = try SyncTestSupport.completeEnvelope(
        entityType: .tag, entityId: smallerId, operation: .upsert,
        version: try Hlc.parse(self.vMid),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion + 1,
        payload: futurePayload, deviceId: "device-future")
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: registry, envelope: futureEarlier), .applied)
      XCTAssertNotNil(
        try PayloadShadow.getShadow(db, entityType: EntityName.tag, entityID: smallerId))

      let knownLater = try SyncTestSupport.completeEnvelope(
        entityType: .tag, entityId: largerId, operation: .upsert,
        version: try Hlc.parse(self.vNew),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: self.tagPayload("shared", "ignored", "#222222"),
        deviceId: "device-known")
      guard
        case .deferred(.aggregateInvariantBlocked(let kind, let entityId, let invariant)) =
          try Apply.applyEnvelope(db, registry: registry, envelope: knownLater)
      else { return XCTFail("collision with an existing future shadow must defer") }
      XCTAssertEqual(kind, .tag)
      XCTAssertEqual(entityId, smallerId)
      XCTAssertTrue(invariant.contains("schema-aware cross-id merge"))

      XCTAssertEqual(try self.countTags(db), 1)
      XCTAssertEqual(try self.tagDisplayName(db, smallerId), "Shared")
      XCTAssertNil(try self.tagDisplayName(db, largerId))
      let retained = try XCTUnwrap(
        PayloadShadow.getShadow(db, entityType: EntityName.tag, entityID: smallerId))
      guard case .object(let retainedObject)? = JSONValue.parse(retained.rawPayloadJSON) else {
        return XCTFail("future shadow must remain an object")
      }
      XCTAssertEqual(retainedObject["future_field"], .string("losing-value"))
      XCTAssertNil(
        try EntityRedirect.get(db, sourceType: EntityName.tag, sourceId: largerId))
      XCTAssertNil(
        try Tombstone.getTombstone(db, entityType: EntityName.tag, entityId: largerId))
    }
  }

  func testMergeRepointsTaskTagsFromLoserToWinner() throws {
    try withDB { db in
      try self.upsert(
        db, "11111111-1111-7111-8111-111111111111", self.tagPayload("shared", "unused", nil),
        self.vOld)
      for (id, title) in [("t1", "Task1"), ("t2", "Task2")] {
        try db.execute(
          sql:
            "INSERT INTO tasks (id, title, status, version, created_at, updated_at) VALUES (?, ?, 'open', '0000000000000_0000_0000000000000000', '', '')",
          arguments: [id, title])
      }
      try db.execute(
        sql:
          "INSERT INTO task_tags (task_id, tag_id, created_at, version) VALUES ('t1', '11111111-1111-7111-8111-111111111111', '', '0000000000000_0000_0000000000000000')"
      )
      try self.upsert(
        db, "eeeeeeee-eeee-7eee-8eee-eeeeeeeeeeee", self.tagPayload("unrelated", "unused", nil),
        self.vOld)
      try db.execute(
        sql:
          "INSERT INTO task_tags (task_id, tag_id, created_at, version) VALUES ('t2', 'eeeeeeee-eeee-7eee-8eee-eeeeeeeeeeee', '', '0000000000000_0000_0000000000000000')"
      )

      try self.upsert(
        db, "eeeeeeee-eeee-7eee-8eee-eeeeeeeeeeee", self.tagPayload("Shared", "unused", nil),
        self.vNew)

      XCTAssertEqual(try self.countTags(db), 1)
      XCTAssertNotNil(try self.tagDisplayName(db, "11111111-1111-7111-8111-111111111111"))
      XCTAssertNil(try self.tagDisplayName(db, "eeeeeeee-eeee-7eee-8eee-eeeeeeeeeeee"))

      let tasks = try String.fetchAll(
        db,
        sql:
          "SELECT task_id FROM task_tags WHERE tag_id = '11111111-1111-7111-8111-111111111111' ORDER BY task_id"
      )
      XCTAssertEqual(tasks, ["t1", "t2"])
      let betaCount = try Int64.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM task_tags WHERE tag_id = 'eeeeeeee-eeee-7eee-8eee-eeeeeeeeeeee'")
      XCTAssertEqual(betaCount, 0)
    }
  }

  func testNoMergeWhenLookupKeysDiffer() throws {
    try withDB { db in
      try self.upsert(db, "tag-a", self.tagPayload("Tag A", "key_a", nil), self.vMid)
      try self.upsert(db, "tag-b", self.tagPayload("Tag B", "key_b", nil), self.vMid)
      XCTAssertEqual(try self.countTags(db), 2)
      XCTAssertNotNil(try self.tagDisplayName(db, "tag-a"))
      XCTAssertNotNil(try self.tagDisplayName(db, "tag-b"))
    }
  }

  func testStaleEnvelopeDoesNotTriggerMerge() throws {
    try withDB { db in
      try self.upsert(
        db, "00000000-0000-7000-8000-000000000001", self.tagPayload("Winner", "dup_key", nil),
        self.vNew)
      try self.upsert(
        db, "ffffffff-ffff-7fff-8fff-ffffffffffff", self.tagPayload("Other", "other_key", nil),
        self.vMid)
      XCTAssertEqual(try self.countTags(db), 2)
      try self.upsert(
        db, "ffffffff-ffff-7fff-8fff-ffffffffffff",
        self.tagPayload("StaleCollision", "dup_key", nil), self.vOld)
      XCTAssertEqual(try self.countTags(db), 2)
      XCTAssertEqual(try self.tagDisplayName(db, "ffffffff-ffff-7fff-8fff-ffffffffffff"), "Other")
    }
  }

  func testMergeStampsWinnerTagVersionAtMergeVersion() throws {
    try withDB { db in
      try self.upsert(
        db, "00000000-0000-7000-8000-000000000001", self.tagPayload("Shared", "unused", nil),
        self.vMid)
      try self.upsert(
        db, "ffffffff-ffff-7fff-8fff-ffffffffffff", self.tagPayload("shared", "unused", nil),
        self.vNew)

      XCTAssertNotNil(try self.tagDisplayName(db, "00000000-0000-7000-8000-000000000001"))
      XCTAssertNil(try self.tagDisplayName(db, "ffffffff-ffff-7fff-8fff-ffffffffffff"))

      let winnerVersion = try XCTUnwrap(
        try self.tagVersion(db, "00000000-0000-7000-8000-000000000001"))
      let tombstoneVersion = try String.fetchOne(
        db,
        sql: "SELECT version FROM sync_tombstones WHERE entity_type = ? AND entity_id = ?",
        arguments: [EntityName.tag, "ffffffff-ffff-7fff-8fff-ffffffffffff"])
      XCTAssertEqual(
        winnerVersion, tombstoneVersion,
        "winner.version must equal merge_version (== loser tombstone version)")

      let winnerHlc = try Hlc.parse(winnerVersion)
      let triggeringHlc = try Hlc.parse(self.vNew)
      XCTAssertTrue(winnerHlc > triggeringHlc, "winner.version must be > triggering version")
      // Bug 2: the merge stamp's suffix is the dominating participant's own suffix
      // (`maxHlc.deviceSuffix`), a deterministic function of the participant set.
      XCTAssertEqual(
        winnerHlc.deviceSuffix, try Hlc.parse(self.vNew).deviceSuffix,
        "merge stamp suffix must be the dominating participant's suffix (maxHlc.deviceSuffix)")
    }
  }

  func testMergeObservesLocalEventWithMergeVersion() throws {
    try withDB { db in
      let observed = Box<[Hlc]>([])
      let state = try Box<HlcState>(HlcState(deviceSuffix: "a1b2c3d4e5f60718"))

      let winnerVersion = try SyncHlcObserver.withTemporaryObserver({ hlc in
        observed.mutate { $0.append(hlc) }
        state.mutate { $0.updateOnReceive(remote: hlc, physicalMs: hlc.physicalMs) }
      }) { () throws -> String in
        try self.upsert(
          db, "00000000-0000-7000-8000-000000000001", self.tagPayload("Shared", "unused", nil),
          self.vMid)
        try self.upsert(
          db, "ffffffff-ffff-7fff-8fff-ffffffffffff", self.tagPayload("shared", "unused", nil),
          self.vNew)
        return try XCTUnwrap(try self.tagVersion(db, "00000000-0000-7000-8000-000000000001"))
      }

      let mergeHlc = try Hlc.parse(winnerVersion)
      let observedList = observed.get()
      XCTAssertTrue(
        observedList.contains(where: { $0 == mergeHlc }),
        "observer must have received merge_version \(winnerVersion); got \(observedList)")

      var next: Hlc!
      state.mutate { next = $0.generate(withPhysicalMs: mergeHlc.physicalMs) }
      XCTAssertTrue(
        next > mergeHlc, "next generated HLC (\(next!)) must strictly exceed merge_version")
    }
  }

  func testMergeReportsClearErrorWhenNoOperationalWireHlcSuccessorExists() throws {
    try withDB { db in
      let ceiling = Hlc.maxOperationalWirePhysicalMs
      let maxCounter = Hlc.maxCounter
      let winnerVersion =
        "\(ceiling)_" + String(format: "%04d", maxCounter - 1) + "_dec0000100000001"
      let loserVersion = "\(ceiling)_" + String(format: "%04d", maxCounter) + "_dec0000200000002"

      try self.upsert(
        db, "00000000-0000-7000-8000-000000000001", self.tagPayload("Shared", "unused", nil),
        winnerVersion)
      XCTAssertThrowsError(
        try self.upsert(
          db, "ffffffff-ffff-7fff-8fff-ffffffffffff", self.tagPayload("shared", "unused", nil),
          loserVersion)
      ) { error in
        guard case ApplyError.invalidVersion(let message) = error else {
          return XCTFail("expected invalidVersion, got \(error)")
        }
        XCTAssertTrue(
          message.contains("tag merge")
            && message.contains("no operational wire HLC successor")
            && message.contains(loserVersion),
          "unexpected ceiling error message: \(message)")
      }
    }
  }

  /// When the max-HLC content comes from a higher-id loser, the surviving min-id
  /// row itself becomes the CONTENT-loser: its discarded `display_name` / `color`
  /// are logged at ITS OWN version, and the winner id ends up holding the loser's
  /// content.
  func testMergeCarriesMaxHlcContentAndLogsMinIdRowFieldsAtItsOwnVersion() throws {
    try withDB { db in
      try self.upsert(
        db, "00000000-0000-7000-8000-000000000001", self.tagPayload("WinnerTag", "unused", nil),
        self.vMid, applyTs: "2026-01-01T00:00:01.000Z")
      try self.upsert(
        db, "ffffffff-ffff-7fff-8fff-ffffffffffff",
        self.tagPayload("winnertag", "unused", "#0066ff"), self.vNew,
        applyTs: "2026-01-01T00:00:02.000Z")

      // Surviving min-id row now holds the max-HLC loser's content.
      XCTAssertEqual(
        try self.tagDisplayName(db, "00000000-0000-7000-8000-000000000001"), "winnertag")
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT color FROM tags WHERE id = '00000000-0000-7000-8000-000000000001'"),
        "#0066ff")
      XCTAssertNil(try self.tagDisplayName(db, "ffffffff-ffff-7fff-8fff-ffffffffffff"))

      let row = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT loser_version, loser_device_id, loser_payload, resolution_type, resolved_at
            FROM sync_conflict_log WHERE entity_type = ? AND entity_id = ?
            """,
          arguments: [EntityName.tag, "00000000-0000-7000-8000-000000000001"]))

      XCTAssertEqual(row["resolution_type"] as String?, ResolutionName.tagMerge)
      // The content-loser is the min-id row itself, so its own version (vMid) is
      // recorded, not the max-HLC participant's.
      XCTAssertEqual(row["loser_version"] as String?, self.vMid)
      let expectedSuffix = try Hlc.parse(self.vMid).deviceSuffix
      XCTAssertEqual(row["loser_device_id"] as String?, expectedSuffix)
      XCTAssertEqual(row["resolved_at"] as String?, "2026-01-01T00:00:02.000Z")

      let payload = try XCTUnwrap(row["loser_payload"] as String?)
      let parsed = try XCTUnwrap(JSONValue.parse(payload).flatMap(ApplyJSON.object))
      // The discarded fields are the min-id row's own values (measured against P*).
      XCTAssertEqual(parsed["display_name"], .string("WinnerTag"))
      XCTAssertEqual(parsed["color"], .null)
      // Byte-for-byte key order parity: the canonical serializer sorts keys, so
      // `color` precedes `display_name`. `loser_payload` is not PII-scrubbed
      // (neither key is in the redaction set), so the stored TEXT must match exactly.
      XCTAssertEqual(payload, "{\"color\":null,\"display_name\":\"WinnerTag\"}")
    }
  }

  func testMergeDoesNotLogConflictWhenLoserFieldsMatchWinner() throws {
    try withDB { db in
      try self.upsert(
        db, "00000000-0000-7000-8000-000000000001", self.tagPayload("Shared", "unused", "#abcdef"),
        self.vMid, applyTs: "2026-01-01T00:00:01.000Z")
      try self.upsert(
        db, "ffffffff-ffff-7fff-8fff-ffffffffffff", self.tagPayload("Shared", "unused", "#abcdef"),
        self.vNew, applyTs: "2026-01-01T00:00:02.000Z")

      XCTAssertNil(try self.tagDisplayName(db, "ffffffff-ffff-7fff-8fff-ffffffffffff"))
      let conflictCount = try Int64.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM sync_conflict_log WHERE entity_type = ? AND resolution_type = ?",
        arguments: [EntityName.tag, ResolutionName.tagMerge])
      XCTAssertEqual(
        conflictCount, 0, "lossless merge must not record a tag_merge conflict_log row")
    }
  }

  // MARK: - max-HLC content convergence

  /// Both apply orders converge on the SAME (winner id, surviving content): the
  /// min-id winner always ends holding the max-HLC participant's content,
  /// regardless of which side arrived first.
  func testBothApplyOrdersConvergeOnIdAndContent() throws {
    var contentA: String?
    try withDB { db in
      try self.upsert(
        db, "00000000-0000-7000-8000-000000000001", self.tagPayload("Alpha", "unused", "#a0a0a0"),
        self.vMid)
      try self.upsert(
        db, "ffffffff-ffff-7fff-8fff-ffffffffffff", self.tagPayload("alpha", "unused", "#b0b0b0"),
        self.vNew)
      contentA = try self.tagDisplayName(db, "00000000-0000-7000-8000-000000000001")
    }
    var contentB: String?
    try withDB { db in
      try self.upsert(
        db, "ffffffff-ffff-7fff-8fff-ffffffffffff", self.tagPayload("alpha", "unused", "#b0b0b0"),
        self.vNew)
      try self.upsert(
        db, "00000000-0000-7000-8000-000000000001", self.tagPayload("Alpha", "unused", "#a0a0a0"),
        self.vMid)
      contentB = try self.tagDisplayName(db, "00000000-0000-7000-8000-000000000001")
    }
    XCTAssertEqual(contentA, "alpha", "surviving content is the max-HLC participant's")
    XCTAssertEqual(contentA, contentB, "content converges regardless of apply order")
  }

  /// An edit targeting the tombstoned loser id after the merge redirects onto the
  /// winner and, at a higher HLC, overwrites the carried content via LWW. Uses
  /// canonical UUID ids because the full envelope path enforces id format.
  func testPostMergeEditToTombstonedLoserRedirectsAndWinsViaLww() throws {
    let smallerId = "00000000-0000-7000-8000-000000000001"
    let largerId = "ffffffff-ffff-7fff-8fff-ffffffffffff"
    let registry = EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
    try withDB { db in
      try self.upsert(db, smallerId, self.tagPayload("Alpha", "unused", nil), self.vMid)
      try self.upsert(db, largerId, self.tagPayload("alpha", "unused", "#0066ff"), self.vNew)
      XCTAssertEqual(try self.tagDisplayName(db, smallerId), "alpha")

      let vNewer = "1711234570000_0000_dec0000100000001"
      let env = try SyncTestSupport.completeEnvelope(
        entityType: .tag, entityId: largerId, operation: .upsert, version: try Hlc.parse(vNewer),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: self.tagPayload("AlphaEdited", "unused", "#00ff00"), deviceId: "device-remote")
      _ = try Apply.applyEnvelope(db, registry: registry, envelope: env)

      XCTAssertEqual(
        try self.tagDisplayName(db, smallerId), "AlphaEdited",
        "an edit to the tombstoned loser id redirects onto the winner and wins LWW")
      XCTAssertNil(try self.tagDisplayName(db, largerId))
    }
  }

  /// Equal HLCs across the cluster degenerate to the pre-change behavior: the
  /// min-id row's content survives (the tiebreak keeps the lower id as `P*`).
  func testEqualHlcTiebreakKeepsMinIdContent() throws {
    try withDB { db in
      try self.upsert(
        db, "00000000-0000-7000-8000-000000000001", self.tagPayload("Alpha", "unused", "#a0a0a0"),
        self.vMid)
      try self.upsert(
        db, "ffffffff-ffff-7fff-8fff-ffffffffffff", self.tagPayload("alpha", "unused", "#00ff00"),
        self.vMid)

      XCTAssertEqual(try self.countTags(db), 1)
      XCTAssertEqual(
        try self.tagDisplayName(db, "00000000-0000-7000-8000-000000000001"), "Alpha",
        "on an equal-HLC tie the min-id content survives")
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT color FROM tags WHERE id = '00000000-0000-7000-8000-000000000001'"),
        "#a0a0a0")
    }
  }

  /// An N=3 cluster: `P*` is the GLOBAL max-HLC participant (here the middle id),
  /// its content is carried onto the min-id winner, and N−1 = 2 conflict rows are
  /// logged — one per content-loser, each at its own version.
  func testThreeWayClusterCarriesGlobalMaxHlcAndLogsTwoContentLosers() throws {
    try withDB { db in
      for (id, name, color, ver) in [
        ("00000000-0000-7000-8000-000000000001", "Aay", "#a00000", self.vOld),
        ("88888888-8888-7888-8888-888888888888", "Bee", "#b00000", self.vNew),
        ("ffffffff-ffff-7fff-8fff-ffffffffffff", "Cee", "#c00000", self.vMid),
      ] {
        try db.execute(
          sql: """
            INSERT INTO tags (id, display_name, lookup_key, color, version, created_at, updated_at)
             VALUES (?, ?, 'shared', ?, ?, ?, ?)
            """,
          arguments: [id, name, color, ver, "2026-01-01T00:00:00.000Z", "2026-01-01T00:00:00.000Z"])
      }

      _ = try ApplyTagMerge.merger.mergeKnownDuplicate(
        db,
        rows: [
          ("00000000-0000-7000-8000-000000000001", self.vOld),
          ("88888888-8888-7888-8888-888888888888", self.vNew),
          ("ffffffff-ffff-7fff-8fff-ffffffffffff", self.vMid),
        ],
        triggeringVersion: self.vNew, applyTs: "2026-01-01T00:00:03.000Z")

      XCTAssertEqual(try self.countTags(db), 1)
      // Content = the GLOBAL argmax (bbb, vNew), carried onto the min-id winner (aaa).
      XCTAssertEqual(try self.tagDisplayName(db, "00000000-0000-7000-8000-000000000001"), "Bee")
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT color FROM tags WHERE id = '00000000-0000-7000-8000-000000000001'"),
        "#b00000")

      // N−1 conflict rows: the two content-losers (aaa, ccc) at their own versions.
      let loserVersions = try String.fetchAll(
        db,
        sql: """
          SELECT loser_version FROM sync_conflict_log
           WHERE entity_type = ? AND entity_id = '00000000-0000-7000-8000-000000000001' ORDER BY loser_version
          """,
        arguments: [EntityName.tag])
      XCTAssertEqual(loserVersions, [self.vOld, self.vMid])
    }
  }

  // MARK: - Bug 2: deterministic merge-stamp suffix (cross-peer version convergence)

  /// A 3-participant slot collision — `V_a=(t,0,sa)`, `V_b=(t,0,sb)` sharing the
  /// `(t,0)` slot with `sb>sa`, and `V_c=(t,1,sc)` dominating — mints a winner
  /// version `(t, 2, sc)` whose suffix is the DOMINATING participant's suffix
  /// (`maxHlc.deviceSuffix`), never the local device's. Two peers with DIFFERENT
  /// device ids that apply the same participants therefore land on a byte-identical
  /// winner version (and content), regardless of the order the rows are folded in.
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
        for (id, name, color, ver) in [
          (idA, "aaa-name", "#aaaaaa", vA),
          (idB, "bbb-name", "#bbbbbb", vB),
          (idC, "ccc-name", "#cccccc", vC),
        ] {
          try db.execute(
            sql: """
              INSERT INTO tags (id, display_name, lookup_key, color, version, created_at, updated_at)
               VALUES (?, ?, 'shared', ?, ?, ?, ?)
              """,
            arguments: [id, name, color, ver, "2026-01-01T00:00:00.000Z", "2026-01-01T00:00:00.000Z"])
        }
        _ = try ApplyTagMerge.merger.mergeKnownDuplicate(
          db, rows: rowOrder, triggeringVersion: vC,
          applyTs: "2026-01-01T00:00:00.000Z")
        return (try self.tagDisplayName(db, idA), try self.tagVersion(db, idA))
      }
    }

    let peerOne = try run(deviceId: "device-one-1111", rowOrder: [(idA, vA), (idB, vB), (idC, vC)])
    let peerTwo = try run(deviceId: "device-two-2222", rowOrder: [(idC, vC), (idB, vB), (idA, vA)])

    XCTAssertEqual(
      peerOne.0, "ccc-name", "content = the dominating participant (V_c), carried onto min id")
    XCTAssertEqual(
      peerOne.1, expectedVersion, "winner version = (maxHlc.phys, counter+1, maxHlc.suffix)")
    XCTAssertEqual(
      peerOne.0, peerTwo.0, "content byte-identical across peers with different device ids")
    XCTAssertEqual(
      peerOne.1, peerTwo.1, "winner version byte-identical across peers (deterministic suffix)")
  }
}
