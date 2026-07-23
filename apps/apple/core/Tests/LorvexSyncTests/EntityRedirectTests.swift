import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

final class EntityRedirectTests: XCTestCase {
  private let registry = EntityApplierRegistry(
    appliers: EntityApplierRegistry.defaultEntityAppliers())
  private let target = "00000000-0000-7000-8000-000000000001"
  private let midA = "22222222-2222-7222-8222-222222222222"
  private let midB = "77777777-7777-7777-8777-777777777777"
  private let source = "ffffffff-ffff-7fff-8fff-ffffffffffff"

  private func version(_ physical: UInt64, counter: UInt32 = 0) throws -> Hlc {
    try Hlc(
      physicalMs: physical, counter: counter,
      deviceSuffix: "1111222233334444")
  }

  private func withDB(_ body: (Database) throws -> Void) throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in try body(db) }
  }

  private func insertTag(
    _ db: Database, id: String, name: String, version: String
  ) throws {
    try db.execute(
      sql: """
        INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at)
        VALUES (?, ?, ?, ?, '2026-07-15T00:00:00.000Z', '2026-07-15T00:00:00.000Z')
        """,
      arguments: [id, name, normalizeLookupKey(name), version])
  }

  private func envelope(
    sourceType: EntityKind = .tag, sourceId: String, targetId: String, version: Hlc
  ) throws -> SyncEnvelope {
    try EntityRedirect.makeEnvelope(
      record: EntityRedirect.Record(
        sourceType: sourceType, sourceId: sourceId, targetId: targetId,
        version: version.description, createdAt: "2026-07-15T00:00:00.000Z"),
      deviceId: "remote-device")
  }

  func testMissingTargetDefersWithoutLedgerTombstoneOrOutboxSideEffects() throws {
    try withDB { db in
      let incoming = try self.envelope(
        sourceId: self.source, targetId: self.target,
        version: try self.version(1_800_000_000_100))
      let result = try Apply.applyEnvelope(
        db, registry: self.registry, envelope: incoming)
      guard case .deferred(.missingDependency(.tag, self.target)) = result else {
        return XCTFail("expected target dependency defer, got \(result)")
      }
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_entity_redirects"), 0)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_tombstones"), 0)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox"), 0)
    }
  }

  func testNextGenerationAliasIsHeldWholeWithoutSideEffects() throws {
    try withDB { db in
      try self.insertTag(
        db, id: self.target, name: "Target",
        version: try self.version(1_800_000_000_050).description)
      var incoming = try self.envelope(
        sourceId: self.source, targetId: self.target,
        version: try self.version(1_800_000_000_100))
      incoming.payloadSchemaVersion = LorvexVersion.payloadSchemaVersion + 1

      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: self.registry, envelope: incoming),
        .deferred(
          reason: .schemaTooNew(
            remoteVersion: incoming.payloadSchemaVersion,
            localVersion: LorvexVersion.payloadSchemaVersion)))
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_entity_redirects"), 0)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_tombstones"), 0)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox"), 0)
    }
  }

  func testAliasFirstLiveMergeDefersWhileSourceHasOpaqueFutureShadow() throws {
    try withDB { db in
      let targetVersion = try self.version(1_800_000_000_100)
      let sourceVersion = try self.version(1_800_000_000_200)
      let aliasVersion = try self.version(1_800_000_000_300)
      try self.insertTag(
        db, id: self.target, name: "Target", version: targetVersion.description)
      try self.insertTag(
        db, id: self.source, name: "Source", version: sourceVersion.description)
      try PayloadShadow.upsertShadow(
        db, entityType: EntityName.tag, entityID: self.source,
        baseVersion: sourceVersion.description,
        payloadSchemaVersion: Int(LorvexVersion.payloadSchemaVersion + 1),
        rawPayloadJSON: try SyncCanonicalize.canonicalizeJSON(
          .object([
            "color": .string("#123456"),
            "display_name": .string("Source"),
            "future_note": .string("preserve-source-content"),
            "version": .string(sourceVersion.description),
          ])),
        sourceDeviceID: "future-peer")

      let result = try Apply.applyEnvelope(
        db, registry: self.registry,
        envelope: try self.envelope(
          sourceId: self.source, targetId: self.target, version: aliasVersion))
      guard case .deferred(
        .aggregateInvariantBlocked(
          entityType: .tag,
          entityId: self.target,
          invariant: "opaque future payload fields require a schema-aware cross-id merge")) = result
      else {
        return XCTFail("expected opaque-shadow collision defer, got \(result)")
      }

      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_entity_redirects"), 0)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox"), 0)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tags"), 2)
      XCTAssertNil(
        try PayloadShadow.getShadow(
          db, entityType: EntityName.tag, entityID: self.target))
      let sourceShadow = try XCTUnwrap(
        try PayloadShadow.getShadow(
          db, entityType: EntityName.tag, entityID: self.source))
      XCTAssertEqual(sourceShadow.payloadSchemaVersion, Int(LorvexVersion.payloadSchemaVersion + 1))
      guard case .object(let shadowObject)? = JSONValue.parse(sourceShadow.rawPayloadJSON) else {
        return XCTFail("source shadow must remain an object")
      }
      XCTAssertEqual(shadowObject["future_note"], .string("preserve-source-content"))
    }
  }

  func testPendingAliasReplaysWhenItsTargetTombstoneArrivesOnALaterPage() throws {
    try withDB { db in
      let incoming = try self.envelope(
        sourceId: self.source, targetId: self.target,
        version: try self.version(1_800_000_000_100))
      let reason = DeferralReason.missingDependency(
        entityType: .tag, entityId: self.target)
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: self.registry, envelope: incoming),
        .deferred(reason: reason))
      try PendingInboxDrain.enqueueDeferred(db, envelope: incoming, reason: reason)

      try Tombstone.createTombstone(
        db, entityType: EntityName.tag, entityId: self.target,
        version: try self.version(1_800_000_000_200).description,
        deletedAt: "2026-07-15T00:00:00.000Z")
      let summary = try PendingInboxDrain.drainPendingInbox(
        db, registry: self.registry)

      XCTAssertEqual(summary.replayed, 1)
      XCTAssertEqual(try PendingInbox.getAllPending(db).count, 0)
      XCTAssertEqual(
        try EntityRedirect.get(
          db, sourceType: EntityName.tag, sourceId: self.source)?.targetId,
        self.target)
      XCTAssertNotNil(
        try Tombstone.getTombstone(
          db, entityType: EntityName.tag, entityId: self.source))
    }
  }

  func testUnsupportedKnownSourceTypeIsRejectedWithoutSideEffects() throws {
    try withDB { db in
      let v = try self.version(1_800_000_000_100)
      let payload = try SyncCanonicalize.canonicalizeJSON(
        .object([
          "source_type": .string(EntityName.list),
          "source_id": .string(self.source),
          "target_id": .string(self.target),
          "version": .string(v.description),
        ]))
      let incoming = SyncEnvelope(
        entityType: .entityRedirect,
        entityId: EntityRedirect.wireEntityId(sourceType: .list, sourceId: self.source),
        operation: .upsert, version: v,
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: payload, deviceId: "remote-device")

      XCTAssertThrowsError(
        try Apply.applyEnvelope(db, registry: self.registry, envelope: incoming)
      ) { error in
        guard case .invalidPayload = error as? ApplyError else {
          return XCTFail("expected invalidPayload, got \(error)")
        }
      }
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_entity_redirects"), 0)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_tombstones"), 0)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox"), 0)
    }
  }

  func testSelfAndAscendingAliasesAreRejectedWithoutSideEffects() throws {
    try withDB { db in
      let v = try self.version(1_800_000_000_100)
      for (sourceID, targetID) in [
        (self.target, self.target),
        (self.target, self.source),
      ] {
        let payload = try SyncCanonicalize.canonicalizeJSON(
          .object([
            "source_type": .string(EntityName.tag),
            "source_id": .string(sourceID),
            "target_id": .string(targetID),
            "version": .string(v.description),
          ]))
        let incoming = SyncEnvelope(
          entityType: .entityRedirect,
          entityId: EntityRedirect.wireEntityId(sourceType: .tag, sourceId: sourceID),
          operation: .upsert, version: v,
          payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
          payload: payload, deviceId: "remote-device")
        XCTAssertThrowsError(
          try Apply.applyEnvelope(db, registry: self.registry, envelope: incoming))
      }
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_entity_redirects"), 0)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_tombstones"), 0)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox"), 0)
    }
  }

  func testRedirectDeleteOperationIsRejectedWithoutSideEffects() throws {
    try withDB { db in
      let upsert = try self.envelope(
        sourceId: self.source, targetId: self.target,
        version: try self.version(1_800_000_000_100))
      let delete = SyncEnvelope(
        entityType: upsert.entityType, entityId: upsert.entityId,
        operation: .delete, version: upsert.version,
        payloadSchemaVersion: upsert.payloadSchemaVersion,
        payload: upsert.payload, deviceId: upsert.deviceId)
      XCTAssertThrowsError(
        try Apply.applyEnvelope(db, registry: self.registry, envelope: delete)
      ) { error in
        guard case .invalidPayload(let message) = error as? ApplyError else {
          return XCTFail("expected invalidPayload, got \(error)")
        }
        XCTAssertTrue(message.contains("delete is not supported for entity_redirect"))
      }
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_entity_redirects"), 0)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_tombstones"), 0)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox"), 0)
    }
  }

  func testSequentialAliasesCompressEveryPredecessorAndEmitDominatingCorrections() throws {
    try withDB { db in
      let v1 = try self.version(1_800_000_000_100)
      let v2 = try self.version(1_800_000_000_200)
      let v3 = try self.version(1_800_000_000_300)
      let device = "00000000-0000-7000-8000-000000000001"
      _ = try EntityRedirect.upsertAndEnqueue(
        db, sourceType: .tag, sourceId: self.source, targetId: self.midB,
        version: v1.description, createdAt: "2026-07-15T00:00:00.000Z", deviceId: device)
      _ = try EntityRedirect.upsertAndEnqueue(
        db, sourceType: .tag, sourceId: self.midB, targetId: self.midA,
        version: v2.description, createdAt: "2026-07-15T00:00:00.000Z", deviceId: device)
      _ = try EntityRedirect.upsertAndEnqueue(
        db, sourceType: .tag, sourceId: self.midA, targetId: self.target,
        version: v3.description, createdAt: "2026-07-15T00:00:00.000Z", deviceId: device)

      for id in [self.midA, self.midB, self.source] {
        let redirect = try XCTUnwrap(
          try EntityRedirect.get(db, sourceType: EntityName.tag, sourceId: id))
        XCTAssertEqual(redirect.targetId, self.target)
        let chase = try ApplyRedirect.chaseRedirectChain(
          db, initialEntityType: EntityName.tag, initialEntityId: id)
        XCTAssertEqual(chase.finalId, self.target)
        XCTAssertEqual(chase.hops.count, 1)
      }
      XCTAssertGreaterThan(
        try Hlc.parse(
          try XCTUnwrap(
            EntityRedirect.get(db, sourceType: EntityName.tag, sourceId: self.source)?.version)),
        v3)
      XCTAssertGreaterThan(
        try Hlc.parse(
          try XCTUnwrap(
            EntityRedirect.get(db, sourceType: EntityName.tag, sourceId: self.midB)?.version)),
        v3)

      let queued = try Row.fetchAll(
        db,
        sql: """
          SELECT entity_id, version, payload FROM sync_outbox
          WHERE entity_type = ? AND synced_at IS NULL
          ORDER BY entity_id
          """,
        arguments: [EntityName.entityRedirect])
      XCTAssertEqual(queued.count, 3)
      for row in queued {
        guard case .object(let payload)? = JSONValue.parse(row["payload"]) else {
          return XCTFail("redirect outbox payload was not an object")
        }
        XCTAssertEqual(payload["target_id"], .string(self.target))
      }
    }
  }

  func testCompetingTargetsUnionTheirLiveComponentsInEitherArrivalOrder() throws {
    struct Snapshot: Equatable {
      var liveIds: [String]
      var sourceTarget: String?
      var displacedTarget: String?
    }

    let run: (Bool) throws -> Snapshot = { smallerTargetFirst in
      var snapshot: Snapshot?
      try self.withDB { db in
        let base = try self.version(1_800_000_000_050)
        try self.insertTag(db, id: self.target, name: "A", version: base.description)
        try self.insertTag(db, id: self.midA, name: "B", version: base.description)
        try self.insertTag(db, id: self.source, name: "S", version: base.description)
        let smaller = try self.envelope(
          sourceId: self.source, targetId: self.target,
          version: try self.version(1_800_000_000_100))
        let larger = try self.envelope(
          sourceId: self.source, targetId: self.midA,
          version: try self.version(1_800_000_000_200))
        for alias in smallerTargetFirst ? [smaller, larger] : [larger, smaller] {
          XCTAssertEqual(
            try Apply.applyEnvelope(db, registry: self.registry, envelope: alias),
            .applied)
        }

        snapshot = Snapshot(
          liveIds: try String.fetchAll(db, sql: "SELECT id FROM tags ORDER BY id"),
          sourceTarget: try EntityRedirect.get(
            db, sourceType: EntityName.tag, sourceId: self.source)?.targetId,
          displacedTarget: try EntityRedirect.get(
            db, sourceType: EntityName.tag, sourceId: self.midA)?.targetId)
      }
      return try XCTUnwrap(snapshot)
    }

    let smallerFirst = try run(true)
    let largerFirst = try run(false)
    let expected = Snapshot(
      liveIds: [target], sourceTarget: target, displacedTarget: target)
    XCTAssertEqual(smallerFirst, expected)
    XCTAssertEqual(largerFirst, expected)
  }

  func testLocalProducerAlsoUnionsAPreexistingCompetingTarget() throws {
    try withDB { db in
      let base = try self.version(1_800_000_000_050)
      let deviceId = "00000000-0000-7000-8000-000000000001"
      try self.insertTag(db, id: self.target, name: "A", version: base.description)
      try self.insertTag(db, id: self.midA, name: "B", version: base.description)
      _ = try EntityRedirect.upsertAndEnqueue(
        db, sourceType: .tag, sourceId: self.source, targetId: self.midA,
        version: try self.version(1_800_000_000_100).description,
        createdAt: "2026-07-15T00:00:00.000Z", deviceId: deviceId)
      try Tombstone.createTombstone(
        db, entityType: EntityName.tag, entityId: self.source,
        version: try self.version(1_800_000_000_100).description,
        deletedAt: "2026-07-15T00:00:00.000Z")

      _ = try EntityRedirect.upsertAndEnqueue(
        db, sourceType: .tag, sourceId: self.source, targetId: self.target,
        version: try self.version(1_800_000_000_200).description,
        createdAt: "2026-07-15T00:00:00.000Z", deviceId: deviceId)

      XCTAssertEqual(
        try String.fetchAll(db, sql: "SELECT id FROM tags ORDER BY id"),
        [self.target])
      XCTAssertEqual(
        try EntityRedirect.get(
          db, sourceType: EntityName.tag, sourceId: self.source)?.targetId,
        self.target)
      XCTAssertEqual(
        try EntityRedirect.get(
          db, sourceType: EntityName.tag, sourceId: self.midA)?.targetId,
        self.target)
    }
  }

  func testTombstonedTerminalTargetAcceptsAliasAndSuppressesLiveSource() throws {
    try withDB { db in
      let targetDeath = try self.version(1_800_000_000_200)
      let aliasVersion = try self.version(1_800_000_000_300)
      let sourceVersion = try self.version(1_800_000_000_400)
      try self.insertTag(
        db, id: self.source, name: "Source", version: sourceVersion.description)
      try Tombstone.createTombstone(
        db, entityType: EntityName.tag, entityId: self.target,
        version: targetDeath.description, deletedAt: "2026-07-15T00:00:00.000Z")

      let result = try Apply.applyEnvelope(
        db, registry: self.registry,
        envelope: try self.envelope(
          sourceId: self.source, targetId: self.target, version: aliasVersion))
      XCTAssertEqual(result, .applied)
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM tags WHERE id = ?", arguments: [self.source]),
        0)
      XCTAssertEqual(
        try EntityRedirect.get(
          db, sourceType: EntityName.tag, sourceId: self.source)?.targetId,
        self.target)
      let sourceDeath = try XCTUnwrap(
        try Tombstone.getTombstone(
          db, entityType: EntityName.tag, entityId: self.source))
      let finalTargetDeath = try XCTUnwrap(
        try Tombstone.getTombstone(
          db, entityType: EntityName.tag, entityId: self.target))
      XCTAssertGreaterThan(try Hlc.parse(sourceDeath.version), sourceVersion)
      XCTAssertEqual(sourceDeath.version, finalTargetDeath.version)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ? AND operation = 'delete'",
          arguments: [EntityName.tag]),
        2)
    }
  }

  func testTombstonedTargetAdvancesToPreexistingNewerSourceDeath() throws {
    try withDB { db in
      let targetDeath = try self.version(1_800_000_000_200)
      let aliasVersion = try self.version(1_800_000_000_300)
      let sourceDeath = try self.version(1_800_000_000_900)
      try Tombstone.createTombstone(
        db, entityType: EntityName.tag, entityId: self.target,
        version: targetDeath.description, deletedAt: "2026-07-15T00:00:00.000Z")
      try Tombstone.createTombstone(
        db, entityType: EntityName.tag, entityId: self.source,
        version: sourceDeath.description, deletedAt: "2026-07-15T00:00:00.000Z")

      XCTAssertEqual(
        try Apply.applyEnvelope(
          db, registry: self.registry,
          envelope: try self.envelope(
            sourceId: self.source, targetId: self.target, version: aliasVersion)),
        .applied)

      let finalTargetDeath = try XCTUnwrap(
        try Tombstone.getTombstone(
          db, entityType: EntityName.tag, entityId: self.target))
      XCTAssertEqual(finalTargetDeath.version, sourceDeath.description)
      XCTAssertEqual(
        try Tombstone.getTombstone(
          db, entityType: EntityName.tag, entityId: self.source)?.version,
        sourceDeath.description)
      let deleteVersions = try String.fetchAll(
        db,
        sql: """
          SELECT version FROM sync_outbox
          WHERE entity_type = 'tag' AND operation = 'delete'
          ORDER BY entity_id
          """)
      XCTAssertEqual(deleteVersions, [sourceDeath.description, sourceDeath.description])
    }
  }

  func testLiveSourceAndTargetUseAggregateMergeAndPreserveMaxHlcContent() throws {
    try withDB { db in
      let targetVersion = try self.version(1_800_000_000_100)
      let sourceVersion = try self.version(1_800_000_000_400)
      let aliasVersion = try self.version(1_800_000_000_500)
      try self.insertTag(
        db, id: self.target, name: "shared", version: targetVersion.description)
      try self.insertTag(
        db, id: self.source, name: "Shared", version: sourceVersion.description)

      XCTAssertEqual(
        try Apply.applyEnvelope(
          db, registry: self.registry,
          envelope: try self.envelope(
            sourceId: self.source, targetId: self.target, version: aliasVersion)),
        .applied)
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT display_name FROM tags WHERE id = ?", arguments: [self.target]),
        "Shared")
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM tags WHERE id = ?", arguments: [self.source]),
        0)
      XCTAssertEqual(
        try EntityRedirect.get(
          db, sourceType: EntityName.tag, sourceId: self.source)?.targetId,
        self.target)
    }
  }

  func testDeleteAddressedToAliasSourceIsDroppedAndWinnerSurvives() throws {
    try withDB { db in
      let aliasVersion = try self.version(1_800_000_000_200)
      try self.insertTag(
        db, id: self.target, name: "Winner",
        version: try self.version(1_800_000_000_100).description)
      try SyncTestSupport.seedEntityRedirect(
        db, sourceType: .tag, sourceId: self.source, targetId: self.target,
        version: aliasVersion.description)
      let deleteVersion = try self.version(1_800_000_000_900)
      let delete = SyncEnvelope(
        entityType: .tag, entityId: self.source, operation: .delete,
        version: deleteVersion, payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: try SyncCanonicalize.canonicalizeJSON(
          .object(["version": .string(deleteVersion.description)])),
        deviceId: "remote-device")
      guard
        case .skipped = try Apply.applyEnvelope(
          db, registry: self.registry, envelope: delete)
      else { return XCTFail("alias-source delete should be dropped") }
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM tags WHERE id = ?", arguments: [self.target]),
        1)
      XCTAssertNotNil(
        try EntityRedirect.get(db, sourceType: EntityName.tag, sourceId: self.source))
    }
  }
}
