import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

final class PayloadEvolutionConvergenceTests: XCTestCase {
  private let entityID = "2026-04-05"
  private let first = "1711234568000_0000_a111111111111111"
  private let legacy = "1711234568001_0000_a222222222222222"
  private let successor = "1711234568002_0000_a333333333333333"

  private var registry: EntityApplierRegistry {
    EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
  }

  private func envelope(
    version: String, schema: UInt32, futureContext: String? = nil
  ) throws -> SyncEnvelope {
    var object: [String: JSONValue] = [
      "blocks": .array([
        .object([
          "block_type": .string("buffer"), "start_minutes": .int(540), "end_minutes": .int(570),
          "calendar_event_id": .null, "event_source": .null, "task_id": .null,
          "title": .string("Buffer"),
        ])
      ]),
      "created_at": .string("2026-04-05T00:00:00Z"),
      "updated_at": .string("2026-04-05T00:00:00Z"),
    ]
    if let futureContext { object["future_context"] = .string(futureContext) }
    return try SyncTestSupport.completeEnvelope(
      entityType: .focusSchedule, entityId: entityID, operation: .upsert,
      version: try Hlc.parseCanonical(version), payloadSchemaVersion: schema,
      payload: try SyncCanonicalize.canonicalizeJSON(.object(object)),
      deviceId: "remote-device")
  }

  private func seedPreservedLegacyUpdate(_ db: Database) throws -> SyncEnvelope {
    let future = try envelope(
      version: first, schema: LorvexVersion.payloadSchemaVersion + 1,
      futureContext: "fleet-preserved")
    XCTAssertEqual(try Apply.applyEnvelope(db, registry: registry, envelope: future), .applied)
    let legacyEnvelope = try envelope(
      version: legacy, schema: LorvexVersion.payloadSchemaVersion)
    XCTAssertEqual(
      try Apply.applyEnvelope(db, registry: registry, envelope: legacyEnvelope), .applied)
    return legacyEnvelope
  }

  func testPreservedHigherSchemaShadowEmitsFullSuccessorAndFreshPeerRetainsIt() throws {
    let source = try SyncTestSupport.freshStore()
    var successorEnvelope: SyncEnvelope?
    try source.writer.write { db in
      let legacyEnvelope = try seedPreservedLegacyUpdate(db)
      let target = try XCTUnwrap(
        AbsencePreserveReemit.convergenceReemitTarget(db, envelope: legacyEnvelope))
      XCTAssertEqual(target.entityId, entityID)

      XCTAssertEqual(
        try ConvergenceEmitter.enqueueCurrentSnapshot(
          db, entityType: target.entityType, entityId: target.entityId,
          mintVersion: { floor in
            XCTAssertEqual(floor?.description, self.legacy)
            return self.successor
          },
          deviceId: "preserving-device"),
        .enqueued)

      let row = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT version, payload_schema_version, payload, device_id
            FROM sync_outbox
            WHERE entity_type = ? AND entity_id = ? AND operation = 'upsert'
            ORDER BY id DESC LIMIT 1
            """,
          arguments: [EntityName.focusSchedule, entityID]))
      let rowVersion: String = row["version"]
      let rowSchema: Int = row["payload_schema_version"]
      let rowPayload: String = row["payload"]
      let rowDevice: String = row["device_id"]
      XCTAssertEqual(rowVersion, successor)
      XCTAssertEqual(rowSchema, Int(LorvexVersion.payloadSchemaVersion + 1))
      guard case .object(let object)? = JSONValue.parse(rowPayload) else {
        return XCTFail("successor payload must be an object")
      }
      XCTAssertEqual(object["future_context"], .string("fleet-preserved"))
      XCTAssertNotNil(object["blocks"], "successor must carry the complete known aggregate")
      successorEnvelope = SyncEnvelope(
        entityType: .focusSchedule, entityId: entityID, operation: .upsert,
        version: try Hlc.parseCanonical(rowVersion), payloadSchemaVersion: UInt32(rowSchema),
        payload: rowPayload, deviceId: rowDevice)
    }

    let fresh = try SyncTestSupport.freshStore()
    try fresh.writer.write { db in
      let successorEnvelope = try XCTUnwrap(successorEnvelope)
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: registry, envelope: successorEnvelope), .applied)
      let shadow = try XCTUnwrap(
        PayloadShadow.getShadow(
          db, entityType: EntityName.focusSchedule, entityID: entityID))
      let known = try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: EntityName.focusSchedule, entityId: entityID)
      let reconstructed = try PayloadShadow.mergePayloadWithShadowAfterLookup(
        db, entityType: EntityName.focusSchedule, entityID: entityID,
        knownPayload: known, shadow: shadow)
      guard case .object(let object) = reconstructed else {
        return XCTFail("fresh peer reconstruction must be an object")
      }
      XCTAssertEqual(object["future_context"], .string("fleet-preserved"))
      XCTAssertEqual(shadow.baseVersion, successor)
    }
  }

  func testPendingReplaySurfacesSchemaEvolutionReemitObligation() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      let future = try envelope(
        version: first, schema: LorvexVersion.payloadSchemaVersion + 1,
        futureContext: "pending-preserved")
      XCTAssertEqual(try Apply.applyEnvelope(db, registry: registry, envelope: future), .applied)
      let legacyEnvelope = try envelope(
        version: legacy, schema: LorvexVersion.payloadSchemaVersion)
      try PendingInboxDrain.enqueuePending(
        db, envelope: legacyEnvelope, reason: "test replay",
        missingEntityType: nil, missingEntityID: nil)

      let summary = try PendingInboxDrain.drainPendingInbox(db, registry: registry)
      XCTAssertEqual(summary.replayed, 1)
      XCTAssertEqual(
        summary.absenceReemitTargets,
        [AbsenceReemitTarget(entityType: EntityName.focusSchedule, entityId: entityID)])
      XCTAssertEqual(
        try PayloadShadow.getShadow(
          db, entityType: EntityName.focusSchedule, entityID: entityID)?.baseVersion,
        legacy)
    }
  }

  func testPendingExactReplayRetainsEqualVersionFutureShadow() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      _ = try seedPreservedLegacyUpdate(db)
      let shadow = try XCTUnwrap(
        PayloadShadow.getShadow(
          db, entityType: EntityName.focusSchedule, entityID: entityID))
      let known = try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: EntityName.focusSchedule, entityId: entityID)
      let complete = try PayloadShadow.mergePayloadWithShadowAfterLookup(
        db, entityType: EntityName.focusSchedule, entityID: entityID,
        knownPayload: known, shadow: shadow)
      let replay = SyncEnvelope(
        entityType: .focusSchedule, entityId: entityID, operation: .upsert,
        version: try Hlc.parseCanonical(legacy),
        payloadSchemaVersion: try PayloadShadow.requireWirePayloadSchemaVersion(
          shadow, context: "pending exact-replay test"),
        payload: try SyncCanonicalize.canonicalizeJSON(complete),
        deviceId: "future-peer")
      try PendingInboxDrain.enqueuePending(
        db, envelope: replay, reason: "duplicate replay",
        missingEntityType: nil, missingEntityID: nil)

      let summary = try PendingInboxDrain.drainPendingInbox(db, registry: registry)

      XCTAssertEqual(summary.skipped, 1)
      XCTAssertEqual(try PendingInbox.countPending(db), 0)
      let retained = try XCTUnwrap(
        PayloadShadow.getShadow(
          db, entityType: EntityName.focusSchedule, entityID: entityID))
      XCTAssertEqual(retained.baseVersion, legacy)
      guard case .object(let object)? = JSONValue.parse(retained.rawPayloadJSON) else {
        return XCTFail("retained payload shadow must remain an object")
      }
      XCTAssertEqual(object["future_context"], .string("fleet-preserved"))
    }
  }

  func testIntroductionMapTargetsOnlyTheAffectedOlderSchemaEntity() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      let tagID = "01966a3f-7c8b-7d4e-8f3a-00000000e001"
      try db.execute(
        sql: """
          INSERT INTO tags (id, display_name, lookup_key, color, version, created_at, updated_at)
          VALUES (?, 'Pinned', 'pinned', '#abcdef', ?, '', '')
          """, arguments: [tagID, legacy])
      let envelope = SyncEnvelope(
        entityType: .tag, entityId: tagID, operation: .upsert,
        version: try Hlc.parseCanonical(legacy), payloadSchemaVersion: 1,
        payload: #"{"display_name":"Pinned"}"#, deviceId: "old-peer")
      let simulatedV2 = [
        SyncPayloadFieldIntroduction(entityType: .tag, fieldName: "color", introducedIn: 2)
      ]
      XCTAssertEqual(
        try AbsencePreserveReemit.schemaEvolutionReemitTarget(
          db, envelope: envelope, appliedEntityId: tagID, introductions: simulatedV2),
        AbsenceReemitTarget(entityType: EntityName.tag, entityId: tagID))
      XCTAssertNil(
        try AbsencePreserveReemit.schemaEvolutionReemitTarget(
          db, envelope: envelope, appliedEntityId: tagID, introductions: []))
    }
  }

  func testRedirectRemapPreservesTargetShadowAndSurfacesWinnerReemit() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      let targetID = "00000000-0000-7000-8000-000000000001"
      let sourceID = "ffffffff-ffff-7fff-8fff-ffffffffffff"
      let futurePayload = try SyncCanonicalize.canonicalizeJSON(
        .object([
          "color": .string("#abcdef"),
          "created_at": .string("2026-04-05T00:00:00.000Z"),
          "display_name": .string("Future tag"),
          "future_note": .string("remap-preserved"),
          "updated_at": .string("2026-04-05T00:00:00.000Z"),
        ]))
      let future = try SyncTestSupport.completeEnvelope(
        entityType: .tag, entityId: targetID, operation: .upsert,
        version: try Hlc.parseCanonical(first),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion + 1,
        payload: futurePayload, deviceId: "future-peer")
      XCTAssertEqual(try Apply.applyEnvelope(db, registry: registry, envelope: future), .applied)
      _ = try EntityRedirect.upsertAndEnqueue(
        db, sourceType: .tag, sourceId: sourceID, targetId: targetID,
        version: first, createdAt: "2026-04-05T00:00:00.000Z",
        deviceId: "local-device")

      let legacyPayload = try SyncCanonicalize.canonicalizeJSON(
        .object([
          "color": .string("#123456"),
          "created_at": .string("2026-04-05T00:00:00.000Z"),
          "display_name": .string("Legacy edit"),
          "updated_at": .string("2026-04-05T00:00:01.000Z"),
        ]))
      let legacyEnvelope = try SyncTestSupport.completeEnvelope(
        entityType: .tag, entityId: sourceID, operation: .upsert,
        version: try Hlc.parseCanonical(legacy),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: legacyPayload, deviceId: "legacy-peer")
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: registry, envelope: legacyEnvelope),
        .remapped(fromEntityId: sourceID, toEntityId: targetID))

      let target = try AbsencePreserveReemit.remappedMergeWinnerReemitTarget(
        db, envelope: legacyEnvelope, toEntityId: targetID)
      XCTAssertEqual(
        target, AbsenceReemitTarget(entityType: EntityName.tag, entityId: targetID))
      XCTAssertEqual(
        try PayloadShadow.getShadow(
          db, entityType: EntityName.tag, entityID: targetID)?.baseVersion,
        legacy)
    }
  }

  func testCrossIDCollisionInventoryMatchesEveryAggregateMergeEngine() {
    let engineEntityTypes = Set(
      [
        ApplyHabitMerge.merger,
        ApplyHabitReminderPolicyMerge.merger,
        ApplyMemoryMerge.merger,
        ApplyTagMerge.merger,
      ].compactMap { EntityKind.parse($0.entityName) })
    XCTAssertEqual(engineEntityTypes, SyncPayloadEvolution.crossIDCollisionEntityTypes)
  }

  func testUnadaptedEvolutionFailsClosedBeforeCrossIDCollisionMutation() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      let winnerID = "00000000-0000-7000-8000-000000000001"
      let incomingID = "ffffffff-ffff-7fff-8fff-ffffffffffff"
      try seedTagParticipant(
        db, id: winnerID, displayName: "Pinned", lookupKey: "pinned",
        color: "#abcdef", version: first)
      try seedTagParticipant(
        db, id: incomingID, displayName: "Pinned", lookupKey: "__staged__",
        color: nil, version: legacy)
      let simulatedV2 = [
        SyncPayloadFieldIntroduction(entityType: .tag, fieldName: "color", introducedIn: 2)
      ]

      XCTAssertThrowsError(
        try ApplyTagMerge.merger.mergeKnownDuplicate(
          db, rows: [(winnerID, first), (incomingID, legacy)],
          triggeringVersion: legacy, applyTs: "2026-04-05T00:00:00.000Z",
          evolutionIntroductions: simulatedV2, collisionEvolutionAdapters: [])
      ) { error in
        guard case ApplyError.deferForwardCompat(let reason) = error,
          case .aggregateInvariantBlocked(let entityType, _, let invariant) = reason
        else { return XCTFail("expected aggregate evolution hold, got \(error)") }
        XCTAssertEqual(entityType, .tag)
        XCTAssertTrue(invariant.contains("missing=[\"color\"]"))
      }

      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tags"), 2)
      XCTAssertEqual(
        try String.fetchOne(db, sql: "SELECT color FROM tags WHERE id = ?", arguments: [winnerID]),
        "#abcdef")
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_entity_redirects"), 0)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_tombstones"), 0)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox"), 0)
    }
  }

  func testExecutableAdapterPreservesEvolvedFieldAcrossDifferentIDs() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      let winnerID = "00000000-0000-7000-8000-000000000001"
      let incomingID = "ffffffff-ffff-7fff-8fff-ffffffffffff"
      try seedTagParticipant(
        db, id: winnerID, displayName: "Pinned", lookupKey: "pinned",
        color: "#abcdef", version: first)
      try seedTagParticipant(
        db, id: incomingID, displayName: "Legacy rename", lookupKey: "__staged__",
        color: nil, version: legacy)
      let simulatedV2 = [
        SyncPayloadFieldIntroduction(entityType: .tag, fieldName: "color", introducedIn: 2)
      ]
      let adapter = PayloadEvolutionCollisionAdapter(
        entityType: .tag, coveredFields: ["color"],
        preserveFields: { db, context in
          let preservedSource = try XCTUnwrap(
            context.participants.map(\.id).first { $0 != context.contentReferenceID })
          try db.execute(
            sql: "UPDATE tags SET color = (SELECT color FROM tags WHERE id = ?) WHERE id = ?",
            arguments: [preservedSource, context.contentReferenceID])
        })

      XCTAssertEqual(
        try ApplyTagMerge.merger.mergeKnownDuplicate(
          db, rows: [(winnerID, first), (incomingID, legacy)],
          triggeringVersion: legacy, applyTs: "2026-04-05T00:00:00.000Z",
          evolutionIntroductions: simulatedV2, collisionEvolutionAdapters: [adapter]),
        winnerID)

      let winner = try XCTUnwrap(
        try Row.fetchOne(
          db, sql: "SELECT display_name, color FROM tags WHERE id = ?", arguments: [winnerID]))
      XCTAssertEqual(winner["display_name"] as String, "Legacy rename")
      XCTAssertEqual(winner["color"] as String?, "#abcdef")
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tags"), 1)
      let outboxPayload = try XCTUnwrap(
        try String.fetchOne(
          db,
          sql: """
            SELECT payload FROM sync_outbox
             WHERE entity_type = 'tag' AND entity_id = ? AND operation = 'upsert'
             ORDER BY id DESC LIMIT 1
            """, arguments: [winnerID]))
      guard case .object(let object)? = JSONValue.parse(outboxPayload) else {
        return XCTFail("winner outbox payload must be an object")
      }
      XCTAssertEqual(object["color"], .string("#abcdef"))
    }
  }

  private func seedTagParticipant(
    _ db: Database, id: String, displayName: String, lookupKey: String,
    color: String?, version: String
  ) throws {
    try db.execute(
      sql: """
        INSERT INTO tags
          (id, display_name, lookup_key, color, version, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, '2026-04-05T00:00:00.000Z', '2026-04-05T00:00:00.000Z')
        """,
      arguments: [id, displayName, lookupKey, color, version])
  }
}
