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

  func testOrdinaryCoalesceUnionsTopologyIntoRetainedContent() throws {
    let store = try SyncTestSupport.freshStore()
    let firstVersion = try version(1_800_000_000_100)
    let secondVersion = try version(1_800_000_000_200)
    let first = try calendarEnvelope(
      title: "First", startTime: "09:00",
      contentVersion: firstVersion, topologyVersion: firstVersion,
      rowVersion: firstVersion, deviceID: deviceID)
    let second = try calendarEnvelope(
      title: "First", startTime: "10:00",
      contentVersion: firstVersion, topologyVersion: secondVersion,
      rowVersion: secondVersion, deviceID: deviceID)

    try store.writer.write { db in
      _ = try Outbox.enqueueCoalesced(db, first, registerIntent: .calendar(.content))
      _ = try Outbox.enqueueCoalesced(db, second, registerIntent: .calendar(.topology))
      XCTAssertEqual(
        try Int64.fetchOne(db, sql: "SELECT register_intent FROM sync_outbox"),
        CalendarEventRegisterIntent.all.rawValue)
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
      try FutureRecordHold.reconcileTerminalEnvelope(
        db, envelope: remote, outcome: outcome)

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
