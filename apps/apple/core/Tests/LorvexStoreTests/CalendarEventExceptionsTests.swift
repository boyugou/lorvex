import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

/// Tests for task recurrence-exception storage helpers.
final class RecurrenceExceptionsRepoTests: XCTestCase {

  private func seedTaskWithList(_ db: Database, taskId: String) throws {
    try db.execute(
      sql: """
        INSERT OR IGNORE INTO lists (id, name, version, created_at, updated_at) \
        VALUES ('list-exc', 'L', '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
        """)
    try db.execute(
      sql: """
        INSERT INTO tasks (id, title, list_id, version, created_at, updated_at) \
        VALUES (?, 'T', 'list-exc', '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
        """,
      arguments: [taskId])
  }

  // -- parse helpers ------------------------------------------------------

  func testParseNoneReturnsEmpty() throws {
    XCTAssertEqual(try RecurrenceExceptionsRepo.parseExceptionDates(nil), [])
  }

  func testParseBlankReturnsEmpty() throws {
    XCTAssertEqual(try RecurrenceExceptionsRepo.parseExceptionDates(""), [])
    XCTAssertEqual(try RecurrenceExceptionsRepo.parseExceptionDates("   "), [])
  }

  func testParseArrayReturnsDatesInOrder() throws {
    let parsed = try RecurrenceExceptionsRepo.parseExceptionDates(
      "[\"2026-04-01\",\"2026-04-08\"]")
    XCTAssertEqual(parsed, ["2026-04-01", "2026-04-08"])
  }

  func testParseInvalidJSONReturnsValidationError() {
    do {
      _ = try RecurrenceExceptionsRepo.parseExceptionDates("not-json")
      XCTFail("expected validation")
    } catch let err as StoreError {
      guard case .validation = err else {
        return XCTFail("expected validation, got \(err)")
      }
    } catch {
      XCTFail("expected StoreError.validation, got \(error)")
    }
  }

  func testParseSetCollapsesDuplicates() throws {
    let set = try RecurrenceExceptionsRepo.parseExceptionDatesAsSet(
      "[\"2026-04-01\",\"2026-04-08\",\"2026-04-01\"]")
    XCTAssertEqual(set.count, 2)
    XCTAssertTrue(set.contains("2026-04-01"))
    XCTAssertTrue(set.contains("2026-04-08"))
  }

  // -- task EXDATE round-trip --------------------------------------------

  func testReplaceTaskExceptionsRoundTripsThroughJSONHelper() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.seedTaskWithList(db, taskId: "task-exc")
      try RecurrenceExceptionsRepo.replaceTaskExceptionsFromJSON(
        db, taskId: "task-exc",
        json: "[\"2026-03-22\",\"2026-03-15\",\"2026-03-22\"]")
      let dates = try RecurrenceExceptionsRepo.loadTaskExceptionDates(db, taskId: "task-exc")
      // Ascending order from the SELECT helper, duplicates collapsed by PK.
      XCTAssertEqual(dates, ["2026-03-15", "2026-03-22"])
      let json = try RecurrenceExceptionsRepo.loadTaskExceptionsJSON(db, taskId: "task-exc")
      XCTAssertEqual(json, "[\"2026-03-15\",\"2026-03-22\"]")
    }
  }

  func testReplaceTaskExceptionsWithEmptyJSONClearsRegistry() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.seedTaskWithList(db, taskId: "task-exc")
      try RecurrenceExceptionsRepo.replaceTaskExceptions(
        db, taskId: "task-exc", dates: ["2026-03-22", "2026-03-15"])
      try RecurrenceExceptionsRepo.replaceTaskExceptionsFromJSON(
        db, taskId: "task-exc", json: nil)
      XCTAssertEqual(
        try RecurrenceExceptionsRepo.loadTaskExceptionDates(db, taskId: "task-exc"), [])
      XCTAssertNil(
        try RecurrenceExceptionsRepo.loadTaskExceptionsJSON(db, taskId: "task-exc"))
    }
  }
}
