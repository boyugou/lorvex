import Foundation
import GRDB
import XCTest

@testable import LorvexStore

/// Defense in depth for the task-reminder wall-clock anchor. Production
/// ingress validates the timezone identifier through Foundation; the schema
/// owns the relational pair and canonical `HH:MM` shape for every SQL writer.
final class TaskReminderAnchorConstraintTests: XCTestCase {
  private let version = "0000000000000_0000_0000000000000000"
  private let taskID = "00000001-0000-7000-8000-000000000000"

  private func seedTask(_ db: Database) throws {
    try db.execute(
      sql: """
        INSERT INTO tasks (id, title, version, created_at, updated_at)
        VALUES (?, 'Reminder parent', ?,
                '2026-07-15T12:00:00.000Z', '2026-07-15T12:00:00.000Z')
        """,
      arguments: [taskID, version])
  }

  private func insertReminder(
    _ db: Database, id: String, localTime: String?, timezone: String?
  ) throws {
    try db.execute(
      sql: """
        INSERT INTO task_reminders
          (id, task_id, reminder_at, version, created_at,
           original_local_time, original_tz)
        VALUES (?, ?, '2026-07-16T16:00:00.000Z', ?,
                '2026-07-15T12:00:00.000Z', ?, ?)
        """,
      arguments: [id, taskID, version, localTime, timezone])
  }

  private func assertConstraint(
    _ expression: @autoclosure () throws -> Void,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertThrowsError(try expression(), file: file, line: line) { error in
      guard let databaseError = error as? DatabaseError else {
        return XCTFail("expected DatabaseError, got \(error)", file: file, line: line)
      }
      XCTAssertEqual(databaseError.resultCode, .SQLITE_CONSTRAINT, file: file, line: line)
    }
  }

  func testSchemaRequiresAnchorColumnsTogether() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try seedTask(db)
      assertConstraint(
        try self.insertReminder(
          db, id: "local-only", localTime: "09:00", timezone: nil))
      assertConstraint(
        try self.insertReminder(
          db, id: "zone-only", localTime: nil, timezone: "America/Los_Angeles"))
    }
  }

  func testSchemaRejectsMalformedLocalTimesAndWhitespaceZones() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try seedTask(db)
      for (index, value) in ["9:00", "09:0", "24:00", "09:60", "09:00:00", "ab:cd"]
        .enumerated()
      {
        assertConstraint(
          try self.insertReminder(
            db, id: "bad-time-\(index)", localTime: value,
            timezone: "America/Los_Angeles"))
      }
      for (index, value) in [
        "", " America/Los_Angeles", "America/Los_Angeles ",
        "America/Los_Angeles\t", "America/Los Angeles",
      ]
        .enumerated()
      {
        assertConstraint(
          try self.insertReminder(
            db, id: "bad-zone-\(index)", localTime: "09:00", timezone: value))
      }
    }
  }

  func testSchemaAcceptsAbsentOrCanonicalAnchor() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try seedTask(db)
      try insertReminder(db, id: "no-anchor", localTime: nil, timezone: nil)
      try insertReminder(
        db, id: "anchored", localTime: "09:05", timezone: "America/Los_Angeles")
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM task_reminders"), 2)
    }
  }

  func testSchemaAcceptsFoundationFixedOffsetTimezone() throws {
    let timezone = "GMT+05:30"
    XCTAssertNotNil(TimeZone(identifier: timezone))

    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try seedTask(db)
      try insertReminder(
        db, id: "fixed-offset", localTime: "09:05", timezone: timezone)
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT original_tz FROM task_reminders WHERE id = 'fixed-offset'"),
        timezone)
    }
  }
}
