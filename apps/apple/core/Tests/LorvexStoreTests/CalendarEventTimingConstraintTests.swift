import GRDB
import XCTest

@testable import LorvexStore

/// Defense-in-depth for direct SQL writers: the schema rejects temporal field
/// combinations outside `CalendarEventTiming`, even if a caller bypasses the
/// normal workflow and sync validation layers.
final class CalendarEventTimingConstraintTests: XCTestCase {
  private let version = "0000000000000_0000_0000000000000000"

  private func insert(
    _ db: Database, id: String, startDate: String = "2026-04-20",
    startTime: String?, endDate: String?, endTime: String?, allDay: Bool
  ) throws {
    try db.execute(
      sql: """
        INSERT INTO calendar_events
          (id, title, start_date, start_time, end_date, end_time, all_day,
           event_type, recurrence_topology_version, content_version, version,
           created_at, updated_at)
        VALUES (?, 'Event', ?, ?, ?, ?, ?, 'event', ?, ?, ?,
                '2026-04-20T09:00:00.000Z', '2026-04-20T09:00:00.000Z')
        """,
      arguments: [
        id, startDate, startTime, endDate, endTime, allDay ? 1 : 0,
        version, version, version,
      ])
  }

  private func assertConstraint(
    _ expression: @autoclosure () throws -> Void,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertThrowsError(try expression(), file: file, line: line) { error in
      guard let dbError = error as? DatabaseError else {
        return XCTFail("expected DatabaseError, got \(error)", file: file, line: line)
      }
      XCTAssertEqual(dbError.resultCode, .SQLITE_CONSTRAINT, file: file, line: line)
    }
  }

  func testSchemaRejectsIllegalTemporalShapes() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      assertConstraint(
        try self.insert(
          db, id: "missing-start", startTime: nil, endDate: nil, endTime: nil,
          allDay: false))
      assertConstraint(
        try self.insert(
          db, id: "reversed-date", startTime: "09:00", endDate: "2026-04-19",
          endTime: "10:00", allDay: false))
      assertConstraint(
        try self.insert(
          db, id: "reversed-time", startTime: "10:00", endDate: nil,
          endTime: "09:59", allDay: false))
      assertConstraint(
        try self.insert(
          db, id: "multi-no-end-time", startTime: "09:00", endDate: "2026-04-21",
          endTime: nil, allDay: false))
      assertConstraint(
        try self.insert(
          db, id: "all-day-with-time", startTime: "09:00", endDate: nil,
          endTime: nil, allDay: true))
    }
  }

  func testSchemaAcceptsCanonicalTemporalShapes() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insert(
        db, id: "timed-point", startTime: "09:00", endDate: nil, endTime: nil,
        allDay: false)
      try self.insert(
        db, id: "timed-span", startTime: "18:00", endDate: "2026-04-21",
        endTime: "09:00", allDay: false)
      try self.insert(
        db, id: "all-day", startTime: nil, endDate: "2026-04-21", endTime: nil,
        allDay: true)

      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM calendar_events"), 3)
    }
  }
}
