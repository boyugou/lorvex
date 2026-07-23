import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync
import XCTest

@testable import LorvexCore

/// Domain importers must not REGRESS a row a peer stamped with a FUTURE HLC. A
/// peer whose clock ran ahead can leave a row versioned far in the future; S-1
/// keeps this device's fresh mint below that stamp. An ungated importer writes
/// its edit BELOW the future version, then emits an outbox envelope below it too,
/// which every peer rejects as stale — the fleet stays divergent with nothing
/// logged. The LWW gate plus the `runWriteAttempt` retry make the imported edit
/// win at a version dominating the future stamp, so the envelope is not stale.
final class SwiftLorvexCoreServiceImportLwwTests: XCTestCase {

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

  // A peer's future HLC: physical ms at the ceiling (~year 2286) under a peer
  // device suffix (not this device's), so the local clock's own-authored seed
  // ignores it and the fresh local mint sits below it (S-1). Bound to a local in
  // each test so the `@Sendable` write closures don't capture `self`.
  private static let futureVersion = "9999913599990_0000_ffffffffffffffff"

  func testImportCalendarEventWinsOverFutureStampedRow() async throws {
    let service = try makeService()
    let futureVersion = Self.futureVersion
    let id = "01966a3f-7c8b-7d4e-8f3a-0000000000c1"
    try service.write { db in
      try db.execute(
        sql: """
          INSERT INTO calendar_events
            (id, title, start_date, all_day, event_type, content_version,
             recurrence_topology_version, version, created_at, updated_at)
          VALUES (?, 'Old', '2026-05-01', 1, 'event', ?, ?, ?, '2026-01-01T00:00:00.000Z',
                  '2026-01-01T00:00:00.000Z')
          """,
        arguments: [id, futureVersion, futureVersion, futureVersion])
    }

    _ = try await service.importCalendarEvent(
      id: id, title: "New title", startDate: "2026-05-01", startTime: nil, endDate: nil,
      endTime: nil, allDay: true, location: nil, notes: nil, url: nil, color: nil,
      eventType: nil, personName: nil, attendees: nil, timezone: nil, recurrence: nil,
      seriesId: nil, recurrenceInstanceDate: nil)

    let future = try Hlc.parse(futureVersion)
    let (title, contentVersion, topologyVersion, rowVersion) = try service.read { db in
      (
        try String.fetchOne(db, sql: "SELECT title FROM calendar_events WHERE id = ?", arguments: [id]),
        try String.fetchOne(
          db, sql: "SELECT content_version FROM calendar_events WHERE id = ?", arguments: [id]),
        try String.fetchOne(
          db, sql: "SELECT recurrence_topology_version FROM calendar_events WHERE id = ?",
          arguments: [id]),
        try String.fetchOne(db, sql: "SELECT version FROM calendar_events WHERE id = ?", arguments: [id])
      )
    }
    XCTAssertEqual(title, "New title", "the imported edit was applied, not dropped")
    let restoredContent = try Hlc.parse(try XCTUnwrap(contentVersion))
    let restoredTopology = try Hlc.parse(try XCTUnwrap(topologyVersion))
    let restoredRow = try Hlc.parse(try XCTUnwrap(rowVersion))
    XCTAssertGreaterThan(restoredContent, future, "restore mints fresh content provenance")
    XCTAssertGreaterThan(restoredTopology, restoredContent, "topology is minted after content")
    XCTAssertGreaterThan(
      restoredRow, restoredTopology,
      "the imported row version strictly dominates every restored register")

    let envelope = try XCTUnwrap(
      service.pendingOutbound().first {
        $0.envelope.entityType == .calendarEvent && $0.envelope.entityId == id
      })
    XCTAssertGreaterThan(
      envelope.envelope.version, future,
      "the emitted envelope dominates the future stamp (not stale)")
  }

  func testImportedDecisionRowVersionStrictlyDominatesPreservedGeneration() async throws {
    let service = try makeService()
    let generation = Self.futureVersion
    let masterID = "01966a3f-7c8b-7d4e-8f3a-0000000000c2"
    let occurrenceDate = "2026-05-02"
    let decisionID = CalendarOccurrenceDecisionID.make(
      seriesId: masterID, recurrenceGeneration: generation,
      recurrenceInstanceDate: occurrenceDate)

    _ = try await service.importCalendarEvent(
      id: decisionID, title: "Cancelled", startDate: occurrenceDate,
      startTime: nil, endDate: nil, endTime: nil, allDay: true,
      location: nil, notes: nil, url: nil, color: nil, eventType: nil,
      personName: nil, attendees: nil, timezone: nil, recurrence: nil,
      seriesId: masterID, recurrenceInstanceDate: occurrenceDate,
      occurrenceState: "cancelled", recurrenceGeneration: generation)

    let row = try service.read { db in
      try XCTUnwrap(CalendarTimelineQueries.getStoredCalendarEvent(db, id: decisionID))
    }
    XCTAssertEqual(row.recurrenceGeneration, generation)
    XCTAssertNil(row.contentVersion)
    XCTAssertNil(row.recurrenceTopologyVersion)
    XCTAssertGreaterThan(try Hlc.parse(row.version), try Hlc.parse(generation))
  }

  func testImportTagWinsOverFutureStampedRowAndAuditsIt() async throws {
    let service = try makeService()
    let futureVersion = Self.futureVersion
    let id = "01966a3f-7c8b-7d4e-8f3a-0000000000d1"
    try service.write { db in
      try db.execute(
        sql: """
          INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at)
          VALUES (?, 'Old', 'old', ?, '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z')
          """,
        arguments: [id, futureVersion])
    }

    try await service.importTag(ExportTag(id: id, displayName: "Renamed"))

    let future = try Hlc.parse(futureVersion)
    let (name, rowVersion, changelogCount) = try service.read { db in
      (
        try String.fetchOne(db, sql: "SELECT display_name FROM tags WHERE id = ?", arguments: [id]),
        try String.fetchOne(db, sql: "SELECT version FROM tags WHERE id = ?", arguments: [id]),
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM ai_changelog WHERE entity_type = 'tag' AND entity_id = ?",
          arguments: [id]) ?? 0
      )
    }
    XCTAssertEqual(name, "Renamed", "the imported edit was applied, not dropped")
    XCTAssertGreaterThan(
      try Hlc.parse(try XCTUnwrap(rowVersion)), future,
      "the imported tag version dominates the future stamp")
    XCTAssertGreaterThanOrEqual(changelogCount, 1, "the tag import wrote an ai_changelog row")

    let envelope = try XCTUnwrap(
      service.pendingOutbound().first {
        $0.envelope.entityType == .tag && $0.envelope.entityId == id
      })
    XCTAssertGreaterThan(envelope.envelope.version, future, "the emitted envelope is not stale")
  }

  func testImportHabitCompletionWinsOverFutureStampedRow() async throws {
    let service = try makeService()
    let futureVersion = Self.futureVersion
    let habitID = "01966a3f-7c8b-7d4e-8f3a-0000000000e1"
    let date = "2026-06-01"
    try service.write { db in
      try db.execute(
        sql: """
          INSERT INTO habits (id, name, version, created_at, updated_at)
          VALUES (?, 'Meditate', '0000000000000_0000_0000000000000000',
                  '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z');
          """,
        arguments: [habitID])
      try db.execute(
        sql: """
          INSERT INTO habit_completions
            (habit_id, completed_date, value, version, created_at, updated_at)
          VALUES (?, ?, 1, ?, '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z')
          """,
        arguments: [habitID, date, futureVersion])
    }

    try await service.importHabitCompletion(
      habitID: habitID,
      completion: ExportHabitCompletion(
        completedDate: date, value: 3, note: nil,
        createdAt: "2026-01-01T00:00:00.000Z", updatedAt: "2026-01-01T00:00:00.000Z"))

    let future = try Hlc.parse(futureVersion)
    let (value, rowVersion) = try service.read { db in
      (
        try Int.fetchOne(
          db, sql: "SELECT value FROM habit_completions WHERE habit_id = ? AND completed_date = ?",
          arguments: [habitID, date]),
        try String.fetchOne(
          db, sql: "SELECT version FROM habit_completions WHERE habit_id = ? AND completed_date = ?",
          arguments: [habitID, date])
      )
    }
    XCTAssertEqual(value, 3, "the imported completion value was applied, not dropped")
    XCTAssertGreaterThan(
      try Hlc.parse(try XCTUnwrap(rowVersion)), future,
      "the imported completion version dominates the future stamp")

    let envelope = try XCTUnwrap(
      service.pendingOutbound().first {
        $0.envelope.entityType == .habitCompletion && $0.envelope.entityId == "\(habitID):\(date)"
      })
    XCTAssertGreaterThan(envelope.envelope.version, future, "the emitted envelope is not stale")
  }
}
