import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Wire coverage for deterministic occurrence-decision rows.
final class CalendarEventSeriesOverrideSyncTests: XCTestCase {
  private let seriesId = "11111111-1111-7111-8111-111111111111"
  private let generation = "1711234000000_0000_dec0000100000001"
  private let instanceDate = "2026-06-23"
  private let first = "1711234000001_0000_dec0000100000001"
  private let second = "1711234000002_0000_dec0000100000001"

  private var decisionId: String {
    CalendarOccurrenceDecisionID.make(
      seriesId: seriesId, recurrenceGeneration: generation,
      recurrenceInstanceDate: instanceDate)
  }

  private func payload(state: CalendarOccurrenceState, title: String = "Standup moved") -> String {
    try! SyncCanonicalize.canonicalizeJSON(
      .object([
        "all_day": .bool(false), "attendees": .null, "color": .null,
        "created_at": .string("2026-06-23T09:00:00.000Z"), "description": .null,
        "end_date": .null, "end_time": .null, "event_type": .string("event"),
        "id": .string(decisionId), "location": .null,
        "occurrence_state": .string(state.rawValue), "person_name": .null,
        "recurrence": .null, "recurrence_generation": .string(generation),
        "recurrence_instance_date": .string(instanceDate),
        "content_version": .null, "recurrence_topology_version": .null,
        "series_cutover_id": .null,
        "series_id": .string(seriesId),
        "start_date": .string(instanceDate), "start_time": .string("09:00"),
        "timezone": .string("America/Los_Angeles"), "title": .string(title),
        "updated_at": .string("2026-06-23T09:00:00.000Z"), "url": .null,
        "version": .string(first),
      ]))
  }

  private func insertDecision(_ db: Database) throws {
    try db.execute(
      sql: """
        INSERT INTO calendar_events
          (id, title, start_date, start_time, all_day, event_type, series_id,
           recurrence_instance_date, occurrence_state, recurrence_generation,
           version, created_at, updated_at)
        VALUES (?, 'Standup moved', ?, '09:00', 0, 'event', ?, ?, 'replacement', ?, ?,
                '2026-06-23T09:00:00.000Z', '2026-06-23T09:00:00.000Z')
        """,
      arguments: [decisionId, instanceDate, seriesId, instanceDate, generation, first])
  }

  func testPayloadBuildEmitsDecisionIdentityAndState() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try self.insertDecision(db)
      guard case .object(let object)? = try PayloadBuild.buildAggregatePayload(
        db, entityType: EntityName.calendarEvent, entityId: self.decisionId)
      else { return XCTFail("expected payload object") }
      XCTAssertEqual(object["series_id"], .string(self.seriesId))
      XCTAssertEqual(object["recurrence_instance_date"], .string(self.instanceDate))
      XCTAssertEqual(object["recurrence_generation"], .string(self.generation))
      XCTAssertEqual(object["occurrence_state"], .string("replacement"))
      XCTAssertEqual(object["content_version"], .null)
      XCTAssertEqual(object["recurrence_topology_version"], .null)
    }
  }

  func testApplyRejectsMismatchedDecisionIdentity() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertThrowsError(
        try ApplyCalendarEvent.applyCalendarEventUpsert(
          db, entityId: "22222222-2222-7222-8222-222222222222",
          payload: self.payload(state: .replacement), version: self.first,
          tieBreak: .rejectEqual, applyTs: "2026-06-23T09:00:00.000Z"))
    }
  }

  func testDecisionWholeRowLwwConvergesAcrossArrivalOrder() throws {
    let left = try SyncTestSupport.freshStore()
    let right = try SyncTestSupport.freshStore()

    func apply(_ db: Database, state: CalendarOccurrenceState, version: String) throws {
      try ApplyCalendarEvent.applyCalendarEventUpsert(
        db, entityId: self.decisionId, payload: self.payload(state: state), version: version,
        tieBreak: .rejectEqual, applyTs: "2026-06-23T09:00:00.000Z")
    }
    try left.writer.write { db in
      try apply(db, state: .replacement, version: first)
      try apply(db, state: .cancelled, version: second)
    }
    try right.writer.write { db in
      try apply(db, state: .cancelled, version: second)
      try apply(db, state: .replacement, version: first)
    }

    let leftState = try left.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT occurrence_state FROM calendar_events WHERE id = ?",
        arguments: [decisionId])
    }
    let rightState = try right.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT occurrence_state FROM calendar_events WHERE id = ?",
        arguments: [decisionId])
    }
    XCTAssertEqual(leftState, "cancelled")
    XCTAssertEqual(rightState, leftState)
  }
}
