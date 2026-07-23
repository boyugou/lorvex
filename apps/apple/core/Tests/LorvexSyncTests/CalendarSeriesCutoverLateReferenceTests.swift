import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Arrival-order probes for synced aggregates that can reference calendar
/// events after a permanent segment boundary has already been deleted.
final class CalendarSeriesCutoverLateReferenceTests: XCTestCase {
  private let rootID = "11111111-1111-4111-8111-111111111111"
  private let taskID = "33333333-3333-4333-8333-333333333333"
  private let timestamp = "2026-07-17T00:00:00.000Z"
  private let deviceID = "calendar-cutover-late-reference-test"
  private let v1 = "1760000000000_0001_1111111111111111"
  private let v2 = "1760000000100_0001_2222222222222222"
  private let v3 = "1760000000200_0001_3333333333333333"
  private let v4 = "1760000000300_0001_4444444444444444"
  private let v5 = "1760000000400_0001_5555555555555555"

  private var registry: EntityApplierRegistry {
    EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
  }

  private func parsed(_ value: String) throws -> Hlc { try Hlc.parseCanonical(value) }

  private func cutoverID(_ date: String) -> String {
    CalendarSeriesCutoverID.make(lineageRootId: rootID, cutoverDate: date)
  }

  private func deletedCutover(_ date: String) throws -> SyncEnvelope {
    let id = cutoverID(date)
    let payload = try SyncCanonicalize.canonicalizeJSON(.object([
      "id": .string(id), "lineage_root_id": .string(rootID),
      "cutover_date": .string(date), "state": .string("deleted"),
      "created_at": .string(timestamp), "updated_at": .string(timestamp),
      "version": .string(v1),
    ]))
    return try SyncTestSupport.completeEnvelope(
      entityType: .calendarSeriesCutover, entityId: id, operation: .upsert,
      version: parsed(v1), payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: payload, deviceId: deviceID)
  }

  private func event(_ id: String, date: String) throws -> SyncEnvelope {
    let payload = try SyncCanonicalize.canonicalizeJSON(.object([
      "title": .string("Late private event"), "start_date": .string(date),
      "start_time": .string("09:00"), "end_date": .string(date),
      "end_time": .string("10:00"), "all_day": .bool(false),
      "timezone": .string("UTC"), "event_type": .string("event"),
      "series_cutover_id": .string(id), "series_id": .null,
      "recurrence_instance_date": .null, "occurrence_state": .null,
      "recurrence": .null, "recurrence_generation": .null,
      "recurrence_topology_version": .string(v3), "content_version": .string(v3),
      "created_at": .string(timestamp), "updated_at": .string(timestamp),
      "version": .string(v3),
    ]))
    return try SyncTestSupport.completeEnvelope(
      entityType: .calendarEvent, entityId: id, operation: .upsert,
      version: parsed(v3), payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: payload, deviceId: deviceID)
  }

  private func edge(_ eventID: String) throws -> SyncEnvelope {
    let id = "\(taskID):\(eventID)"
    let payload = try SyncCanonicalize.canonicalizeJSON(.object([
      "task_id": .string(taskID), "calendar_event_id": .string(eventID),
      "created_at": .string(timestamp), "updated_at": .string(timestamp),
      "version": .string(v2),
    ]))
    return try SyncTestSupport.completeEnvelope(
      entityType: .taskCalendarEventLink, entityId: id, operation: .upsert,
      version: parsed(v2), payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: payload, deviceId: deviceID)
  }

  private func schedule(
    date: String, version: String, eventID: String, retainBuffer: Bool
  ) throws -> SyncEnvelope {
    var blocks: [JSONValue] = [
      .object([
        "block_type": .string("event"), "start_minutes": .int(540),
        "end_minutes": .int(600), "task_id": .null,
        "calendar_event_id": .string(eventID), "event_source": .string("canonical"),
        "title": .string("Deleted segment"),
      ])
    ]
    if retainBuffer {
      blocks.append(
        .object([
          "block_type": .string("buffer"), "start_minutes": .int(600),
          "end_minutes": .int(630), "task_id": .null, "calendar_event_id": .null,
          "event_source": .null, "title": .string("Keep buffer"),
        ]))
    }
    let payload = try SyncCanonicalize.canonicalizeJSON(.object([
      "date": .string(date), "rationale": .string("Late schedule"),
      "timezone": .string("UTC"), "blocks": .array(blocks),
      "created_at": .string(timestamp), "updated_at": .string(timestamp),
      "version": .string(version),
    ]))
    return try SyncTestSupport.completeEnvelope(
      entityType: .focusSchedule, entityId: date, operation: .upsert,
      version: parsed(version), payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: payload, deviceId: deviceID)
  }

  private func apply(_ db: Database, _ envelope: SyncEnvelope) throws -> ApplyResult {
    try Apply.applyEnvelope(db, registry: registry, envelope: envelope)
  }

  private func targets(_ result: ApplyResult) throws -> [CalendarCleanupRepairTarget] {
    guard case .repairRequired(.propagateCalendarCleanup(let targets, _)) = result else {
      throw NSError(
        domain: "CalendarSeriesCutoverLateReferenceTests", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "expected cleanup repair, got \(result)"])
    }
    return targets
  }

  private func fulfill(_ db: Database, _ result: ApplyResult, successor: String) throws {
    guard case .repairRequired(let obligation) = result else {
      return XCTFail("expected repair obligation")
    }
    try ApplyRepair.fulfill(
      db, obligation: obligation, mintVersion: { _ in successor },
      deviceId: deviceID)
  }

  private func pending(
    _ db: Database, kind: EntityKind, id: String
  ) throws -> SyncEnvelope? {
    try Outbox.getPending(db).first {
      $0.envelope.entityType == kind && $0.envelope.entityId == id
    }?.envelope
  }

  func testDeletedBoundaryTerminalizesLateEdgeBeforeFkAndLateEventBeforeConflictState() throws {
    let date = "2026-08-20"
    let segmentID = cutoverID(date)
    let edge = try edge(segmentID)
    let event = try event(segmentID, date: date)
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertEqual(try apply(db, deletedCutover(date)), .applied)

      let edgeResult = try apply(db, edge)
      XCTAssertEqual(
        try targets(edgeResult),
        [
          CalendarCleanupRepairTarget(
            entityType: .taskCalendarEventLink, entityId: edge.entityId,
            operation: .delete)
        ])
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM sync_pending_inbox WHERE envelope_entity_id = ?",
          arguments: [edge.entityId]), 0)
      try fulfill(db, edgeResult, successor: v4)
      let edgeDelete = try XCTUnwrap(
        pending(db, kind: .taskCalendarEventLink, id: edge.entityId))
      XCTAssertEqual(edgeDelete.operation, .delete)
      XCTAssertGreaterThan(edgeDelete.version, edge.version)

      let eventResult = try apply(db, event)
      XCTAssertTrue(
        try targets(eventResult).contains(
          CalendarCleanupRepairTarget(
            entityType: .calendarEvent, entityId: segmentID, operation: .delete)))
      try fulfill(db, eventResult, successor: v5)
      let eventDelete = try XCTUnwrap(pending(db, kind: .calendarEvent, id: segmentID))
      XCTAssertEqual(eventDelete.operation, .delete)
      XCTAssertGreaterThan(eventDelete.version, event.version)

      for table in ["sync_conflict_log", "sync_payload_shadow"] {
        XCTAssertEqual(
          try Int.fetchOne(
            db,
            sql: """
              SELECT COUNT(*) FROM \(table)
              WHERE (entity_type = ? AND entity_id = ?)
                 OR (entity_type = ? AND entity_id = ?)
              """,
            arguments: [
              EdgeName.taskCalendarEventLink, edge.entityId,
              EntityName.calendarEvent, segmentID,
            ]),
          0)
      }
    }
  }

  func testDeletedBoundarySanitizesLateFocusScheduleAndDeletesEmptyAggregate() throws {
    let cutoverDate = "2026-08-22"
    let segmentID = cutoverID(cutoverDate)
    let retainedDate = "2026-08-23"
    let emptyDate = "2026-08-24"
    let retained = try schedule(
      date: retainedDate, version: v2, eventID: segmentID, retainBuffer: true)
    let empty = try schedule(
      date: emptyDate, version: v3, eventID: segmentID, retainBuffer: false)
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertEqual(try apply(db, deletedCutover(cutoverDate)), .applied)

      let retainedResult = try apply(db, retained)
      XCTAssertTrue(
        try targets(retainedResult).contains(
          CalendarCleanupRepairTarget(
            entityType: .focusSchedule, entityId: retainedDate,
            operation: .upsert)))
      XCTAssertEqual(
        try String.fetchAll(
          db,
          sql: "SELECT block_type FROM focus_schedule_blocks WHERE date = ?",
          arguments: [retainedDate]),
        ["buffer"])
      try fulfill(db, retainedResult, successor: v4)
      let sanitized = try XCTUnwrap(pending(db, kind: .focusSchedule, id: retainedDate))
      XCTAssertEqual(sanitized.operation, .upsert)
      XCTAssertFalse(sanitized.payload.contains(segmentID))
      XCTAssertTrue(sanitized.payload.contains("Keep buffer"))

      let emptyResult = try apply(db, empty)
      XCTAssertTrue(
        try targets(emptyResult).contains(
          CalendarCleanupRepairTarget(
            entityType: .focusSchedule, entityId: emptyDate,
            operation: .delete)))
      XCTAssertNil(
        try String.fetchOne(
          db, sql: "SELECT date FROM focus_schedule WHERE date = ?", arguments: [emptyDate]))
      try fulfill(
        db, emptyResult, successor: "1760000000500_0001_6666666666666666")
      XCTAssertEqual(try pending(db, kind: .focusSchedule, id: emptyDate)?.operation, .delete)

      for table in ["sync_conflict_log", "sync_payload_shadow"] {
        XCTAssertEqual(
          try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM \(table) WHERE entity_type = ? AND entity_id IN (?, ?)",
            arguments: [EntityName.focusSchedule, retainedDate, emptyDate]),
          0)
      }
    }
  }
}
