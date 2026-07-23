import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import XCTest

@testable import LorvexCore

final class SwiftLorvexCoreServiceCalendarOccurrenceInvariantTests: XCTestCase {
  private let generation = "0000000000000_0000_0000000000000001"

  private func makeService() throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    return SwiftLorvexCoreService(store: try LorvexStore.openInMemory(schemaSQL: schemaSQL))
  }

  private func uuid() -> String { UUID().uuidString.lowercased() }

  private func importBase(
    _ service: SwiftLorvexCoreService,
    id: String,
    recurrence: String? = #"{"FREQ":"DAILY"}"#
  ) async throws -> CalendarTimelineEvent {
    try await service.importCalendarEvent(
      id: id, title: "Master", startDate: "2026-08-10", startTime: "09:00",
      endDate: "2026-08-10", endTime: "10:00", allDay: false,
      location: nil, notes: nil, url: nil, color: nil, eventType: nil,
      personName: nil, attendees: nil, timezone: "America/Los_Angeles",
      recurrence: recurrence, seriesId: nil, recurrenceInstanceDate: nil,
      occurrenceState: nil,
      recurrenceGeneration: recurrence == nil ? nil : generation)
  }

  private func importDecision(
    _ service: SwiftLorvexCoreService,
    id: String,
    masterID: String,
    date: String = "2026-08-11",
    state: String? = "replacement",
    recurrence: String? = nil,
    generation: String?
  ) async throws -> CalendarTimelineEvent {
    try await service.importCalendarEvent(
      id: id, title: "Decision", startDate: date, startTime: "11:00",
      endDate: date, endTime: "12:00", allDay: false,
      location: nil, notes: nil, url: nil, color: nil, eventType: nil,
      personName: nil, attendees: nil, timezone: "America/Los_Angeles",
      recurrence: recurrence, seriesId: masterID, recurrenceInstanceDate: date,
      occurrenceState: state, recurrenceGeneration: generation)
  }

  private func assertNoArtifacts(
    _ service: SwiftLorvexCoreService,
    id: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    let count = try service.read { db in
      try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM calendar_events WHERE id = ?", arguments: [id])
    }
    XCTAssertEqual(count, 0, file: file, line: line)
    XCTAssertTrue(try service.pendingOutbound().isEmpty, file: file, line: line)
    let changelogCount = try service.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog")
    }
    XCTAssertEqual(changelogCount, 0, file: file, line: line)
  }

  func testImportRejectsRecurringDecisionAtomically() async throws {
    let service = try makeService()
    let masterID = uuid()
    let date = "2026-08-11"
    let id = CalendarOccurrenceDecisionID.make(
      seriesId: masterID, recurrenceGeneration: generation,
      recurrenceInstanceDate: date)

    do {
      _ = try await importDecision(
        service, id: id, masterID: masterID,
        recurrence: #"{"FREQ":"DAILY"}"#, generation: generation)
      XCTFail("A decision must not carry recurrence")
    } catch {
      XCTAssertTrue(String(describing: error).contains("must not carry recurrence"))
    }
    try assertNoArtifacts(service, id: id)
  }

  func testImportRejectsMissingDecisionStateAndGenerationAtomically() async throws {
    let service = try makeService()
    let masterID = uuid()
    let id = uuid()
    do {
      _ = try await importDecision(
        service, id: id, masterID: masterID, state: nil, generation: nil)
      XCTFail("A decision requires state and generation")
    } catch {
      XCTAssertTrue(String(describing: error).contains("occurrence_state"))
    }
    try assertNoArtifacts(service, id: id)
  }

  func testImportRejectsNondeterministicDecisionIDAtomically() async throws {
    let service = try makeService()
    let id = uuid()
    do {
      _ = try await importDecision(
        service, id: id, masterID: uuid(), generation: generation)
      XCTFail("A decision id must be deterministic")
    } catch {
      XCTAssertTrue(String(describing: error).contains("does not match"))
    }
    try assertNoArtifacts(service, id: id)
  }

  func testUpdateCannotTurnDecisionIntoRecurringMaster() async throws {
    let service = try makeService()
    let masterID = uuid()
    _ = try await importBase(service, id: masterID)
    let date = "2026-08-11"
    let decisionID = CalendarOccurrenceDecisionID.make(
      seriesId: masterID, recurrenceGeneration: generation,
      recurrenceInstanceDate: date)
    _ = try await importDecision(
      service, id: decisionID, masterID: masterID, generation: generation)
    try service.write { db in
      try db.execute(sql: "DELETE FROM sync_outbox")
      try db.execute(sql: "DELETE FROM ai_changelog")
    }
    let beforeVersion = try service.read { db in
      try String.fetchOne(
        db, sql: "SELECT version FROM calendar_events WHERE id = ?",
        arguments: [decisionID])
    }

    do {
      _ = try await service.updateCalendarEvent(
        id: decisionID, title: nil, startDate: nil, endDate: nil,
        startTime: nil, endTime: nil, allDay: nil, location: nil,
        notes: nil, recurrence: .set(TaskRecurrenceRule(freq: .daily)),
        timezone: nil, url: nil, color: nil, eventType: nil,
        personName: nil, attendees: .unset)
      XCTFail("A decision must reject recurrence")
    } catch {
      XCTAssertTrue(String(describing: error).contains("must not carry recurrence"))
    }
    let afterVersion = try service.read { db in
      try String.fetchOne(
        db, sql: "SELECT version FROM calendar_events WHERE id = ?",
        arguments: [decisionID])
    }
    XCTAssertEqual(afterVersion, beforeVersion)
    XCTAssertTrue(try service.pendingOutbound().isEmpty)
  }

  func testDecisionMayArriveBeforeMasterAndActivatesAfterMasterRestore() async throws {
    let service = try makeService()
    let masterID = uuid()
    let date = "2026-08-11"
    let decisionID = CalendarOccurrenceDecisionID.make(
      seriesId: masterID, recurrenceGeneration: generation,
      recurrenceInstanceDate: date)
    _ = try await importDecision(
      service, id: decisionID, masterID: masterID,
      state: "cancelled", generation: generation)

    _ = try await importBase(service, id: masterID)
    let row = try service.read { db in
      try CalendarTimelineQueries.getCalendarEvent(db, id: masterID)
    }
    XCTAssertEqual(
      try RecurrenceExceptionsRepo.parseExceptionDates(row?.recurrenceExceptions), [date])
  }
}
