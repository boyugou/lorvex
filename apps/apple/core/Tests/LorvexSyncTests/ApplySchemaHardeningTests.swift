import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Apply-path trust-boundary pre-validation for schema invariants that a raw
/// bind would otherwise push down to a `SQLITE_CONSTRAINT` (dropped opaquely by
/// the inbound batch loop) or, for the invariants with no backing CHECK, land as
/// a silently-corrupt row. Each case asserts a typed ``ApplyError/invalidPayload``
/// skip (a single-envelope drop) with a recognizable reason, never a raw
/// `.db` / `.dbConstraint` error and never a landed row.
final class ApplySchemaHardeningTests: XCTestCase {

  private let vMid = "1711234568000_0000_dec0000100000001"
  private let zeroVersion = "0000000000000_0000_0000000000000000"
  private let taskId = "01943a6d-b5c8-7e1f-9a12-3456789abcdf"

  private func withDB(_ body: (Database) throws -> Void) throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in try body(db) }
  }

  private func canon(_ obj: JSONValue) -> String {
    try! SyncCanonicalize.canonicalizeJSON(obj)
  }

  private func insertHabit(_ db: Database, _ id: String) throws {
    try db.execute(
      sql: """
        INSERT INTO habits (id, name, frequency_type, target_count, archived,
                            lookup_key, version, created_at, updated_at)
        VALUES (?, 'Read', 'daily', 1, 0, ?, ?, '', '')
        """,
      arguments: [id, id, zeroVersion])
  }

  private func assertInvalidPayload(
    _ expr: @autoclosure () throws -> Void, containing needle: String,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertThrowsError(try expr(), file: file, line: line) { error in
      guard case let ApplyError.invalidPayload(msg) = error else {
        return XCTFail(
          "expected .invalidPayload (single-envelope drop), got \(error) — a .db / .dbConstraint "
            + "error surfaces an opaque reason", file: file, line: line)
      }
      XCTAssertTrue(
        msg.contains(needle), "reason '\(msg)' should mention '\(needle)'", file: file, line: line)
    }
  }

  // MARK: - focus_schedule_blocks (block_type, task_id, calendar_event_id) cross-field

  private func focusPayload(_ block: JSONValue) -> String {
    return canon(
      .object([
        "created_at": .string("2026-04-01T00:00:00Z"),
        "updated_at": .string("2026-04-01T00:00:00Z"),
        "blocks": .array([block]),
      ]))
  }

  private func applyFocus(_ db: Database, _ block: JSONValue) throws {
    try ApplyDayScoped.applyFocusScheduleUpsert(
      db, entityId: "2026-04-01", payload: focusPayload(block), version: vMid,
      tieBreak: .rejectEqual)
  }

  func testFocusTaskBlockWithoutTaskIdIsInvalidPayload() throws {
    try withDB { db in
      assertInvalidPayload(
        try self.applyFocus(
          db,
          .object([
            "block_type": .string("task"), "start_minutes": .int(540), "end_minutes": .int(570),
            "event_source": .null,
          ])),
        containing: "block_type 'task'")
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM focus_schedule_blocks WHERE date = ?",
          arguments: ["2026-04-01"]), 0, "no block should have landed")
    }
  }

  func testFocusBufferBlockWithEventIdIsInvalidPayload() throws {
    try withDB { db in
      assertInvalidPayload(
        try self.applyFocus(
          db,
          .object([
            "block_type": .string("buffer"), "start_minutes": .int(540), "end_minutes": .int(570),
            "calendar_event_id": .string("01943a6d-b5c8-7e1f-9a12-3456789abcde"),
            "event_source": .null,
          ])),
        containing: "block_type 'buffer'")
    }
  }

  func testFocusTaskBlockWithEventIdIsInvalidPayload() throws {
    try withDB { db in
      assertInvalidPayload(
        try self.applyFocus(
          db,
          .object([
            "block_type": .string("task"), "start_minutes": .int(540), "end_minutes": .int(570),
            "task_id": .string(self.taskId),
            "calendar_event_id": .string("01943a6d-b5c8-7e1f-9a12-3456789abcde"),
            "event_source": .null,
          ])),
        containing: "block_type 'task'")
    }
  }

  func testFocusValidBlocksApply() throws {
    try withDB { db in
      try self.applyFocus(
        db,
        .object([
          "block_type": .string("task"), "start_minutes": .int(540), "end_minutes": .int(570),
          "task_id": .string(self.taskId), "event_source": .null,
        ]))
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM focus_schedule_blocks WHERE date = ?",
          arguments: ["2026-04-01"]), 1)
    }
  }

  // MARK: - habit_completions.value > 0

  private func completionPayload(value: Int64) -> String {
    canon(
      .object([
        "value": .int(value), "created_at": .string("2026-04-01T00:00:00Z"),
        "updated_at": .string("2026-04-01T00:00:00Z"),
      ]))
  }

  private func applyCompletion(_ db: Database, habitId: String, date: String, value: Int64) throws {
    try ApplyEdge.applyHabitCompletionUpsert(
      db, entityId: "\(habitId):\(date)", payload: completionPayload(value: value), version: vMid,
      tieBreak: .rejectEqual)
  }

  func testHabitCompletionZeroValueIsInvalidPayload() throws {
    try withDB { db in
      assertInvalidPayload(
        try self.applyCompletion(db, habitId: "h-1", date: "2026-04-01", value: 0),
        containing: "value must be > 0")
      XCTAssertEqual(
        try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM habit_completions"), 0)
    }
  }

  func testHabitCompletionNegativeValueIsInvalidPayload() throws {
    try withDB { db in
      assertInvalidPayload(
        try self.applyCompletion(db, habitId: "h-1", date: "2026-04-01", value: -3),
        containing: "value must be > 0")
    }
  }

  func testHabitCompletionPositiveValueApplies() throws {
    try withDB { db in
      try self.insertHabit(db, "h-1")
      try self.applyCompletion(db, habitId: "h-1", date: "2026-04-01", value: 2)
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT value FROM habit_completions WHERE habit_id = ? AND completed_date = ?",
          arguments: ["h-1", "2026-04-01"]), 2)
    }
  }

  // MARK: - habit_reminder_policies.reminder_time HH:MM

  private func policyPayload(habitId: String, reminderTime: String) -> String {
    canon(
      .object([
        "habit_id": .string(habitId), "reminder_time": .string(reminderTime),
        "enabled": .bool(true), "created_at": .string("2026-04-01T00:00:00Z"),
        "updated_at": .string("2026-04-01T00:00:00Z"),
      ]))
  }

  private func applyPolicy(_ db: Database, id: String, habitId: String, reminderTime: String) throws
  {
    try ApplyChild.applyHabitReminderPolicyUpsert(
      db, entityId: id, payload: policyPayload(habitId: habitId, reminderTime: reminderTime),
      version: vMid, tieBreak: .rejectEqual, applyTs: "2026-04-01T00:00:00Z")
  }

  func testReminderPolicyMalformedTimesAreInvalidPayload() throws {
    try withDB { db in
      for bad in ["9:5", "09:00:00", "", "25:00", "24:00", "9am"] {
        assertInvalidPayload(
          try self.applyPolicy(db, id: "p-\(bad.count)", habitId: "h-1", reminderTime: bad),
          containing: "reminder_time must be HH:MM")
      }
      XCTAssertEqual(
        try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM habit_reminder_policies"), 0)
    }
  }

  func testReminderPolicyValidTimeApplies() throws {
    try withDB { db in
      try self.insertHabit(db, "h-1")
      try self.applyPolicy(db, id: "p-1", habitId: "h-1", reminderTime: "09:05")
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT reminder_time FROM habit_reminder_policies WHERE id = ?",
          arguments: ["p-1"]), "09:05")
    }
  }

  // MARK: - calendar occurrence-decision linkage

  private func calendarPayload(seriesId: JSONValue, recurrenceInstanceDate: JSONValue) -> String {
    let isDecision: Bool
    if case .string = seriesId { isDecision = true } else { isDecision = false }
    return canon(
      .object([
        "title": .string("Standup"), "start_date": .string("2026-04-20"),
        "start_time": .string("09:00"),
        "all_day": .bool(false), "event_type": .string("event"),
        "series_id": seriesId, "recurrence_instance_date": recurrenceInstanceDate,
        "occurrence_state": isDecision ? .string("replacement") : .null,
        "recurrence": .null,
        "recurrence_generation": isDecision ? .string(vMid) : .null,
        "content_version": isDecision ? .null : .string(vMid),
        "recurrence_topology_version": isDecision ? .null : .string(vMid),
        "series_cutover_id": .null,
        "created_at": .string("2026-04-20T09:00:00.000Z"),
        "updated_at": .string("2026-04-20T09:00:00.000Z"),
      ]))
  }

  private func applyCalendar(
    _ db: Database, id: String, seriesId: JSONValue, recurrenceInstanceDate: JSONValue
  ) throws {
    try ApplyCalendarEvent.applyCalendarEventUpsert(
      db, entityId: id,
      payload: calendarPayload(seriesId: seriesId, recurrenceInstanceDate: recurrenceInstanceDate),
      version: vMid, tieBreak: .rejectEqual, applyTs: "2026-04-20T09:00:00.000Z")
  }

  func testCalendarSeriesIdWithoutInstanceDateIsInvalidPayload() throws {
    try withDB { db in
      assertInvalidPayload(
        try self.applyCalendar(
          db, id: "e-1", seriesId: .string("master-1"), recurrenceInstanceDate: .null),
        containing: "must be set together")
      XCTAssertEqual(
        try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM calendar_events"), 0)
    }
  }

  func testCalendarInstanceDateWithoutSeriesIdIsInvalidPayload() throws {
    try withDB { db in
      assertInvalidPayload(
        try self.applyCalendar(
          db, id: "e-1", seriesId: .null, recurrenceInstanceDate: .string("2026-04-20")),
        containing: "must be set together")
    }
  }

  func testCalendarPlainEventBothNullApplies() throws {
    try withDB { db in
      try self.applyCalendar(db, id: "e-1", seriesId: .null, recurrenceInstanceDate: .null)
      XCTAssertEqual(
        try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM calendar_events WHERE id = 'e-1'"), 1)
    }
  }

  func testCalendarOccurrenceDecisionBothSetApplies() throws {
    try withDB { db in
      let seriesId = "11111111-1111-7111-8111-111111111111"
      let decisionId = CalendarOccurrenceDecisionID.make(
        seriesId: seriesId, recurrenceGeneration: self.vMid,
        recurrenceInstanceDate: "2026-04-20")
      try self.applyCalendar(
        db, id: decisionId, seriesId: .string(seriesId),
        recurrenceInstanceDate: .string("2026-04-20"))
      let row = try Row.fetchOne(
        db, sql: "SELECT series_id, recurrence_instance_date FROM calendar_events WHERE id = ?",
        arguments: [decisionId])
      XCTAssertEqual(row?["series_id"], seriesId)
      XCTAssertEqual(row?["recurrence_instance_date"], "2026-04-20")
    }
  }
}
