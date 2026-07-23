import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

final class FocusScheduleEventProvenanceConvergenceTests: XCTestCase {
  private let date = "2026-08-01"
  private let eventId = "01943a6d-b5c8-7e1f-9a12-3456789abcde"
  private let version = "1760000000000_0001_0123456789abcdef"
  private let timestamp = "2026-08-01T12:00:00.000Z"

  private func canonicalSchedulePayload() -> JSONValue {
    .object([
      "date": .string(date),
      "rationale": .string("Protect planning time"),
      "timezone": .string("America/Los_Angeles"),
      "created_at": .string(timestamp),
      "updated_at": .string(timestamp),
      "blocks": .array([
        .object([
          "block_type": .string("event"),
          "start_minutes": .int(600),
          "end_minutes": .int(660),
          "task_id": .null,
          "calendar_event_id": .string(eventId),
          "event_source": .string(FocusScheduleEventSource.canonical.rawValue),
          "title": .string("Planning session"),
        ])
      ]),
    ])
  }

  private func applySchedule(_ db: Database, payload: JSONValue) throws {
    try ApplyDayScoped.applyFocusScheduleUpsert(
      db, entityId: date, payload: try SyncCanonicalize.canonicalizeJSON(payload),
      version: version, tieBreak: .rejectEqual)
  }

  private func insertCanonicalEvent(_ db: Database) throws {
    try db.execute(
      sql: """
        INSERT INTO calendar_events (
          id, title, start_date, start_time, end_date, end_time, all_day,
          event_type, content_version, recurrence_topology_version, version, created_at, updated_at
        ) VALUES (?, 'Planning session', ?, '10:00', ?, '11:00', 0,
          'event', ?, ?, ?, ?, ?)
        """,
      arguments: [eventId, date, date, version, version, version, timestamp, timestamp])
  }

  private func snapshot(_ db: Database) throws -> JSONValue {
    try XCTUnwrap(
      PayloadBuild.buildAggregatePayload(
        db, entityType: EntityName.focusSchedule, entityId: date))
  }

  func testCanonicalSnapshotIsIndependentOfEventArrivalOrder() throws {
    let eventFirst = try SyncTestSupport.freshStore()
    let scheduleFirst = try SyncTestSupport.freshStore()

    let firstSnapshot = try eventFirst.writer.write { db in
      try insertCanonicalEvent(db)
      try applySchedule(db, payload: canonicalSchedulePayload())
      return try snapshot(db)
    }

    let scheduleFirstState = try scheduleFirst.writer.write { db -> (
      snapshot: JSONValue, backfillPayload: JSONValue
    ) in
      try applySchedule(db, payload: canonicalSchedulePayload())
      let scheduleSnapshot = try snapshot(db)
      let report = try Outbox.enqueueAllLiveForFullResync(db)
      XCTAssertEqual(report.skipped, 0)
      let entry = try XCTUnwrap(
        Outbox.getPending(db).first {
          $0.envelope.entityType == .focusSchedule && $0.envelope.entityId == date
        })
      return (
        scheduleSnapshot,
        try XCTUnwrap(JSONValue.parse(entry.envelope.payload)))
    }
    let beforeEventSnapshot = scheduleFirstState.snapshot
    XCTAssertEqual(beforeEventSnapshot, firstSnapshot)

    let afterEventSnapshot = try scheduleFirst.writer.write { db in
      try insertCanonicalEvent(db)
      return try snapshot(db)
    }
    XCTAssertEqual(afterEventSnapshot, firstSnapshot)

    let thirdPeer = try SyncTestSupport.freshStore()
    try thirdPeer.writer.write { db in
      try applySchedule(db, payload: scheduleFirstState.backfillPayload)
      let row = try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: "SELECT calendar_event_id, event_source, title FROM focus_schedule_blocks WHERE date = ?",
          arguments: [date]))
      XCTAssertEqual(row[0] as String?, eventId)
      XCTAssertEqual(row[1] as String?, FocusScheduleEventSource.canonical.rawValue)
      XCTAssertEqual(row[2] as String?, "Planning session")

      try insertCanonicalEvent(db)
      XCTAssertEqual(try snapshot(db), firstSnapshot)
    }
  }

  func testProviderTitleIsNeutralizedAndRemainsNeutralOnPeerResnapshot() throws {
    let origin = try SyncTestSupport.freshStore()
    let outbound = try origin.writer.write { db -> JSONValue in
      _ = try FocusScheduleBlocksRepo.syncUpsertFocusSchedule(
        db, date: date, rationale: nil, timezone: "UTC", version: version,
        createdAt: timestamp, updatedAt: timestamp, versionCmp: .greater)
      try FocusScheduleBlocksRepo.materializeScheduleBlocks(
        db, date: date,
        blocks: [
          .init(
            blockType: "event", startMinutes: 720, endMinutes: 780,
            eventSource: .provider, title: "Secret board meeting")
        ])
      XCTAssertEqual(
        try String.fetchOne(
          db,
          sql: "SELECT title FROM focus_schedule_blocks WHERE date = ?",
          arguments: [date]),
        "Secret board meeting", "local provider title remains available on its source device")
      return try snapshot(db)
    }

    guard case .object(let payloadObject) = outbound,
      case .array(let blocks)? = payloadObject["blocks"],
      case .object(let block) = try XCTUnwrap(blocks.first)
    else { return XCTFail("expected focus schedule block payload") }
    XCTAssertEqual(block["calendar_event_id"], .null)
    XCTAssertEqual(block["event_source"], .string(FocusScheduleEventSource.provider.rawValue))
    XCTAssertEqual(block["title"], .string("Event"))

    let peer = try SyncTestSupport.freshStore()
    try peer.writer.write { db in
      try applySchedule(db, payload: outbound)
      XCTAssertEqual(try snapshot(db), outbound)
      XCTAssertEqual(
        try String.fetchOne(
          db,
          sql: "SELECT title FROM focus_schedule_blocks WHERE date = ?",
          arguments: [date]),
        "Event")
    }
  }

  func testFreeformTitleSurvivesRoundTrip() throws {
    let origin = try SyncTestSupport.freshStore()
    let outbound = try origin.writer.write { db -> JSONValue in
      try applySchedule(
        db,
        payload: .object([
          "date": .string(date), "rationale": .null, "timezone": .string("UTC"),
          "created_at": .string(timestamp), "updated_at": .string(timestamp),
          "blocks": .array([
            .object([
              "block_type": .string("event"), "start_minutes": .int(720),
              "end_minutes": .int(780), "task_id": .null, "calendar_event_id": .null,
              "event_source": .string(FocusScheduleEventSource.freeform.rawValue),
              "title": .string("Lunch"),
            ])
          ]),
        ]))
      return try snapshot(db)
    }

    let peer = try SyncTestSupport.freshStore()
    try peer.writer.write { db in
      try applySchedule(db, payload: outbound)
      XCTAssertEqual(try snapshot(db), outbound)
      let row = try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: "SELECT calendar_event_id, event_source, title FROM focus_schedule_blocks WHERE date = ?",
          arguments: [date]))
      XCTAssertNil(row[0] as String?)
      XCTAssertEqual(row[1] as String?, FocusScheduleEventSource.freeform.rawValue)
      XCTAssertEqual(row[2] as String?, "Lunch")
    }
  }
}
