import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync
import XCTest

@testable import LorvexCore

final class CalendarEventRegisterIntentProvenanceTests: XCTestCase {
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

  private func intent(
    _ service: SwiftLorvexCoreService, eventID: String
  ) throws -> Int64 {
    try service.read { db in
      try XCTUnwrap(
        Int64.fetchOne(
          db,
          sql: """
            SELECT register_intent FROM sync_outbox
            WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
            """,
          arguments: [EntityName.calendarEvent, eventID]))
    }
  }

  private func clearEventOutbox(
    _ service: SwiftLorvexCoreService, eventID: String
  ) throws {
    try service.write { db in
      try db.execute(
        sql: "DELETE FROM sync_outbox WHERE entity_type = ? AND entity_id = ?",
        arguments: [EntityName.calendarEvent, eventID])
    }
  }

  func testWorkflowInferenceAndNativeImportPersistExactRegisterProvenance() async throws {
    let service = try makeService()
    let created = try await service.createCalendarEvent(
      title: "Planning", startDate: "2026-08-01", endDate: "2026-08-01",
      startTime: "09:00", endTime: "10:00", allDay: false,
      location: nil, notes: nil)
    XCTAssertEqual(try intent(service, eventID: created.id), CalendarEventRegisterIntent.all.rawValue)

    try clearEventOutbox(service, eventID: created.id)
    _ = try await service.updateCalendarEvent(
      id: created.id, title: "Renamed planning", startDate: nil, endDate: nil,
      startTime: nil, endTime: nil, allDay: nil, location: nil, notes: nil,
      recurrence: .unset, timezone: nil, url: nil, color: nil, eventType: nil,
      personName: nil, attendees: .unset)
    XCTAssertEqual(
      try intent(service, eventID: created.id), CalendarEventRegisterIntent.content.rawValue)

    try clearEventOutbox(service, eventID: created.id)
    _ = try await service.updateCalendarEvent(
      id: created.id, title: nil, startDate: nil, endDate: nil,
      startTime: "09:30", endTime: nil, allDay: nil, location: nil, notes: nil,
      recurrence: .unset, timezone: nil, url: nil, color: nil, eventType: nil,
      personName: nil, attendees: .unset)
    XCTAssertEqual(
      try intent(service, eventID: created.id), CalendarEventRegisterIntent.topology.rawValue)

    try clearEventOutbox(service, eventID: created.id)
    _ = try await service.updateCalendarEvent(
      id: created.id, title: "Renamed planning", startDate: nil, endDate: nil,
      startTime: nil, endTime: nil, allDay: nil, location: nil, notes: nil,
      recurrence: .unset, timezone: nil, url: nil, color: nil, eventType: nil,
      personName: nil, attendees: .unset)
    XCTAssertEqual(try intent(service, eventID: created.id), 0)

    let importedID = UUID().uuidString.lowercased()
    _ = try await service.importCalendarEvent(
      id: importedID, title: "Imported", startDate: "2026-08-02",
      startTime: "11:00", endDate: "2026-08-02", endTime: "12:00",
      allDay: false, location: nil)
    XCTAssertEqual(
      try intent(service, eventID: importedID), CalendarEventRegisterIntent.all.rawValue)
    let clocks = try service.read { db in
      try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: """
            SELECT content_version, recurrence_topology_version, version
            FROM calendar_events WHERE id = ?
            """,
          arguments: [importedID]))
    }
    XCTAssertNotEqual(clocks["content_version"] as String, clocks["version"] as String)
    XCTAssertNotEqual(clocks["recurrence_topology_version"] as String, clocks["version"] as String)
  }
}
