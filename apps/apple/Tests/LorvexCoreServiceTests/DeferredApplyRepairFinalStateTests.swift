import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync
import XCTest

@testable import LorvexCore

/// Deferred apply repairs must publish the final canonical state after every
/// envelope and pending-inbox replay in the page has settled.
final class DeferredApplyRepairFinalStateTests: XCTestCase {
  private let eventId = "77777777-7777-4777-8777-777777777771"
  private let planDate = "2026-08-05"
  private let timestamp = "2026-08-05T12:00:00.000Z"
  private let v1 = "1760000010000_0001_1111111111111111"
  private let v2 = "1760000010100_0001_2222222222222222"
  private let v3 = "1760000010200_0001_3333333333333333"
  private let deviceId = "77777777-7777-4777-8777-777777777799"

  func testLaterValidScheduleWinsOverEarlierDeferredCalendarDeleteRepair() throws {
    let service = try makeService()
    let planDate = self.planDate
    XCTAssertEqual(
      try service.applyInbound([calendarDeleteEnvelope()], undecodable: 0).applied,
      1)

    _ = try service.applyInbound(
      [
        try scheduleEnvelope(version: v2, referencesDeletedEvent: true),
        try scheduleEnvelope(version: v3, referencesDeletedEvent: false),
      ],
      undecodable: 0)

    let state = try service.read { db in
      (
        title: try String.fetchOne(
          db,
          sql: "SELECT title FROM focus_schedule_blocks WHERE date = ?1",
          arguments: [planDate]),
        tombstone: try Tombstone.getTombstone(
          db, entityType: EntityName.focusSchedule, entityId: planDate)
      )
    }
    XCTAssertEqual(state.title, "Keep buffer")
    XCTAssertNil(state.tombstone)
    let outbound = try service.pendingOutbound().map(\.envelope).first {
      $0.entityType == .focusSchedule && $0.entityId == planDate
    }
    XCTAssertEqual(outbound?.operation, .upsert)
    XCTAssertTrue(outbound?.payload.contains("Keep buffer") == true)
    XCTAssertFalse(outbound?.payload.contains(eventId) == true)
  }

  func testLaterHigherPreferenceUpsertSupersedesEarlierEqualCollisionRepair() throws {
    let service = try makeService()
    let key = PreferenceKeys.prefSetupSummary
    XCTAssertEqual(
      try service.applyInbound(
        [try preferenceEnvelope(key: key, value: "base", version: v1)], undecodable: 0
      ).applied,
      1)

    _ = try service.applyInbound(
      [
        try preferenceEnvelope(key: key, value: "collision", version: v1),
        try preferenceEnvelope(key: key, value: "final", version: v2),
      ],
      undecodable: 0)

    let stored = try service.read { db in
      try String.fetchOne(
        db, sql: "SELECT value FROM preferences WHERE key = ?1", arguments: [key])
    }
    XCTAssertEqual(stored.flatMap(JSONValue.parse), .string("final"))
  }

  func testLaterHigherPreferenceDeleteSupersedesEarlierEqualCollisionRepair() throws {
    let service = try makeService()
    let key = PreferenceKeys.prefSetupSummary
    XCTAssertEqual(
      try service.applyInbound(
        [try preferenceEnvelope(key: key, value: "base", version: v1)], undecodable: 0
      ).applied,
      1)

    _ = try service.applyInbound(
      [
        try preferenceEnvelope(key: key, value: "collision", version: v1),
        preferenceDeleteEnvelope(key: key, version: v2),
      ],
      undecodable: 0)

    let state = try service.read { db in
      (
        value: try String.fetchOne(
          db, sql: "SELECT value FROM preferences WHERE key = ?1", arguments: [key]),
        tombstone: try Tombstone.getTombstone(
          db, entityType: EntityName.preference, entityId: key)
      )
    }
    XCTAssertNil(state.value)
    XCTAssertEqual(state.tombstone?.version, v2)
  }

  private func makeService() throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    return SwiftLorvexCoreService(store: try LorvexStore.openInMemory(schemaSQL: schemaSQL))
  }

  private func calendarDeleteEnvelope() -> SyncEnvelope {
    SyncEnvelope(
      entityType: .calendarEvent, entityId: eventId, operation: .delete,
      version: try! Hlc.parse(v1), payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: #"{"version":"1760000010000_0001_1111111111111111"}"#,
      deviceId: deviceId)
  }

  private func scheduleEnvelope(
    version: String, referencesDeletedEvent: Bool
  ) throws -> SyncEnvelope {
    let block: JSONValue =
      referencesDeletedEvent
      ? .object([
        "block_type": .string("event"), "start_minutes": .int(540),
        "end_minutes": .int(600), "task_id": .null,
        "calendar_event_id": .string(eventId), "event_source": .string("canonical"),
        "title": .string("Deleted event"),
      ])
      : .object([
        "block_type": .string("buffer"), "start_minutes": .int(600),
        "end_minutes": .int(630), "task_id": .null, "calendar_event_id": .null,
        "event_source": .null, "title": .string("Keep buffer"),
      ])
    return try CurrentSyncEnvelopeTestSupport.complete(
      SyncEnvelope(
        entityType: .focusSchedule, entityId: planDate, operation: .upsert,
        version: try Hlc.parse(version),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: try SyncCanonicalize.canonicalizeJSON(
          .object([
            "date": .string(planDate), "rationale": .string("Plan"),
            "timezone": .string("UTC"), "blocks": .array([block]),
            "created_at": .string(timestamp), "updated_at": .string(timestamp),
          ])),
        deviceId: deviceId))
  }

  private func preferenceEnvelope(
    key: String, value: String, version: String
  ) throws -> SyncEnvelope {
    try CurrentSyncEnvelopeTestSupport.complete(
      SyncEnvelope(
        entityType: .preference, entityId: key, operation: .upsert,
        version: try Hlc.parse(version),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: try SyncCanonicalize.canonicalizeJSON(
          .object([
            "key": .string(key), "value": .string(value),
            "updated_at": .string(timestamp),
          ])),
        deviceId: deviceId))
  }

  private func preferenceDeleteEnvelope(key: String, version: String) -> SyncEnvelope {
    SyncEnvelope(
      entityType: .preference, entityId: key, operation: .delete,
      version: try! Hlc.parse(version), payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: "{\"version\":\"\(version)\"}", deviceId: deviceId)
  }
}
