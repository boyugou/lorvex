import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Equal HLCs normally mean exact replay. If cloned state or a broken writer
/// reuses one HLC for different semantic mutations, ordinary `>=` LWW lets each
/// device retain its own bytes forever. These tests pin the deterministic join
/// and strict-successor repair used by both inbound apply and push conflicts.
final class EqualHlcConvergenceTests: XCTestCase {
  private let entityId = "01966a3f-7c8b-7d4e-8f3a-00000000c011"
  private let collidedVersion = "1711234567890_0000_a1b2c3d4a1b2c3d4"
  private let successorVersion = "1711234567890_0001_a1b2c3d4a1b2c3d4"
  private let registry = EntityApplierRegistry(
    appliers: EntityApplierRegistry.defaultEntityAppliers())

  private func upsert(_ name: String, color: String) throws -> SyncEnvelope {
    let payload = try SyncCanonicalize.canonicalizeJSON(.object([
      "id": .string(entityId),
      "display_name": .string(name),
      "color": .string(color),
      "created_at": .string("2026-07-15T00:00:00.000Z"),
      "updated_at": .string("2026-07-15T00:00:00.000Z"),
      "version": .string(collidedVersion),
    ]))
    return SyncEnvelope(
      entityType: .tag, entityId: entityId, operation: .upsert,
      version: try Hlc.parseCanonical(collidedVersion),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: payload, deviceId: "cloned-device")
  }

  private func delete() throws -> SyncEnvelope {
    SyncEnvelope(
      entityType: .tag, entityId: entityId, operation: .delete,
      version: try Hlc.parseCanonical(collidedVersion),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: #"{"version":"1711234567890_0000_a1b2c3d4a1b2c3d4"}"#,
      deviceId: "cloned-device")
  }

  private func applySeed(_ envelope: SyncEnvelope, to db: Database) throws {
    XCTAssertEqual(
      try Apply.applyEnvelope(db, registry: registry, envelope: envelope), .applied)
  }

  private func applyCollisionAndRepair(
    _ envelope: SyncEnvelope, to db: Database
  ) throws {
    let result = try Apply.applyEnvelope(db, registry: registry, envelope: envelope)
    guard case .repairRequired(let obligation) = result else {
      XCTFail("equal-HLC semantic mismatch must surface a repair obligation: \(result)")
      return
    }
    try ApplyRepair.fulfill(
      db, obligation: obligation,
      mintVersion: { _ in self.successorVersion },
      deviceId: "repairing-clone")
  }

  private func pendingEnvelope(_ db: Database) throws -> SyncEnvelope {
    let pending = try Outbox.getPending(db)
    XCTAssertEqual(pending.count, 1)
    return try XCTUnwrap(pending.first?.envelope)
  }

  func testReverseArrivalOfTwoUpsertsConvergesWithSameClonedSuffix() throws {
    let alpha = try upsert("Alpha", color: "#111111")
    let beta = try upsert("Beta", color: "#222222")
    let storeAB = try SyncTestSupport.freshStore()
    let storeBA = try SyncTestSupport.freshStore()

    let stateAB = try storeAB.writer.write { db -> (String?, String?, String?, SyncEnvelope) in
      try applySeed(alpha, to: db)
      try applyCollisionAndRepair(beta, to: db)
      return (
        try String.fetchOne(db, sql: "SELECT display_name FROM tags WHERE id = ?", arguments: [entityId]),
        try String.fetchOne(db, sql: "SELECT color FROM tags WHERE id = ?", arguments: [entityId]),
        try String.fetchOne(db, sql: "SELECT version FROM tags WHERE id = ?", arguments: [entityId]),
        try pendingEnvelope(db))
    }
    let stateBA = try storeBA.writer.write { db -> (String?, String?, String?, SyncEnvelope) in
      try applySeed(beta, to: db)
      try applyCollisionAndRepair(alpha, to: db)
      return (
        try String.fetchOne(db, sql: "SELECT display_name FROM tags WHERE id = ?", arguments: [entityId]),
        try String.fetchOne(db, sql: "SELECT color FROM tags WHERE id = ?", arguments: [entityId]),
        try String.fetchOne(db, sql: "SELECT version FROM tags WHERE id = ?", arguments: [entityId]),
        try pendingEnvelope(db))
    }

    XCTAssertEqual(stateAB.0, stateBA.0)
    XCTAssertEqual(stateAB.1, stateBA.1)
    XCTAssertEqual(stateAB.2, successorVersion)
    XCTAssertEqual(stateAB.2, stateBA.2)
    XCTAssertEqual(
      try SyncMutationSemantics.key(for: stateAB.3),
      try SyncMutationSemantics.key(for: stateBA.3))
  }

  func testExactSemanticReplayIgnoresDeviceAndJsonKeyOrder() throws {
    let original = try upsert("Exact", color: "#123456")
    let reordered = SyncEnvelope(
      entityType: original.entityType, entityId: original.entityId,
      operation: original.operation, version: original.version,
      payloadSchemaVersion: original.payloadSchemaVersion,
      payload:
        ##"{"version":"1711234567890_0000_a1b2c3d4a1b2c3d4","updated_at":"2026-07-15T00:00:00.000Z","id":"01966a3f-7c8b-7d4e-8f3a-00000000c011","created_at":"2026-07-15T00:00:00.000Z","color":"#123456","display_name":"Exact"}"##,
      deviceId: "different-attribution")
    let store = try SyncTestSupport.freshStore()

    try store.writer.write { db in
      try applySeed(original, to: db)
      guard case .skipped = try Apply.applyEnvelope(
        db, registry: registry, envelope: reordered)
      else {
        XCTFail("semantic replay should be an idempotent skip")
        return
      }
      XCTAssertTrue(try Outbox.getPending(db).isEmpty)
    }
  }

  func testUpsertDeleteCollisionConvergesToOneSuccessorTombstone() throws {
    let upsert = try upsert("Delete me", color: "#abcdef")
    let delete = try delete()
    let storeUD = try SyncTestSupport.freshStore()
    let storeDU = try SyncTestSupport.freshStore()

    let stateUD = try storeUD.writer.write { db -> (String?, SyncEnvelope) in
      try applySeed(upsert, to: db)
      try applyCollisionAndRepair(delete, to: db)
      return (
        try Tombstone.getTombstone(db, entityType: EntityName.tag, entityId: entityId)?.version,
        try pendingEnvelope(db))
    }
    let stateDU = try storeDU.writer.write { db -> (String?, SyncEnvelope) in
      try applySeed(delete, to: db)
      try applyCollisionAndRepair(upsert, to: db)
      return (
        try Tombstone.getTombstone(db, entityType: EntityName.tag, entityId: entityId)?.version,
        try pendingEnvelope(db))
    }

    XCTAssertEqual(stateUD.0, successorVersion)
    XCTAssertEqual(stateUD.0, stateDU.0)
    XCTAssertEqual(stateUD.1.operation, .delete)
    XCTAssertEqual(
      try SyncMutationSemantics.key(for: stateUD.1),
      try SyncMutationSemantics.key(for: stateDU.1))
  }

  func testRedirectSlotRepairReenqueuesCanonicalRedirectAtSuccessor() throws {
    let store = try SyncTestSupport.freshStore()
    let sourceId = "ffffffff-ffff-7fff-8fff-ffffffffffff"
    let targetId = "00000000-0000-7000-8000-000000000001"

    try store.writer.write { db in
      try db.execute(
        sql: """
          INSERT INTO tags (
            id, display_name, lookup_key, version, created_at, updated_at
          ) VALUES (?, 'Target', 'target', ?,
                    '2026-07-15T00:00:00.000Z', '2026-07-15T00:00:00.000Z')
          """,
        arguments: [targetId, collidedVersion])
      let local = try EntityRedirect.upsertAndEnqueue(
        db, sourceType: .tag, sourceId: sourceId, targetId: targetId,
        version: collidedVersion, createdAt: "2026-07-15T00:00:00.000Z",
        deviceId: "cloned-device")
      let old = try XCTUnwrap(
        Outbox.getPending(db).first { $0.envelope.entityType == .entityRedirect })

      try ApplyRepair.fulfill(
        db,
        obligation: .resolveEqualVersionCollision(
          contender: try EntityRedirect.makeEnvelope(
            record: local, deviceId: "cloned-device"),
          additionalFloor: nil),
        mintVersion: { _ in self.successorVersion },
        deviceId: "repairing-clone")

      let repaired = try XCTUnwrap(
        Outbox.getPending(db).first { $0.envelope.entityType == .entityRedirect })
      XCTAssertNotEqual(repaired.id, old.id)
      XCTAssertEqual(repaired.envelope.version.description, successorVersion)
      XCTAssertEqual(
        try EntityRedirect.get(
          db, sourceType: EntityName.tag, sourceId: sourceId)?.version,
        successorVersion)
      XCTAssertEqual(
        try EntityRedirect.decodePayload(
          wireEntityId: repaired.envelope.entityId,
          payload: repaired.envelope.payload).targetId,
        targetId)
    }
  }
}
