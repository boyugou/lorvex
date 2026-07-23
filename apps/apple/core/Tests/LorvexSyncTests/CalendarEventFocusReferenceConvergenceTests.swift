import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Ordinary calendar-event deletion is an absorbing boundary for canonical
/// focus-schedule blocks, independent of CloudKit arrival order.
final class CalendarEventFocusReferenceConvergenceTests: XCTestCase {
  private let eventId = "77777777-7777-4777-8777-777777777771"
  private let planDate = "2026-08-05"
  private let timestamp = "2026-08-05T12:00:00.000Z"
  private let v1 = "1760000010000_0001_1111111111111111"
  private let v2 = "1760000010100_0001_2222222222222222"
  private let v3 = "1760000010200_0001_3333333333333333"
  private let v4 = "1760000010300_0001_4444444444444444"
  private let v5 = "1760000010400_0001_5555555555555555"
  private let deviceId = "77777777-7777-4777-8777-777777777799"
  private let registry = EntityApplierRegistry(
    appliers: EntityApplierRegistry.defaultEntityAppliers())

  func testEventDeleteAfterScheduleRemovesReferenceAndDeletesEmptyRoot() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertEqual(try apply(db, eventEnvelope()), .applied)
      XCTAssertEqual(
        try apply(db, scheduleEnvelope(version: v2, retainBuffer: false)), .applied)

      let result = try apply(db, deleteEnvelope())
      let obligation = try calendarRepair(result)
      guard case .propagateCalendarCleanup(let targets, _) = obligation else {
        return XCTFail("expected calendar cleanup")
      }
      XCTAssertEqual(
        targets,
        [
          CalendarCleanupRepairTarget(
            entityType: .focusSchedule, entityId: planDate, operation: .delete)
        ])
      XCTAssertNil(
        try String.fetchOne(
          db, sql: "SELECT date FROM focus_schedule WHERE date = ?1",
          arguments: [planDate]))
      XCTAssertNotNil(
        try Tombstone.getTombstone(
          db, entityType: EntityName.calendarEvent, entityId: eventId))

      try fulfill(db, obligation: obligation, successor: v5)
      XCTAssertEqual(
        try pending(db, kind: .focusSchedule, id: planDate)?.operation,
        .delete)
    }
  }

  func testScheduleAfterEventDeleteCannotRestoreCanonicalReference() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertEqual(try apply(db, eventEnvelope()), .applied)
      XCTAssertEqual(try apply(db, deleteEnvelope()), .applied)

      let result = try apply(db, scheduleEnvelope(version: v4, retainBuffer: true))
      let obligation = try calendarRepair(result)
      guard case .propagateCalendarCleanup(let targets, _) = obligation else {
        return XCTFail("expected calendar cleanup")
      }
      XCTAssertEqual(
        targets,
        [
          CalendarCleanupRepairTarget(
            entityType: .focusSchedule, entityId: planDate, operation: .upsert)
        ])
      XCTAssertEqual(
        try String.fetchAll(
          db,
          sql: "SELECT block_type FROM focus_schedule_blocks WHERE date = ?1",
          arguments: [planDate]),
        ["buffer"])

      try fulfill(db, obligation: obligation, successor: v5)
      let repaired = try XCTUnwrap(
        pending(db, kind: .focusSchedule, id: planDate))
      XCTAssertEqual(repaired.operation, .upsert)
      XCTAssertFalse(repaired.payload.contains(eventId))
      XCTAssertTrue(repaired.payload.contains("Keep buffer"))
    }
  }

  private func apply(_ db: Database, _ envelope: SyncEnvelope) throws -> ApplyResult {
    try Apply.applyEnvelope(db, registry: registry, envelope: envelope)
  }

  private func calendarRepair(_ result: ApplyResult) throws -> ApplyRepairObligation {
    guard case .repairRequired(let obligation) = result,
      case .propagateCalendarCleanup = obligation
    else {
      XCTFail("expected calendar cleanup repair, got \(result)")
      throw NSError(domain: "CalendarEventFocusReferenceConvergenceTests", code: 1)
    }
    return obligation
  }

  private func fulfill(
    _ db: Database, obligation: ApplyRepairObligation, successor: String
  ) throws {
    try ApplyRepair.fulfill(
      db, obligation: obligation, mintVersion: { _ in successor }, deviceId: deviceId)
  }

  private func pending(
    _ db: Database, kind: EntityKind, id: String
  ) throws -> SyncEnvelope? {
    try Outbox.getPending(db).first {
      $0.envelope.entityType == kind && $0.envelope.entityId == id
    }?.envelope
  }

  private func eventEnvelope() throws -> SyncEnvelope {
    try SyncTestSupport.completeEnvelope(
      entityType: .calendarEvent, entityId: eventId, operation: .upsert,
      version: Hlc.parse(v1), payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: try SyncCanonicalize.canonicalizeJSON(
        .object([
          "title": .string("Planning"), "start_date": .string(planDate),
          "start_time": .string("09:00"), "end_date": .string(planDate),
          "end_time": .string("10:00"), "all_day": .bool(false),
          "timezone": .string("UTC"), "event_type": .string("event"),
          "series_cutover_id": .null, "series_id": .null,
          "recurrence_instance_date": .null, "occurrence_state": .null,
          "recurrence": .null, "recurrence_generation": .null,
          "content_version": .string(v1),
          "recurrence_topology_version": .string(v1),
          "created_at": .string(timestamp), "updated_at": .string(timestamp),
        ])),
      deviceId: deviceId)
  }

  private func deleteEnvelope() throws -> SyncEnvelope {
    try SyncTestSupport.completeEnvelope(
      entityType: .calendarEvent, entityId: eventId, operation: .delete,
      version: Hlc.parse(v3), payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: try SyncCanonicalize.canonicalizeJSON(
        .object(["version": .string(v3)])),
      deviceId: deviceId)
  }

  private func scheduleEnvelope(version: String, retainBuffer: Bool) throws -> SyncEnvelope {
    var blocks: [JSONValue] = [
      .object([
        "block_type": .string("event"), "start_minutes": .int(540),
        "end_minutes": .int(600), "task_id": .null,
        "calendar_event_id": .string(eventId), "event_source": .string("canonical"),
        "title": .string("Planning"),
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
    return try SyncTestSupport.completeEnvelope(
      entityType: .focusSchedule, entityId: planDate, operation: .upsert,
      version: Hlc.parse(version), payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: try SyncCanonicalize.canonicalizeJSON(
        .object([
          "date": .string(planDate), "rationale": .string("Plan"),
          "timezone": .string("UTC"), "blocks": .array(blocks),
          "created_at": .string(timestamp), "updated_at": .string(timestamp),
        ])),
      deviceId: deviceId)
  }
}
