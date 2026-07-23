import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// The sync apply boundary must accept exactly the same temporal shapes and
/// timezone/recurrence bounds as first-party calendar writes. A peer must not
/// be able to materialize a row that the domain model cannot represent.
final class ApplyCalendarEventTimingTests: XCTestCase {
  private var versionCounter = 0

  private func nextVersion() -> String {
    versionCounter += 1
    return String(format: "1711234%06d_0000_dec0000100000001", versionCounter)
  }

  private func withDB(_ body: (Database) throws -> Void) throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in try body(db) }
  }

  private func payload(
    startDate: String = "2026-04-20",
    startTime: JSONValue = .string("09:00"),
    endDate: JSONValue = .null,
    endTime: JSONValue = .null,
    allDay: Bool = false,
    timezone: JSONValue = .null,
    recurrence: JSONValue = .null
  ) -> String {
    let recurrenceGeneration: JSONValue
    if recurrence == .null {
      recurrenceGeneration = .null
    } else {
      recurrenceGeneration = .string("1711234000000_0000_dec0000100000001")
    }
    return try! SyncCanonicalize.canonicalizeJSON(
      .object([
        "title": .string("Standup"),
        "start_date": .string(startDate),
        "start_time": startTime,
        "end_date": endDate,
        "end_time": endTime,
        "all_day": .bool(allDay),
        "timezone": timezone,
        "recurrence": recurrence,
        "occurrence_state": .null,
        "recurrence_generation": recurrenceGeneration,
        "recurrence_instance_date": .null,
        "content_version": .string("1711234000000_0000_dec0000100000001"),
        "recurrence_topology_version": .string("1711234000000_0000_dec0000100000001"),
        "series_cutover_id": .null,
        "series_id": .null,
        "event_type": .string("event"),
        "created_at": .string("2026-04-20T09:00:00.000Z"),
        "updated_at": .string("2026-04-20T09:00:00.000Z"),
      ]))
  }

  private func apply(_ db: Database, id: String = "event-1", payload: String) throws {
    try ApplyCalendarEvent.applyCalendarEventUpsert(
      db, entityId: id, payload: payload, version: nextVersion(), tieBreak: .rejectEqual,
      applyTs: "2026-04-20T09:00:00.000Z")
  }

  private func assertInvalidPayload(
    _ expression: @autoclosure () throws -> Void, containing needle: String,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertThrowsError(try expression(), file: file, line: line) { error in
      guard case let ApplyError.invalidPayload(message) = error else {
        return XCTFail("expected invalidPayload, got \(error)", file: file, line: line)
      }
      XCTAssertTrue(
        message.contains(needle), "reason '\(message)' should mention '\(needle)'",
        file: file, line: line)
    }
  }

  func testTimedEventWithoutStartTimeIsRejected() throws {
    try withDB { db in
      assertInvalidPayload(
        try self.apply(db, payload: self.payload(startTime: .null)),
        containing: "start_time")
    }
  }

  func testEndDateBeforeStartDateIsRejected() throws {
    try withDB { db in
      assertInvalidPayload(
        try self.apply(
          db,
          payload: self.payload(
            startDate: "2026-04-20", endDate: .string("2026-04-19"),
            endTime: .string("10:00"))),
        containing: "end_date")
    }
  }

  func testSameDayEndTimeBeforeStartTimeIsRejected() throws {
    try withDB { db in
      assertInvalidPayload(
        try self.apply(
          db,
          payload: self.payload(startTime: .string("10:00"), endTime: .string("09:59"))),
        containing: "end_time")
    }
  }

  func testMultiDayTimedEventWithoutEndTimeIsRejected() throws {
    try withDB { db in
      assertInvalidPayload(
        try self.apply(
          db, payload: self.payload(endDate: .string("2026-04-21"), endTime: .null)),
        containing: "end_time")
    }
  }

  func testInvalidTimezoneIsRejected() throws {
    try withDB { db in
      assertInvalidPayload(
        try self.apply(
          db, payload: self.payload(timezone: .string("Definitely/Not_A_Timezone"))),
        containing: "timezone")
    }
  }

  func testTimezoneIsTrimmedBeforePersistence() throws {
    try withDB { db in
      try self.apply(db, payload: self.payload(timezone: .string("  America/Los_Angeles  ")))
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT timezone FROM calendar_events WHERE id = ?", arguments: ["event-1"]),
        "America/Los_Angeles")
    }
  }

  func testRecurrenceUntilBeforeStartDateIsRejected() throws {
    try withDB { db in
      assertInvalidPayload(
        try self.apply(
          db,
          payload: self.payload(
            recurrence: .string(#"{"FREQ":"DAILY","UNTIL":"2026-04-19"}"#))),
        containing: "UNTIL")
    }
  }

  func testCanonicalTemporalShapesApply() throws {
    try withDB { db in
      try self.apply(
        db, id: "timed-point",
        payload: self.payload(startTime: .string("09:00")))
      try self.apply(
        db, id: "timed-span",
        payload: self.payload(
          startTime: .string("18:00"), endDate: .string("2026-04-21"),
          endTime: .string("09:00")))
      try self.apply(
        db, id: "all-day",
        payload: self.payload(
          startTime: .null, endDate: .string("2026-04-21"), endTime: .null,
          allDay: true))

      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM calendar_events"), 3)
    }
  }
}
