import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Convergence probes for the independent calendar content/topology registers.
final class CalendarEventGroupedMergeTests: XCTestCase {
  private let eventId = "55555555-5555-7555-8555-555555555555"
  private let registry = EntityApplierRegistry(
    appliers: EntityApplierRegistry.defaultEntityAppliers())

  private let baseVersion = "1760000000100_0000_aaaaaaaaaaaaaaaa"
  private let contentEditVersion = "1760000000200_0000_aaaaaaaaaaaaaaaa"
  private let topologyEditVersion = "1760000000300_0000_bbbbbbbbbbbbbbbb"
  private let reemitVersion = "1760000000400_0000_cccccccccccccccc"
  private let localHighVersion = "1760000000500_0000_dddddddddddddddd"

  private func envelope(
    title: String, startTime: String, recurrence: String, generation: String,
    contentVersion: String, topologyVersion: String, rowVersion: String,
    createdAt: String = "2026-07-20T08:00:00.000Z",
    updatedAt: String = "2026-07-20T12:00:00.000Z"
  ) throws -> SyncEnvelope {
    let partial = try SyncCanonicalize.canonicalizeJSON(
      .object([
        "title": .string(title), "start_date": .string("2026-07-20"),
        "start_time": .string(startTime), "end_date": .null, "end_time": .null,
        "all_day": .bool(false), "recurrence": .string(recurrence),
        "recurrence_generation": .string(generation),
        "content_version": .string(contentVersion),
        "recurrence_topology_version": .string(topologyVersion),
        "created_at": .string(createdAt), "updated_at": .string(updatedAt),
      ]))
    return try SyncTestSupport.completeEnvelope(
      entityType: .calendarEvent, entityId: eventId, operation: .upsert,
      version: Hlc.parse(rowVersion), payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: partial, deviceId: "peer")
  }

  private func decisionEnvelope(
    state: CalendarOccurrenceState, title: String, rowVersion: String
  ) throws -> SyncEnvelope {
    let instanceDate = "2026-07-21"
    let decisionId = CalendarOccurrenceDecisionID.make(
      seriesId: eventId, recurrenceGeneration: baseVersion,
      recurrenceInstanceDate: instanceDate)
    let partial = try SyncCanonicalize.canonicalizeJSON(
      .object([
        "title": .string(title), "start_date": .string(instanceDate),
        "start_time": .string("09:00"), "all_day": .bool(false),
        "series_id": .string(eventId), "recurrence_instance_date": .string(instanceDate),
        "occurrence_state": .string(state.rawValue),
        "recurrence_generation": .string(baseVersion), "content_version": .null,
        "recurrence_topology_version": .null,
      ]))
    return try SyncTestSupport.completeEnvelope(
      entityType: .calendarEvent, entityId: decisionId, operation: .upsert,
      version: Hlc.parse(rowVersion), payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: partial, deviceId: "peer")
  }

  private func snapshot(_ db: Database, id: String? = nil) throws -> [String: String?] {
    let resolvedId = id ?? eventId
    let row = try XCTUnwrap(
      try Row.fetchOne(
        db,
        sql: """
          SELECT title, start_time, recurrence, recurrence_generation, content_version,
                 recurrence_topology_version, created_at, updated_at, version
            FROM calendar_events WHERE id = ?
          """,
        arguments: [resolvedId]))
    return [
      "title": row["title"], "start_time": row["start_time"],
      "recurrence": row["recurrence"], "recurrence_generation": row["recurrence_generation"],
      "content_version": row["content_version"],
      "recurrence_topology_version": row["recurrence_topology_version"],
      "created_at": row["created_at"], "updated_at": row["updated_at"],
      "version": row["version"],
    ]
  }

  private func canonicalSnapshot(_ db: Database) throws -> String {
    let value = try OutboxEnqueue.readEntityPayloadSnapshot(
      db, entityType: EntityName.calendarEvent, entityId: eventId)
    return try SyncCanonicalize.canonicalizeJSON(value)
  }

  func testOppositeArrivalOrdersJoinProductionShapedContentAndTopology() throws {
    // These are snapshots that real local writes can produce. The content edit
    // advances only content_version; the later topology edit advances only the
    // topology clock while carrying the old content register. Each row version
    // is the maximum of the clocks it transports.
    let contentNewer = try envelope(
      title: "Newest metadata", startTime: "09:00", recurrence: "{\"FREQ\":\"DAILY\"}",
      generation: baseVersion, contentVersion: contentEditVersion,
      topologyVersion: baseVersion, rowVersion: contentEditVersion,
      createdAt: "2026-07-20T09:00:00.000Z", updatedAt: "2026-07-20T10:00:00.000Z")
    let topologyNewer = try envelope(
      title: "Stale metadata", startTime: "11:30", recurrence: "{\"FREQ\":\"WEEKLY\"}",
      generation: topologyEditVersion, contentVersion: baseVersion,
      topologyVersion: topologyEditVersion, rowVersion: topologyEditVersion,
      createdAt: "2026-07-20T08:00:00.000Z", updatedAt: "2026-07-20T11:00:00.000Z")

    let left = try SyncTestSupport.freshStore()
    let right = try SyncTestSupport.freshStore()
    var leftTarget: AbsenceReemitTarget?
    var rightTarget: AbsenceReemitTarget?

    try left.writer.write { db in
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: self.registry, envelope: contentNewer), .applied)
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: self.registry, envelope: topologyNewer), .applied)
      leftTarget = try AbsencePreserveReemit.convergenceReemitTarget(
        db, envelope: topologyNewer)
    }
    try right.writer.write { db in
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: self.registry, envelope: topologyNewer), .applied)
      // Whole-row stale, independently newer content: the special gate must
      // admit it instead of returning an ordinary LWW skip.
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: self.registry, envelope: contentNewer), .applied)
      rightTarget = try AbsencePreserveReemit.convergenceReemitTarget(
        db, envelope: contentNewer)
    }

    let leftSnapshot = try left.writer.read { try self.snapshot($0) }
    let rightSnapshot = try right.writer.read { try self.snapshot($0) }
    XCTAssertEqual(leftSnapshot, rightSnapshot)
    XCTAssertEqual(
      try left.writer.read { try self.canonicalSnapshot($0) },
      try right.writer.read { try self.canonicalSnapshot($0) })
    XCTAssertEqual(leftSnapshot["title"]!, "Newest metadata")
    XCTAssertEqual(leftSnapshot["start_time"]!, "11:30")
    XCTAssertEqual(leftSnapshot["recurrence"]!, "{\"FREQ\":\"WEEKLY\",\"INTERVAL\":1}")
    XCTAssertEqual(leftSnapshot["recurrence_generation"]!, topologyEditVersion)
    XCTAssertEqual(leftSnapshot["content_version"]!, contentEditVersion)
    XCTAssertEqual(leftSnapshot["recurrence_topology_version"]!, topologyEditVersion)
    XCTAssertEqual(leftSnapshot["created_at"]!, "2026-07-20T08:00:00.000Z")
    XCTAssertEqual(leftSnapshot["updated_at"]!, "2026-07-20T11:00:00.000Z")
    XCTAssertEqual(leftSnapshot["version"]!, topologyEditVersion)
    let expected = AbsenceReemitTarget(entityType: EntityName.calendarEvent, entityId: eventId)
    XCTAssertEqual(leftTarget, expected)
    XCTAssertEqual(rightTarget, expected)
  }

  func testEqualRowAndRegisterHlcsStillUseDeterministicGroupJoins() throws {
    let sameVersion = "1760000000350_0000_eeeeeeeeeeeeeeee"
    let contentWinner = try envelope(
      title: "Zulu metadata", startTime: "09:00", recurrence: "{\"FREQ\":\"DAILY\"}",
      generation: sameVersion, contentVersion: sameVersion,
      topologyVersion: sameVersion, rowVersion: sameVersion)
    let topologyWinner = try envelope(
      title: "Alpha metadata", startTime: "11:30", recurrence: "{\"FREQ\":\"WEEKLY\"}",
      generation: sameVersion, contentVersion: sameVersion,
      topologyVersion: sameVersion, rowVersion: sameVersion)
    let left = try SyncTestSupport.freshStore()
    let right = try SyncTestSupport.freshStore()

    try left.writer.write { db in
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: self.registry, envelope: contentWinner), .applied)
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: self.registry, envelope: topologyWinner), .applied)
    }
    try right.writer.write { db in
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: self.registry, envelope: topologyWinner), .applied)
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: self.registry, envelope: contentWinner), .applied)
    }

    let leftSnapshot = try left.writer.read { try self.snapshot($0) }
    let rightSnapshot = try right.writer.read { try self.snapshot($0) }
    XCTAssertEqual(leftSnapshot, rightSnapshot)
    XCTAssertEqual(leftSnapshot["title"]!, "Zulu metadata")
    XCTAssertEqual(leftSnapshot["start_time"]!, "11:30")
    XCTAssertEqual(leftSnapshot["content_version"]!, sameVersion)
    XCTAssertEqual(leftSnapshot["recurrence_topology_version"]!, sameVersion)
  }

  func testConvergenceReemitAdvancesOnlyTransportVersion() throws {
    let content = try envelope(
      title: "New content", startTime: "09:00", recurrence: "{\"FREQ\":\"DAILY\"}",
      generation: baseVersion, contentVersion: contentEditVersion,
      topologyVersion: baseVersion, rowVersion: contentEditVersion)
    let topology = try envelope(
      title: "Old content", startTime: "11:30", recurrence: "{\"FREQ\":\"WEEKLY\"}",
      generation: topologyEditVersion, contentVersion: baseVersion,
      topologyVersion: topologyEditVersion, rowVersion: topologyEditVersion)
    let source = try SyncTestSupport.freshStore()
    let peer = try SyncTestSupport.freshStore()

    try source.writer.write { db in
      XCTAssertEqual(try Apply.applyEnvelope(db, registry: registry, envelope: content), .applied)
      XCTAssertEqual(try Apply.applyEnvelope(db, registry: registry, envelope: topology), .applied)
      XCTAssertEqual(
        try ConvergenceEmitter.enqueueCurrentSnapshot(
          db, entityType: EntityName.calendarEvent, entityId: eventId,
          mintVersion: { _ in self.reemitVersion }, deviceId: "merge-device"),
        .enqueued)

      let after = try snapshot(db)
      XCTAssertEqual(after["content_version"]!, contentEditVersion)
      XCTAssertEqual(after["recurrence_topology_version"]!, topologyEditVersion)
      XCTAssertEqual(after["version"]!, reemitVersion)

      let outbox = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT payload, payload_schema_version, device_id
              FROM sync_outbox
             WHERE entity_type = ? AND entity_id = ? AND operation = 'upsert'
             ORDER BY id DESC LIMIT 1
            """,
          arguments: [EntityName.calendarEvent, eventId]))
      let payload: String = outbox["payload"]
      guard case .object(let object)? = JSONValue.parse(payload) else {
        return XCTFail("re-emit payload must be an object")
      }
      XCTAssertEqual(object["content_version"], .string(contentEditVersion))
      XCTAssertEqual(object["recurrence_topology_version"], .string(topologyEditVersion))

      let envelope = SyncEnvelope(
        entityType: .calendarEvent, entityId: eventId, operation: .upsert,
        version: try Hlc.parse(reemitVersion),
        payloadSchemaVersion: outbox["payload_schema_version"], payload: payload,
        deviceId: outbox["device_id"])
      try peer.writer.write { peerDb in
        XCTAssertEqual(
          try Apply.applyEnvelope(peerDb, registry: registry, envelope: envelope), .applied)
      }
    }

    let sourceSnapshot = try source.writer.read { try canonicalSnapshot($0) }
    let peerSnapshot = try peer.writer.read { try canonicalSnapshot($0) }
    XCTAssertEqual(peerSnapshot, sourceSnapshot)
  }

  func testAuthoritativeResetRebuildsBaseAndDecisionBelowLocalClocks() throws {
    let remoteBase = try envelope(
      title: "Authoritative base", startTime: "09:00", recurrence: "{\"FREQ\":\"DAILY\"}",
      generation: contentEditVersion, contentVersion: contentEditVersion,
      topologyVersion: contentEditVersion, rowVersion: contentEditVersion)
    let localBase = try envelope(
      title: "Superseded local base", startTime: "13:00",
      recurrence: "{\"FREQ\":\"WEEKLY\"}", generation: localHighVersion,
      contentVersion: localHighVersion, topologyVersion: localHighVersion,
      rowVersion: localHighVersion)
    let remoteDecision = try decisionEnvelope(
      state: .replacement, title: "Authoritative decision", rowVersion: contentEditVersion)
    let localDecision = try decisionEnvelope(
      state: .cancelled, title: "Superseded local decision", rowVersion: localHighVersion)
    let decisionId = remoteDecision.entityId
    let store = try SyncTestSupport.freshStore()

    try store.writer.write { db in
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: registry, envelope: localBase), .applied)
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: registry, envelope: localDecision), .applied)

      XCTAssertTrue(
        try ApplyLww.resetVersionForAuthoritativeSnapshot(
          db, entityType: EntityName.calendarEvent, entityId: eventId))
      XCTAssertTrue(
        try ApplyLww.resetVersionForAuthoritativeSnapshot(
          db, entityType: EntityName.calendarEvent, entityId: decisionId))
      XCTAssertNil(
        try String.fetchOne(
          db, sql: "SELECT id FROM calendar_events WHERE id = ?", arguments: [eventId]))
      XCTAssertNil(
        try String.fetchOne(
          db, sql: "SELECT id FROM calendar_events WHERE id = ?", arguments: [decisionId]))

      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: registry, envelope: remoteBase), .applied)
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: registry, envelope: remoteDecision), .applied)
      XCTAssertEqual(try snapshot(db)["title"]!, "Authoritative base")
      XCTAssertEqual(try snapshot(db, id: decisionId)["title"]!, "Authoritative decision")
    }
  }

  func testRegisterShapesAndClocksAreRejectedAtTheTypedBoundary() throws {
    let contentAboveRow = try envelope(
      title: "Invalid content", startTime: "09:00", recurrence: "{\"FREQ\":\"DAILY\"}",
      generation: baseVersion, contentVersion: topologyEditVersion,
      topologyVersion: baseVersion, rowVersion: contentEditVersion)
    let topologyAboveRow = try envelope(
      title: "Invalid topology", startTime: "09:00", recurrence: "{\"FREQ\":\"DAILY\"}",
      generation: baseVersion, contentVersion: baseVersion,
      topologyVersion: topologyEditVersion, rowVersion: contentEditVersion)
    let generationAboveRow = try envelope(
      title: "Invalid generation", startTime: "09:00", recurrence: "{\"FREQ\":\"DAILY\"}",
      generation: topologyEditVersion, contentVersion: baseVersion,
      topologyVersion: baseVersion, rowVersion: contentEditVersion)
    let decision = try decisionEnvelope(
      state: .replacement, title: "Invalid decision", rowVersion: contentEditVersion)
    guard case .object(var decisionObject)? = JSONValue.parse(decision.payload) else {
      return XCTFail("decision payload must be an object")
    }
    decisionObject["content_version"] = .string(baseVersion)
    let decisionWithContentClock = SyncEnvelope(
      entityType: decision.entityType, entityId: decision.entityId,
      operation: decision.operation, version: decision.version,
      payloadSchemaVersion: decision.payloadSchemaVersion,
      payload: try SyncCanonicalize.canonicalizeJSON(.object(decisionObject)),
      deviceId: decision.deviceId)
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      func assertInvalid(_ envelope: SyncEnvelope, contains expected: String) {
        XCTAssertThrowsError(
          try Apply.applyEnvelope(db, registry: registry, envelope: envelope)) { error in
          guard case ApplyError.invalidPayload(let message) = error else {
            return XCTFail("expected invalidPayload, got \(error)")
          }
          XCTAssertTrue(message.contains(expected), "unexpected reason: \(message)")
        }
      }
      assertInvalid(contentAboveRow, contains: "must not exceed row version")
      assertInvalid(topologyAboveRow, contains: "must not exceed row version")
      assertInvalid(generationAboveRow, contains: "recurrence_generation must not exceed")
      assertInvalid(decisionWithContentClock, contains: "cannot carry base register clocks")
    }
  }

  func testFutureSchemaBaseMergeHoldsUntilFieldGroupIsKnown() throws {
    let local = try envelope(
      title: "Local", startTime: "09:00", recurrence: "{\"FREQ\":\"DAILY\"}",
      generation: baseVersion, contentVersion: contentEditVersion,
      topologyVersion: baseVersion, rowVersion: contentEditVersion)
    let candidate = try envelope(
      title: "Future", startTime: "11:30", recurrence: "{\"FREQ\":\"WEEKLY\"}",
      generation: topologyEditVersion, contentVersion: baseVersion,
      topologyVersion: topologyEditVersion, rowVersion: topologyEditVersion)
    guard case .object(var object)? = JSONValue.parse(candidate.payload) else {
      return XCTFail("candidate payload must be an object")
    }
    object["future_calendar_field"] = .string("opaque")
    let future = SyncEnvelope(
      entityType: candidate.entityType, entityId: candidate.entityId,
      operation: candidate.operation, version: candidate.version,
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion + 1,
      payload: try SyncCanonicalize.canonicalizeJSON(.object(object)),
      deviceId: candidate.deviceId)

    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: self.registry, envelope: local), .applied)
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: self.registry, envelope: future),
        .deferred(
          reason: .schemaTooNew(
            remoteVersion: LorvexVersion.payloadSchemaVersion + 1,
            localVersion: LorvexVersion.payloadSchemaVersion)))
      XCTAssertEqual(try self.snapshot(db)["title"]!, "Local")
    }
  }
}
