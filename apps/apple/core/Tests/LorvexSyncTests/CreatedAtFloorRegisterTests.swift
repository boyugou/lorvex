import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// `created_at` on the merge-family aggregates (tag, habit, habit reminder
/// policy) is a min-register: every payload addressed to a row's identity —
/// including payloads remapped through a permanent alias, and including
/// version-skipped payloads — lowers the row's creation floor to the minimum
/// observed value, and an aggregate collapse folds the participant-set minimum.
/// These tests pin arrival-order independence of the floor across the three
/// real inbound shapes: deferred-alias replay, a late source upsert that wins
/// target LWW after remap, and a late source upsert that loses target LWW and
/// is skipped before dispatch (where the skip-site fold is the only witness of
/// the source's creation time this peer ever applies).
final class CreatedAtFloorRegisterTests: XCTestCase {
  private let targetId = "00000000-0000-7000-8000-000000000001"
  private let sourceId = "ffffffff-ffff-7fff-8fff-ffffffffffff"
  private let aliasVersion = "1800000000200_0000_2222333344445555"
  private let sourceVersion = "1800000000300_0000_5555666677778888"
  private let targetCreatedAt = "2026-07-01T00:00:00.000Z"
  private let sourceCreatedAt = "2026-06-30T00:00:00.000Z"
  private let registry = EntityApplierRegistry(
    appliers: EntityApplierRegistry.defaultEntityAppliers())

  private func aliasEnvelope() throws -> SyncEnvelope {
    try EntityRedirect.makeEnvelope(
      record: EntityRedirect.Record(
        sourceType: .habit, sourceId: sourceId, targetId: targetId,
        version: aliasVersion, createdAt: targetCreatedAt),
      deviceId: "remote-device")
  }

  private func habitEnvelope(
    entityId: String, name: String, version: String, createdAt: String, updatedAt: String
  ) throws -> SyncEnvelope {
    let supplied = try SyncCanonicalize.canonicalizeJSON(
      .object([
        "name": .string(name), "frequency_type": .string("daily"),
        "target_count": .int(1), "archived": .bool(false), "position": .int(0),
        "icon": .null, "color": .null, "cue": .null, "milestone_target": .null,
        "created_at": .string(createdAt), "updated_at": .string(updatedAt),
      ]))
    return try SyncTestSupport.completeEnvelope(
      entityType: .habit, entityId: entityId, operation: .upsert,
      version: try Hlc.parse(version),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: supplied, deviceId: "remote-device")
  }

  private func sourceEnvelope() throws -> SyncEnvelope {
    try habitEnvelope(
      entityId: sourceId, name: "Renamed Source", version: sourceVersion,
      createdAt: sourceCreatedAt, updatedAt: "2026-07-03T00:00:00.000Z")
  }

  private func targetEnvelope(version: String) throws -> SyncEnvelope {
    try habitEnvelope(
      entityId: targetId, name: "Original Target", version: version,
      createdAt: targetCreatedAt, updatedAt: targetCreatedAt)
  }

  private func insertHabit(
    _ db: Database, id: String, name: String, lookupKey: String,
    version: String, createdAt: String, updatedAt: String
  ) throws {
    try db.execute(
      sql: """
        INSERT INTO habits
          (id, name, frequency_type, target_count, archived, lookup_key, position,
           version, created_at, updated_at)
        VALUES (?, ?, 'daily', 1, 0, ?, 0, ?, ?, ?)
        """,
      arguments: [id, name, lookupKey, version, createdAt, updatedAt])
  }

  private func snapshot(_ db: Database) throws -> String {
    try SyncCanonicalize.canonicalizeJSON(
      try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: EntityName.habit, entityId: targetId))
  }

  /// The reference peer: both rows live when the alias arrives, so the
  /// aggregate engine collapses them and folds the participant-set minimum.
  private func collapsePeerSnapshot(targetVersion: String) throws -> String {
    let store = try SyncTestSupport.freshStore()
    return try store.writer.write { db in
      try insertHabit(
        db, id: targetId, name: "Original Target", lookupKey: "original target",
        version: targetVersion, createdAt: targetCreatedAt, updatedAt: targetCreatedAt)
      try insertHabit(
        db, id: sourceId, name: "Renamed Source", lookupKey: "renamed source",
        version: sourceVersion, createdAt: sourceCreatedAt,
        updatedAt: "2026-07-03T00:00:00.000Z")
      _ = try Apply.applyEnvelope(db, registry: registry, envelope: try aliasEnvelope())
      return try snapshot(db)
    }
  }

  private func assertFloor(_ payloadJSON: String, version: String, name: String) throws {
    guard case .object(let payload)? = JSONValue.parse(payloadJSON) else {
      return XCTFail("habit payload must be an object")
    }
    XCTAssertEqual(payload["created_at"], .string(sourceCreatedAt))
    XCTAssertEqual(payload["version"], .string(version))
    XCTAssertEqual(payload["name"], .string(name))
  }

  /// An alias whose target this peer has never seen defers wholesale (no
  /// durable redirect yet); the pending-inbox replay after both rows landed
  /// runs the ordinary live collapse and folds the floor.
  func testDeferredAliasReplayConvergesWithCollapsePeer() throws {
    let targetVersion = "1800000000100_0000_1111222233334444"
    let store = try SyncTestSupport.freshStore()
    let replayed = try store.writer.write { db -> String in
      let first = try Apply.applyEnvelope(
        db, registry: registry, envelope: try aliasEnvelope())
      guard case .deferred = first else {
        XCTFail("alias without a known target must defer, got \(first)")
        return ""
      }
      XCTAssertNil(try EntityRedirect.get(db, sourceType: EntityName.habit, sourceId: sourceId))
      _ = try Apply.applyEnvelope(db, registry: registry, envelope: try sourceEnvelope())
      _ = try Apply.applyEnvelope(
        db, registry: registry, envelope: try targetEnvelope(version: targetVersion))
      _ = try Apply.applyEnvelope(db, registry: registry, envelope: try aliasEnvelope())
      return try snapshot(db)
    }
    XCTAssertEqual(replayed, try collapsePeerSnapshot(targetVersion: targetVersion))
    try assertFloor(replayed, version: sourceVersion, name: "Renamed Source")
  }

  /// Alias-first peer that never held the source row live: the late
  /// source-addressed upsert remaps onto the live target, wins its LWW, and the
  /// gated DO UPDATE folds `min(existing, incoming)` instead of overwriting.
  func testAliasFirstLateSourceUpsertWinsAndFoldsFloor() throws {
    let targetVersion = "1800000000100_0000_1111222233334444"
    let store = try SyncTestSupport.freshStore()
    let result = try store.writer.write { db -> String in
      try insertHabit(
        db, id: targetId, name: "Original Target", lookupKey: "original target",
        version: targetVersion, createdAt: targetCreatedAt, updatedAt: targetCreatedAt)
      _ = try Apply.applyEnvelope(db, registry: registry, envelope: try aliasEnvelope())
      let remap = try Apply.applyEnvelope(
        db, registry: registry, envelope: try sourceEnvelope())
      guard case .remapped = remap else {
        XCTFail("late source upsert must remap through the alias, got \(remap)")
        return ""
      }
      return try snapshot(db)
    }
    XCTAssertEqual(result, try collapsePeerSnapshot(targetVersion: targetVersion))
    try assertFloor(result, version: sourceVersion, name: "Renamed Source")
  }

  /// Alias-first peer whose target carries a NEWER version than the late source
  /// upsert: the remapped payload is version-skipped before dispatch, and the
  /// skip-site fold is the only application of the source's creation floor this
  /// peer ever performs. Without it the peer would keep the target's later
  /// `created_at` forever while collapse peers converge on the minimum.
  func testAliasFirstStaleSourceUpsertSkipsButFoldsFloor() throws {
    let newerTargetVersion = "1800000000900_0000_1111222233334444"
    let store = try SyncTestSupport.freshStore()
    let result = try store.writer.write { db -> String in
      try insertHabit(
        db, id: targetId, name: "Original Target", lookupKey: "original target",
        version: newerTargetVersion, createdAt: targetCreatedAt, updatedAt: targetCreatedAt)
      _ = try Apply.applyEnvelope(db, registry: registry, envelope: try aliasEnvelope())
      let remap = try Apply.applyEnvelope(
        db, registry: registry, envelope: try sourceEnvelope())
      guard case .skipped = remap else {
        XCTFail("stale remapped source upsert must skip on target LWW, got \(remap)")
        return ""
      }
      return try snapshot(db)
    }
    XCTAssertEqual(result, try collapsePeerSnapshot(targetVersion: newerTargetVersion))
    try assertFloor(result, version: newerTargetVersion, name: "Original Target")
  }

  /// Natural-key discovery folds the same lattice: the min-id winner of a
  /// lookup-key collision ends at the participant-set minimum floor, in both
  /// arrival orders.
  func testNaturalKeyCollisionFoldsParticipantMinimum() throws {
    let targetVersion = "1800000000100_0000_1111222233334444"
    let run: (Bool) throws -> String = { targetFirst in
      let store = try SyncTestSupport.freshStore()
      return try store.writer.write { db in
        let envelopes = [
          try self.habitEnvelope(
            entityId: self.targetId, name: "Same Habit", version: targetVersion,
            createdAt: self.targetCreatedAt, updatedAt: self.targetCreatedAt),
          try self.habitEnvelope(
            entityId: self.sourceId, name: "Same Habit", version: self.sourceVersion,
            createdAt: self.sourceCreatedAt, updatedAt: "2026-07-03T00:00:00.000Z"),
        ]
        for envelope in targetFirst ? envelopes : envelopes.reversed() {
          _ = try Apply.applyEnvelope(db, registry: self.registry, envelope: envelope)
        }
        return try self.snapshot(db)
      }
    }
    let targetFirst = try run(true)
    let sourceFirst = try run(false)
    XCTAssertEqual(targetFirst, sourceFirst)
    guard case .object(let payload)? = JSONValue.parse(targetFirst) else {
      return XCTFail("habit payload must be an object")
    }
    XCTAssertEqual(payload["created_at"], .string(sourceCreatedAt))
  }
}
