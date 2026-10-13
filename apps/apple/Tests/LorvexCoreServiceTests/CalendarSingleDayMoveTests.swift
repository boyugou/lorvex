import GRDB
import XCTest

@testable import LorvexCore

/// Moving the start of a single-day event keeps it a single day. A timed event created with an end
/// date equal to its start (and no end time) stores that end date, but the typed row reads it as "no
/// end date", so a move of the start left the stored end date behind, before the start, and the
/// database's date rule refused the write with SQLite's own text. A multi-day event keeps its end
/// date unless the caller moves that too, as before.
final class CalendarSingleDayMoveTests: XCTestCase {
  private func create(
    _ service: SwiftLorvexCoreService, start: String, end: String?, time: String?
  ) async throws -> CalendarTimelineEvent {
    try await service.createCalendarEvent(
      title: "Event", startDate: start, endDate: end, startTime: time, endTime: nil,
      allDay: time == nil, location: nil, notes: nil, recurrence: nil, timezone: nil, url: nil,
      color: nil, eventType: nil, personName: nil, attendees: nil)
  }

  private func move(
    _ service: SwiftLorvexCoreService, _ id: String, to start: String, end: String? = nil
  ) async throws -> CalendarTimelineEvent {
    try await service.updateCalendarEvent(
      id: id, title: nil, startDate: start, endDate: end, startTime: nil, endTime: nil, allDay: nil,
      location: nil, notes: nil, recurrence: .unset, timezone: nil, url: nil, color: nil,
      eventType: nil, personName: nil, attendees: .unset)
  }

  private func storedEnd(_ service: SwiftLorvexCoreService, _ id: String) throws -> String? {
    try service.read { db in
      try String.fetchOne(db, sql: "SELECT end_date FROM calendar_events WHERE id = ?", arguments: [id])
    }
  }

  func testATimedEventWithAnExplicitSameDayEndDateMovesWithItsEnd() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let event = try await create(service, start: "2026-09-18", end: "2026-09-18", time: "00:55")
    XCTAssertEqual(try storedEnd(service, event.id), "2026-09-18")

    let moved = try await move(service, event.id, to: "2026-11-05")

    XCTAssertEqual(moved.startDate, "2026-11-05")
    XCTAssertEqual(try storedEnd(service, event.id), "2026-11-05")
  }

  func testAnAllDayEventWithAnExplicitSameDayEndDateMovesWithItsEnd() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let event = try await create(service, start: "2026-09-18", end: "2026-09-18", time: nil)

    let moved = try await move(service, event.id, to: "2026-11-05")

    XCTAssertEqual(moved.startDate, "2026-11-05")
    XCTAssertEqual(try storedEnd(service, event.id), "2026-11-05")
  }

  func testASingleDayEventWithNoEndDateStillMoves() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let event = try await create(service, start: "2026-09-18", end: nil, time: "09:00")

    let moved = try await move(service, event.id, to: "2026-11-05")

    XCTAssertEqual(moved.startDate, "2026-11-05")
    XCTAssertNil(try storedEnd(service, event.id))
  }

  func testAMultiDayEventKeepsItsEndDateAndAStartMovedPastItIsRefusedInPlainWords() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let event = try await create(service, start: "2026-09-18", end: "2026-09-20", time: nil)

    let shortened = try await move(service, event.id, to: "2026-09-19")
    XCTAssertEqual(shortened.startDate, "2026-09-19")
    XCTAssertEqual(try storedEnd(service, event.id), "2026-09-20")

    do {
      _ = try await move(service, event.id, to: "2026-11-05")
      XCTFail("the start moved past the end date")
    } catch {
      XCTAssertTrue("\(error)".contains("cannot be before start_date"), "\(error)")
      XCTAssertFalse("\(error)".contains("SQLite"), "\(error)")
    }

    let rescheduled = try await move(service, event.id, to: "2026-11-05", end: "2026-11-07")
    XCTAssertEqual(rescheduled.startDate, "2026-11-05")
    XCTAssertEqual(try storedEnd(service, event.id), "2026-11-07")
  }

  /// A constraint of the stored data that validation did not foresee reaches the caller as a typed
  /// validation error that says what happened, never as SQLite's text.
  func testAConstraintFailureInAWriteIsATypedValidationErrorWithoutSQLiteText() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    do {
      try service.withWrite { db, _, _ in
        try db.execute(sql: "INSERT INTO lists (id) VALUES (NULL)")
      }
      XCTFail("the insert broke a NOT NULL rule")
    } catch let error as LorvexCoreError {
      guard case .validation(let field, let message) = error else {
        return XCTFail("expected a validation error, got \(error)")
      }
      XCTAssertEqual(field, LorvexCoreError.storedDataRuleField)
      XCTAssertFalse(message.contains("SQLite"), message)
      XCTAssertFalse(message.contains("CHECK"), message)
    }
  }
}
