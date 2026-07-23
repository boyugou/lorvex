import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

final class CalendarEventLocalIntentReplayTests: XCTestCase {
  private let eventID = "01966a3f-7c8b-7d4e-8f3a-00000000f101"
  private let deviceID = "local-replay-device"
  private let registry = EntityApplierRegistry(
    appliers: EntityApplierRegistry.defaultEntityAppliers())

  private final class LockedHlcHandle: HlcDominatingStateHandle, @unchecked Sendable {
    private let lock = NSLock()
    private let state: HlcState

    init() throws {
      state = try HlcState(deviceSuffix: "cccccccccccccccc")
    }

    func generate() -> Hlc {
      generate(dominating: nil)
    }

    func generate(dominating floor: Hlc?) -> Hlc {
      lock.lock()
      defer { lock.unlock() }
      if let floor {
        state.updateOnReceive(remote: floor, physicalMs: 2_000_000_000_000)
      }
      return state.generate(withPhysicalMs: 2_000_000_000_000)
    }
  }

  private func version(_ physical: UInt64, suffix: String = "1111222233334444") throws -> Hlc {
    try Hlc(physicalMs: physical, counter: 0, deviceSuffix: suffix)
  }

  private func calendarEnvelope(
    title: String, startTime: String,
    contentVersion: Hlc, topologyVersion: Hlc, rowVersion: Hlc,
    deviceID: String = "peer"
  ) throws -> SyncEnvelope {
    let partial = try SyncCanonicalize.canonicalizeJSON(
      .object([
        "title": .string(title),
        "description": .null,
        "location": .null,
        "url": .null,
        "color": .null,
        "event_type": .string("event"),
        "person_name": .null,
        "attendees": .null,
        "start_date": .string("2026-07-20"),
        "start_time": .string(startTime),
        "end_date": .string("2026-07-20"),
        "end_time": .string("18:00"),
        "all_day": .bool(false),
        "timezone": .string("America/Los_Angeles"),
        "recurrence": .null,
        "recurrence_generation": .null,
        "series_id": .null,
        "recurrence_instance_date": .null,
        "occurrence_state": .null,
        "content_version": .string(contentVersion.description),
        "recurrence_topology_version": .string(topologyVersion.description),
        "created_at": .string("2026-07-20T08:00:00.000Z"),
        "updated_at": .string("2026-07-20T12:00:00.000Z"),
        "version": .string(rowVersion.description),
      ]))
    return try SyncTestSupport.completeEnvelope(
      entityType: .calendarEvent, entityId: eventID, operation: .upsert,
      version: rowVersion, payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: partial, deviceId: deviceID)
  }

  private func payload(
    rowVersion: Hlc, contentVersion: Hlc?, topologyVersion: Hlc?,
    seriesID: String? = nil
  ) -> JSONValue {
    .object([
      "series_id": seriesID.map(JSONValue.string) ?? .null,
      "version": .string(rowVersion.description),
      "content_version": contentVersion.map { .string($0.description) } ?? .null,
      "recurrence_topology_version": topologyVersion.map { .string($0.description) } ?? .null,
    ])
  }

  private func outboxRow(_ db: Database) throws -> Row {
    try XCTUnwrap(
      try Row.fetchOne(
        db,
        sql: """
          SELECT payload, payload_schema_version, version, register_intent
          FROM sync_outbox
          WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
          """,
        arguments: [EntityName.calendarEvent, eventID]))
  }

  private func deleteEnvelope(version: Hlc) throws -> SyncEnvelope {
    SyncEnvelope(
      entityType: .calendarEvent, entityId: eventID,
      operation: .delete, version: version,
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: try SyncCanonicalize.canonicalizeJSON(
        .object(["version": .string(version.description)])),
      deviceId: "remote-delete-device")
  }

  private func assertCanonicalOutboxMatchesRow(
    _ db: Database, expectedIntent: CalendarEventRegisterIntent,
    file: StaticString = #filePath, line: UInt = #line
  ) throws {
    let row = try outboxRow(db)
    let canonical = try SyncCanonicalize.canonicalizeJSON(
      OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: EntityName.calendarEvent, entityId: eventID))
    XCTAssertEqual(row["payload"] as String, canonical, file: file, line: line)
    XCTAssertEqual(
      row["register_intent"] as Int64,
      expectedIntent.rawValue, file: file, line: line)
  }

  func testLocalMutationInferenceCoversEachRegisterCombinationAndDecisionRows() throws {
    let older = try version(1_800_000_000_100)
    let row = try version(1_800_000_000_200)

    XCTAssertEqual(
      CalendarEventRegisterIntent.inferredLocalMutation(
        from: payload(rowVersion: row, contentVersion: row, topologyVersion: older)),
      .content)
    XCTAssertEqual(
      CalendarEventRegisterIntent.inferredLocalMutation(
        from: payload(rowVersion: row, contentVersion: older, topologyVersion: row)),
      .topology)
    XCTAssertEqual(
      CalendarEventRegisterIntent.inferredLocalMutation(
        from: payload(rowVersion: row, contentVersion: row, topologyVersion: row)),
      .all)
    XCTAssertEqual(
      CalendarEventRegisterIntent.inferredLocalMutation(
        from: payload(rowVersion: row, contentVersion: older, topologyVersion: older)),
      [])
    XCTAssertEqual(
      CalendarEventRegisterIntent.inferredLocalMutation(
        from: payload(
          rowVersion: row, contentVersion: nil, topologyVersion: nil,
          seriesID: "01966a3f-7c8b-7d4e-8f3a-00000000f199")),
      [])
  }

  func testOrdinaryCoalesceUnionsTopologyIntoRetainedContentAndFenceStartsNewLineage() throws {
    let store = try SyncTestSupport.freshStore()
    let firstVersion = try version(1_800_000_000_100)
    let secondVersion = try version(1_800_000_000_200)
    let thirdVersion = try version(1_800_000_000_300)
    let first = try calendarEnvelope(
      title: "First", startTime: "09:00",
      contentVersion: firstVersion, topologyVersion: firstVersion,
      rowVersion: firstVersion, deviceID: deviceID)
    let second = try calendarEnvelope(
      title: "First", startTime: "10:00",
      contentVersion: firstVersion, topologyVersion: secondVersion,
      rowVersion: secondVersion, deviceID: deviceID)
    let third = try calendarEnvelope(
      title: "Third", startTime: "10:00",
      contentVersion: thirdVersion, topologyVersion: secondVersion,
      rowVersion: thirdVersion, deviceID: deviceID)

    try store.writer.write { db in
      _ = try Outbox.enqueueCoalesced(db, first, registerIntent: .calendar(.content))
      _ = try Outbox.enqueueCoalesced(db, second, registerIntent: .calendar(.topology))
      XCTAssertEqual(
        try Int64.fetchOne(db, sql: "SELECT register_intent FROM sync_outbox"),
        CalendarEventRegisterIntent.all.rawValue)

      try SyncCheckpoints.set(db, key: SyncCheckpoints.keyDatabaseInstanceId, value: "db-instance")
      _ = try CloudTraversalWitness.claimAccount(db, accountIdentifier: "account")
      _ = try AuthoritativeSnapshot.begin(
        db,
        boundary: try SyncTestSupport.cloudTraversalBoundary(
          accountIdentifier: "account", zoneIdentifier: "zone"),
        databaseInstanceId: "db-instance")
      XCTAssertEqual(
        try String.fetchOne(db, sql: "SELECT disposition FROM sync_outbox"),
        Outbox.Disposition.authoritativeAdoption.rawValue)

      _ = try Outbox.enqueueCoalesced(db, third, registerIntent: .calendar(.content))
      let replacement = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: "SELECT register_intent, disposition FROM sync_outbox"))
      XCTAssertEqual(
        replacement["register_intent"] as Int64,
        CalendarEventRegisterIntent.content.rawValue)
      XCTAssertNil(replacement["disposition"] as String?)
    }
  }

  func testCoalesceDropsIntentWhenSameClockRegisterBytesDiffer() throws {
    let store = try SyncTestSupport.freshStore()
    let registerVersion = try version(1_800_000_000_100)
    let replacementVersion = try version(1_800_000_000_200)
    let local = try calendarEnvelope(
      title: "Locally authored", startTime: "09:00",
      contentVersion: registerVersion, topologyVersion: registerVersion,
      rowVersion: registerVersion, deviceID: deviceID)
    let replacement = try calendarEnvelope(
      title: "Remote collision winner", startTime: "09:00",
      contentVersion: registerVersion, topologyVersion: registerVersion,
      rowVersion: replacementVersion)

    try store.writer.write { db in
      _ = try Outbox.enqueueCoalesced(db, local, registerIntent: .calendar(.content))
      _ = try Outbox.enqueueCoalesced(db, replacement)

      XCTAssertEqual(
        try Int64.fetchOne(db, sql: "SELECT register_intent FROM sync_outbox"), 0,
        "an equal group clock cannot retain provenance for different register bytes")
    }
  }

  func testConvergenceReemitDropsContentIntentAfterRemoteContentWins() throws {
    let store = try SyncTestSupport.freshStore()
    let localVersion = try version(1_800_000_000_100, suffix: "bbbbbbbbbbbbbbbb")
    let remoteContentVersion = try version(
      1_800_000_000_300, suffix: "aaaaaaaaaaaaaaaa")
    let remoteRowVersion = try version(1_800_000_000_400, suffix: "aaaaaaaaaaaaaaaa")
    let reemitVersion = try version(1_800_000_000_500, suffix: "cccccccccccccccc")
    let local = try calendarEnvelope(
      title: "Local content", startTime: "09:00",
      contentVersion: localVersion, topologyVersion: localVersion,
      rowVersion: localVersion, deviceID: deviceID)
    let remote = try calendarEnvelope(
      title: "Remote content winner", startTime: "09:00",
      contentVersion: remoteContentVersion, topologyVersion: localVersion,
      rowVersion: remoteRowVersion)

    try store.writer.write { db in
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: registry, envelope: local), .applied)
      _ = try Outbox.enqueueCoalesced(db, local, registerIntent: .calendar(.content))
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: registry, envelope: remote), .applied)
      XCTAssertEqual(
        try ConvergenceEmitter.enqueueCurrentSnapshot(
          db, entityType: EntityName.calendarEvent, entityId: eventID,
          mintVersion: { _ in reemitVersion.description }, deviceId: deviceID),
        .enqueued)

      let row = try outboxRow(db)
      XCTAssertEqual(row["register_intent"] as Int64, 0)
      let payload = try XCTUnwrap(JSONValue.parse(row["payload"] as String))
      guard case .object(let object) = payload else {
        return XCTFail("expected calendar-event object payload")
      }
      XCTAssertEqual(object["title"], .string("Remote content winner"))
    }
  }

  func testConvergenceReemitPreservesContentIntentAcrossRemoteTopologyWin() throws {
    let store = try SyncTestSupport.freshStore()
    let localVersion = try version(1_800_000_000_100, suffix: "bbbbbbbbbbbbbbbb")
    let remoteTopologyVersion = try version(
      1_800_000_000_300, suffix: "aaaaaaaaaaaaaaaa")
    let remoteRowVersion = try version(1_800_000_000_400, suffix: "aaaaaaaaaaaaaaaa")
    let reemitVersion = try version(1_800_000_000_500, suffix: "cccccccccccccccc")
    let local = try calendarEnvelope(
      title: "Local content", startTime: "09:00",
      contentVersion: localVersion, topologyVersion: localVersion,
      rowVersion: localVersion, deviceID: deviceID)
    let remote = try calendarEnvelope(
      title: "Local content", startTime: "14:00",
      contentVersion: localVersion, topologyVersion: remoteTopologyVersion,
      rowVersion: remoteRowVersion)

    try store.writer.write { db in
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: registry, envelope: local), .applied)
      _ = try Outbox.enqueueCoalesced(db, local, registerIntent: .calendar(.content))
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: registry, envelope: remote), .applied)
      XCTAssertEqual(
        try ConvergenceEmitter.enqueueCurrentSnapshot(
          db, entityType: EntityName.calendarEvent, entityId: eventID,
          mintVersion: { _ in reemitVersion.description }, deviceId: deviceID),
        .enqueued)

      let row = try outboxRow(db)
      XCTAssertEqual(
        row["register_intent"] as Int64,
        CalendarEventRegisterIntent.content.rawValue)
      let payload = try XCTUnwrap(JSONValue.parse(row["payload"] as String))
      guard case .object(let object) = payload else {
        return XCTFail("expected calendar-event object payload")
      }
      XCTAssertEqual(object["start_time"], .string("14:00"))
    }
  }

  func testConvergenceReemitPreservesTopologyIntentAcrossRemoteContentWin() throws {
    let store = try SyncTestSupport.freshStore()
    let localVersion = try version(1_800_000_000_100, suffix: "bbbbbbbbbbbbbbbb")
    let remoteContentVersion = try version(
      1_800_000_000_300, suffix: "aaaaaaaaaaaaaaaa")
    let remoteRowVersion = try version(1_800_000_000_400, suffix: "aaaaaaaaaaaaaaaa")
    let reemitVersion = try version(1_800_000_000_500, suffix: "cccccccccccccccc")
    let local = try calendarEnvelope(
      title: "Original content", startTime: "14:00",
      contentVersion: localVersion, topologyVersion: localVersion,
      rowVersion: localVersion, deviceID: deviceID)
    let remote = try calendarEnvelope(
      title: "Remote content winner", startTime: "14:00",
      contentVersion: remoteContentVersion, topologyVersion: localVersion,
      rowVersion: remoteRowVersion)

    try store.writer.write { db in
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: registry, envelope: local), .applied)
      _ = try Outbox.enqueueCoalesced(db, local, registerIntent: .calendar(.topology))
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: registry, envelope: remote), .applied)
      XCTAssertEqual(
        try ConvergenceEmitter.enqueueCurrentSnapshot(
          db, entityType: EntityName.calendarEvent, entityId: eventID,
          mintVersion: { _ in reemitVersion.description }, deviceId: deviceID),
        .enqueued)

      let row = try outboxRow(db)
      XCTAssertEqual(
        row["register_intent"] as Int64,
        CalendarEventRegisterIntent.topology.rawValue)
      let payload = try XCTUnwrap(JSONValue.parse(row["payload"] as String))
      guard case .object(let object) = payload else {
        return XCTFail("expected calendar-event object payload")
      }
      XCTAssertEqual(object["title"], .string("Remote content winner"))
    }
  }

  func testConvergenceReemitNeverClaimsLocalCalendarRegisterIntent() throws {
    let store = try SyncTestSupport.freshStore()
    let base = try version(1_800_000_000_100)
    let reemit = try version(1_800_000_000_200)
    let envelope = try calendarEnvelope(
      title: "Remote", startTime: "09:00",
      contentVersion: base, topologyVersion: base, rowVersion: base)

    try store.writer.write { db in
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: registry, envelope: envelope), .applied)
      XCTAssertEqual(
        try ConvergenceEmitter.enqueueCurrentSnapshot(
          db, entityType: EntityName.calendarEvent, entityId: eventID,
          mintVersion: { _ in reemit.description }, deviceId: deviceID),
        .enqueued)
      XCTAssertEqual(
        try Int64.fetchOne(db, sql: "SELECT register_intent FROM sync_outbox"), 0)
    }
  }

  func testAuthoritativeReplayDropsZeroBitNoOpWhenRemoteBaselineDeletedEvent() throws {
    let store = try SyncTestSupport.freshStore()
    let localVersion = try version(1_800_000_000_100, suffix: "bbbbbbbbbbbbbbbb")
    let deleteVersion = try version(1_800_000_000_500, suffix: "aaaaaaaaaaaaaaaa")
    let local = try calendarEnvelope(
      title: "Stale no-op snapshot", startTime: "09:00",
      contentVersion: localVersion, topologyVersion: localVersion,
      rowVersion: localVersion, deviceID: deviceID)

    try store.writer.write { db in
      XCTAssertEqual(
        try Apply.applyEnvelope(
          db, registry: registry, envelope: deleteEnvelope(version: deleteVersion)),
        .applied)
      var report = AuthoritativeSnapshotReport()
      try AuthoritativeSnapshot.replayPostSessionLocalIntents(
        db,
        intents: [
          AuthoritativeSnapshotLocalIntent(
            outboxID: nil, envelope: local, registerIntent: .none)
        ],
        registry: registry,
        hlc: HlcSession(handle: try LockedHlcHandle()),
        deviceId: deviceID, report: &report)

      XCTAssertNil(
        try String.fetchOne(
          db, sql: "SELECT id FROM calendar_events WHERE id = ?", arguments: [eventID]))
      XCTAssertEqual(
        try Tombstone.getTombstone(
          db, entityType: EntityName.calendarEvent, entityId: eventID)?.version,
        deleteVersion.description)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ? AND entity_id = ?",
          arguments: [EntityName.calendarEvent, eventID]),
        0)
      XCTAssertTrue(report.changedEntityTypes.isEmpty)
    }
  }

  func testAuthoritativeReplayDropsCapturedConvergenceReemitAfterRemoteDeletion() throws {
    let store = try SyncTestSupport.freshStore()
    let baseVersion = try version(1_800_000_000_100, suffix: "bbbbbbbbbbbbbbbb")
    let reemitVersion = try version(1_800_000_000_200, suffix: "bbbbbbbbbbbbbbbb")
    let deleteVersion = try version(1_800_000_000_500, suffix: "aaaaaaaaaaaaaaaa")
    let local = try calendarEnvelope(
      title: "Converged local snapshot", startTime: "09:00",
      contentVersion: baseVersion, topologyVersion: baseVersion,
      rowVersion: baseVersion, deviceID: deviceID)

    try store.writer.write { db in
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: registry, envelope: local), .applied)
      try SyncCheckpoints.set(db, key: SyncCheckpoints.keyDatabaseInstanceId, value: "db-instance")
      _ = try CloudTraversalWitness.claimAccount(db, accountIdentifier: "account")
      let session = try AuthoritativeSnapshot.begin(
        db,
        boundary: try SyncTestSupport.cloudTraversalBoundary(
          accountIdentifier: "account", zoneIdentifier: "zone"),
        databaseInstanceId: "db-instance")
      XCTAssertEqual(
        try ConvergenceEmitter.enqueueCurrentSnapshot(
          db, entityType: EntityName.calendarEvent, entityId: eventID,
          mintVersion: { _ in reemitVersion.description }, deviceId: deviceID),
        .enqueued)
      XCTAssertEqual(
        try Apply.applyEnvelope(
          db, registry: registry, envelope: deleteEnvelope(version: deleteVersion)),
        .applied)

      let captured = try AuthoritativeSnapshot.capturePostSessionLocalIntents(
        db, accountIdentifier: "account", outboxBoundaryId: session.outboxBoundaryId)
      XCTAssertEqual(captured.count, 1)
      XCTAssertEqual(captured[0].registerIntent, .none)
      try AuthoritativeSnapshot.discardCapturedIntentQueueRows(db, intents: captured)
      var report = AuthoritativeSnapshotReport()
      try AuthoritativeSnapshot.replayPostSessionLocalIntents(
        db, intents: captured, registry: registry,
        hlc: HlcSession(handle: try LockedHlcHandle()),
        deviceId: deviceID, report: &report)

      XCTAssertNil(
        try String.fetchOne(
          db, sql: "SELECT id FROM calendar_events WHERE id = ?", arguments: [eventID]))
      XCTAssertEqual(
        try Tombstone.getTombstone(
          db, entityType: EntityName.calendarEvent, entityId: eventID)?.version,
        deleteVersion.description)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ? AND entity_id = ?",
          arguments: [EntityName.calendarEvent, eventID]),
        0)
      XCTAssertTrue(report.changedEntityTypes.isEmpty)
    }
  }

  func testAuthoritativeReplayPromotesOnlyContentOverHigherRemoteClock() throws {
    let store = try SyncTestSupport.freshStore()
    let remoteTopology = try version(1_800_000_000_200, suffix: "aaaaaaaaaaaaaaaa")
    let localContent = try version(1_800_000_000_300, suffix: "bbbbbbbbbbbbbbbb")
    let remoteContent = try version(1_800_000_000_500, suffix: "aaaaaaaaaaaaaaaa")
    let staleLocalTopology = try version(1_800_000_000_600, suffix: "bbbbbbbbbbbbbbbb")
    let localRow = try version(1_800_000_000_700, suffix: "bbbbbbbbbbbbbbbb")
    let remoteRow = try version(1_800_000_000_800, suffix: "aaaaaaaaaaaaaaaa")
    let remote = try calendarEnvelope(
      title: "Remote title", startTime: "09:00",
      contentVersion: remoteContent, topologyVersion: remoteTopology,
      rowVersion: remoteRow)
    let local = try calendarEnvelope(
      title: "Local post-session title", startTime: "14:00",
      contentVersion: localContent, topologyVersion: staleLocalTopology,
      rowVersion: localRow, deviceID: deviceID)

    try store.writer.write { db in
      try SyncCheckpoints.set(db, key: SyncCheckpoints.keyDatabaseInstanceId, value: "db-instance")
      _ = try CloudTraversalWitness.claimAccount(db, accountIdentifier: "account")
      let session = try AuthoritativeSnapshot.begin(
        db,
        boundary: try SyncTestSupport.cloudTraversalBoundary(
          accountIdentifier: "account", zoneIdentifier: "zone"),
        databaseInstanceId: "db-instance")
      _ = try Outbox.enqueueCoalesced(
        db, local, registerIntent: .calendar(.content))
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: registry, envelope: remote), .applied)
      let captured = try AuthoritativeSnapshot.capturePostSessionLocalIntents(
        db, accountIdentifier: "account", outboxBoundaryId: session.outboxBoundaryId)
      XCTAssertEqual(captured.count, 1)
      XCTAssertEqual(captured[0].registerIntent, .calendar(.content))
      try AuthoritativeSnapshot.discardCapturedIntentQueueRows(db, intents: captured)
      var report = AuthoritativeSnapshotReport()
      try AuthoritativeSnapshot.replayPostSessionLocalIntents(
        db, intents: captured,
        registry: registry,
        hlc: HlcSession(handle: try LockedHlcHandle()),
        deviceId: deviceID, report: &report)

      let row = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT title, start_time, content_version,
                   recurrence_topology_version, version
            FROM calendar_events WHERE id = ?
            """,
          arguments: [eventID]))
      XCTAssertEqual(row["title"] as String, "Local post-session title")
      XCTAssertEqual(row["start_time"] as String, "09:00")
      XCTAssertEqual(row["recurrence_topology_version"] as String, remoteTopology.description)
      let promoted = try Hlc.parseCanonical(row["content_version"] as String)
      XCTAssertGreaterThan(promoted, remoteRow)
      XCTAssertEqual(row["version"] as String, promoted.description)
      XCTAssertEqual(report.changedEntityTypes, [.calendarEvent])
      try assertCanonicalOutboxMatchesRow(db, expectedIntent: .content)
    }
  }

  func testAuthoritativeReplayAppliesKnownRegisterThenReattachesFuturePayloadShadow() throws {
    let store = try SyncTestSupport.freshStore()
    let remoteContent = try version(1_800_000_000_300, suffix: "aaaaaaaaaaaaaaaa")
    let remoteTopology = try version(1_800_000_000_400, suffix: "aaaaaaaaaaaaaaaa")
    let remoteRow = try version(1_800_000_000_500, suffix: "aaaaaaaaaaaaaaaa")
    let localContent = try version(1_800_000_000_200, suffix: "bbbbbbbbbbbbbbbb")
    let localRow = try version(1_800_000_000_600, suffix: "bbbbbbbbbbbbbbbb")
    let remote = try calendarEnvelope(
      title: "Remote title", startTime: "09:00",
      contentVersion: remoteContent, topologyVersion: remoteTopology,
      rowVersion: remoteRow)
    let local = try calendarEnvelope(
      title: "Local content intent", startTime: "15:00",
      contentVersion: localContent, topologyVersion: localContent,
      rowVersion: localRow, deviceID: deviceID)

    try store.writer.write { db in
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: registry, envelope: remote), .applied)
      guard case .object(var futurePayload)? = JSONValue.parse(remote.payload) else {
        return XCTFail("expected object payload")
      }
      futurePayload["future_calendar_field"] = .string("preserve-me")
      try PayloadShadow.upsertShadow(
        db, entityType: EntityName.calendarEvent, entityID: eventID,
        baseVersion: remoteRow.description,
        payloadSchemaVersion: Int(LorvexVersion.payloadSchemaVersion + 1),
        rawPayloadJSON: try SyncCanonicalize.canonicalizeJSON(.object(futurePayload)),
        sourceDeviceID: "future-peer")

      var report = AuthoritativeSnapshotReport()
      try AuthoritativeSnapshot.replayPostSessionLocalIntents(
        db,
        intents: [
          AuthoritativeSnapshotLocalIntent(
            outboxID: nil, envelope: local, registerIntent: .calendar(.content))
        ],
        registry: registry,
        hlc: HlcSession(handle: try LockedHlcHandle()),
        deviceId: deviceID, report: &report)

      let canonical = try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: EntityName.calendarEvent, entityId: eventID)
      guard case .object(let canonicalObject) = canonical else {
        return XCTFail("expected canonical object payload")
      }
      XCTAssertEqual(canonicalObject["title"], .string("Local content intent"))
      XCTAssertEqual(canonicalObject["start_time"], .string("09:00"))
      let queued = try outboxRow(db)
      XCTAssertEqual(
        queued["payload_schema_version"] as Int,
        Int(LorvexVersion.payloadSchemaVersion + 1))
      XCTAssertEqual(
        queued["register_intent"] as Int64,
        CalendarEventRegisterIntent.content.rawValue)
      let queuedPayload = try XCTUnwrap(JSONValue.parse(queued["payload"] as String))
      guard case .object(let queuedObject) = queuedPayload else {
        return XCTFail("expected queued object payload")
      }
      XCTAssertEqual(queuedObject["future_calendar_field"], .string("preserve-me"))
      for (key, value) in canonicalObject {
        XCTAssertEqual(queuedObject[key], value, "queued known field drifted: \(key)")
      }
      let successorVersion = queued["version"] as String
      let shadow = try XCTUnwrap(
        PayloadShadow.getShadow(
          db, entityType: EntityName.calendarEvent, entityID: eventID))
      XCTAssertEqual(shadow.baseVersion, successorVersion)
      XCTAssertEqual(report.changedEntityTypes, [.calendarEvent])
    }
  }

  func testFutureRecordReplayPromotesOnlyTopologyOverHigherRemoteClock() throws {
    let store = try SyncTestSupport.freshStore()
    let remoteContent = try version(1_800_000_000_200, suffix: "aaaaaaaaaaaaaaaa")
    let localTopology = try version(1_800_000_000_300, suffix: "bbbbbbbbbbbbbbbb")
    let remoteTopology = try version(1_800_000_000_500, suffix: "aaaaaaaaaaaaaaaa")
    let staleLocalContent = try version(1_800_000_000_600, suffix: "bbbbbbbbbbbbbbbb")
    let localRow = try version(1_800_000_000_700, suffix: "bbbbbbbbbbbbbbbb")
    let remoteFloor = try version(1_800_000_000_900, suffix: "aaaaaaaaaaaaaaaa")
    let remote = try calendarEnvelope(
      title: "Remote title", startTime: "09:00",
      contentVersion: remoteContent, topologyVersion: remoteTopology,
      rowVersion: remoteFloor)
    let local = try calendarEnvelope(
      title: "Stale local title", startTime: "14:00",
      contentVersion: staleLocalContent, topologyVersion: localTopology,
      rowVersion: localRow, deviceID: deviceID)

    try store.writer.write { db in
      _ = try Outbox.enqueueCoalesced(
        db, local, registerIntent: .calendar(.topology))
      try FutureRecordHold.fenceExistingLocalIntent(
        db, entityType: EntityName.calendarEvent, entityId: eventID,
        heldVersion: remoteFloor.description)
      try db.execute(
        sql: """
          UPDATE sync_outbox SET future_record_resolution = ?
          WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
          """,
        arguments: [
          FutureRecordHold.Resolution.localAfterFuture.rawValue,
          EntityName.calendarEvent, eventID,
        ])
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: registry, envelope: remote), .applied)
      let replay = try XCTUnwrap(
        FutureRecordHold.reconcileTerminalEnvelope(
          db, envelope: remote, outcome: .applied))
      XCTAssertEqual(replay.registerIntent, .calendar(.topology))
      let state = try HlcState(deviceSuffix: "dddddddddddddddd")
      try FutureRecordHold.fulfillLocalIntentReplay(
        db, replay: replay,
        registry: registry,
        mintVersion: { floor in
          if let floor {
            state.updateOnReceive(remote: floor, physicalMs: 2_000_000_000_000)
          }
          return state.generate(withPhysicalMs: 2_000_000_000_000).description
        },
        deviceId: deviceID)

      let row = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT title, start_time, content_version,
                   recurrence_topology_version, version
            FROM calendar_events WHERE id = ?
            """,
          arguments: [eventID]))
      XCTAssertEqual(row["title"] as String, "Remote title")
      XCTAssertEqual(row["start_time"] as String, "14:00")
      XCTAssertEqual(row["content_version"] as String, remoteContent.description)
      let promoted = try Hlc.parseCanonical(row["recurrence_topology_version"] as String)
      XCTAssertGreaterThan(promoted, remoteFloor)
      XCTAssertEqual(row["version"] as String, promoted.description)
      try assertCanonicalOutboxMatchesRow(db, expectedIntent: .topology)
    }
  }

  func testFutureLwwGroupedMergeRestagesSurvivingLocalRegisterIntent() throws {
    let store = try SyncTestSupport.freshStore()
    let localVersion = try version(1_800_000_000_100, suffix: "bbbbbbbbbbbbbbbb")
    let remoteTopology = try version(1_800_000_000_300, suffix: "aaaaaaaaaaaaaaaa")
    let remoteRow = try version(1_800_000_000_400, suffix: "aaaaaaaaaaaaaaaa")
    let local = try calendarEnvelope(
      title: "Local content", startTime: "09:00",
      contentVersion: localVersion, topologyVersion: localVersion,
      rowVersion: localVersion, deviceID: deviceID)
    let remote = try calendarEnvelope(
      title: "Local content", startTime: "14:00",
      contentVersion: localVersion, topologyVersion: remoteTopology,
      rowVersion: remoteRow)

    try store.writer.write { db in
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: registry, envelope: local), .applied)
      _ = try Outbox.enqueueCoalesced(
        db, local, registerIntent: .calendar(.content))
      try FutureRecordHold.fenceExistingLocalIntent(
        db, entityType: EntityName.calendarEvent, entityId: eventID,
        heldVersion: remoteRow.description)

      let outcome = try Apply.applyEnvelope(db, registry: registry, envelope: remote)
      XCTAssertEqual(outcome, .applied)
      XCTAssertNil(
        try FutureRecordHold.reconcileTerminalEnvelope(
          db, envelope: remote, outcome: outcome))

      let row = try outboxRow(db)
      XCTAssertEqual(
        row["register_intent"] as Int64,
        CalendarEventRegisterIntent.content.rawValue)
      let queued = try XCTUnwrap(JSONValue.parse(row["payload"] as String))
      guard case .object(let object) = queued else {
        return XCTFail("expected calendar-event object payload")
      }
      XCTAssertEqual(object["title"], .string("Local content"))
      XCTAssertEqual(object["start_time"], .string("14:00"))
    }
  }
}
