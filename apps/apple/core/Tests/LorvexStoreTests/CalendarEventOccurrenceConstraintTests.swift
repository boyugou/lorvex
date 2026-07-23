import GRDB
import XCTest

@testable import LorvexStore

final class CalendarEventOccurrenceConstraintTests: XCTestCase {
  private let generation = "1800000000000_0001_1111111111111111"
  private let nextGeneration = "1800000000001_0000_2222222222222222"
  private let topology = "1800000000000_0002_3333333333333333"
  private let rowVersion = "1800000000002_0000_4444444444444444"

  private func insert(
    _ db: Database,
    id: String,
    recurrence: String?,
    seriesId: String?,
    instanceDate: String?,
    state: String?,
    generation: String?,
    topology: String?
  ) throws {
    try db.execute(
      sql: """
        INSERT INTO calendar_events
          (id, title, start_date, start_time, all_day, recurrence, series_id,
           recurrence_instance_date, occurrence_state, recurrence_generation,
           recurrence_topology_version, content_version, event_type, version,
           created_at, updated_at)
        VALUES (?, 'Standup', '2026-06-22', '09:00', 0, ?, ?, ?, ?, ?, ?, ?, 'event', ?,
                '2026-06-22T00:00:00.000Z', '2026-06-22T00:00:00.000Z')
        """,
      arguments: [
        id, recurrence, seriesId, instanceDate, state, generation, topology,
        seriesId == nil ? topology : nil, rowVersion,
      ])
  }

  func testEveryLegalRowShapeCanCoexist() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try insert(
        db, id: "plain", recurrence: nil, seriesId: nil, instanceDate: nil,
        state: nil, generation: nil, topology: topology)
      try insert(
        db, id: "master", recurrence: #"{"FREQ":"DAILY"}"#, seriesId: nil,
        instanceDate: nil, state: nil, generation: generation, topology: topology)
      for state in ["replacement", "cancelled", "inherit"] {
        try insert(
          db, id: "decision-\(state)", recurrence: nil, seriesId: "master",
          instanceDate: "2026-06-\(state == "replacement" ? "23" : state == "cancelled" ? "24" : "25")",
          state: state, generation: generation, topology: nil)
      }
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM calendar_events"), 5)
    }
  }

  func testDuplicateDecisionRegisterIsRejectedButNewGenerationIsIndependent() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try insert(
        db, id: "first", recurrence: nil, seriesId: "master",
        instanceDate: "2026-06-23", state: "replacement",
        generation: generation, topology: nil)
      XCTAssertThrowsError(
        try insert(
          db, id: "duplicate", recurrence: nil, seriesId: "master",
          instanceDate: "2026-06-23", state: "cancelled",
          generation: generation, topology: nil))
      XCTAssertNoThrow(
        try insert(
          db, id: "new-generation", recurrence: nil, seriesId: "master",
          instanceDate: "2026-06-23", state: "inherit",
          generation: nextGeneration, topology: nil))
    }
  }

  func testDecisionMayArriveBeforeMaster() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try insert(
        db, id: "decision", recurrence: nil, seriesId: "missing-master",
        instanceDate: "2026-06-23", state: "cancelled",
        generation: generation, topology: nil)
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM calendar_events"), 1)
    }
  }

  func testIllegalShapeCombinationsAreRejected() throws {
    let cases: [(String?, String?, String?, String?, String?, String?)] = [
      // plain base without topology; plain base carrying generation
      (nil, nil, nil, nil, nil, nil),
      (nil, nil, nil, nil, generation, topology),
      // recurring master without generation or topology
      (#"{"FREQ":"DAILY"}"#, nil, nil, nil, nil, topology),
      (#"{"FREQ":"DAILY"}"#, nil, nil, nil, generation, nil),
      // decision missing state/generation, or carrying recurrence/topology
      (nil, "master", "2026-06-23", nil, generation, nil),
      (nil, "master", "2026-06-23", "cancelled", nil, nil),
      (#"{"FREQ":"DAILY"}"#, "master", "2026-06-23", "replacement", generation, nil),
      (nil, "master", "2026-06-23", "replacement", generation, topology),
      // half linkage
      (nil, "master", nil, "replacement", generation, nil),
      (nil, nil, "2026-06-23", "replacement", generation, nil),
    ]
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      for (index, fields) in cases.enumerated() {
        XCTAssertThrowsError(
          try insert(
            db, id: "bad-\(index)", recurrence: fields.0, seriesId: fields.1,
            instanceDate: fields.2, state: fields.3, generation: fields.4,
            topology: fields.5),
          "case \(index) must violate the row-shape CHECK")
      }
    }
  }

  func testStateDateAndHlcChecksRejectNoncanonicalValues() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertThrowsError(
        try insert(
          db, id: "bad-state", recurrence: nil, seriesId: "master",
          instanceDate: "2026-06-23", state: "deleted",
          generation: generation, topology: nil))
      XCTAssertThrowsError(
        try insert(
          db, id: "bad-date", recurrence: nil, seriesId: "master",
          instanceDate: "2026-02-30", state: "cancelled",
          generation: generation, topology: nil))
      XCTAssertThrowsError(
        try insert(
          db, id: "bad-generation", recurrence: nil, seriesId: "master",
          instanceDate: "2026-06-23", state: "cancelled",
          generation: "1800000000000_1_ABCDEFABCDEFABCD", topology: nil))
      XCTAssertThrowsError(
        try insert(
          db, id: "bad-topology", recurrence: nil, seriesId: nil,
          instanceDate: nil, state: nil, generation: nil,
          topology: "1800000000000_1_ABCDEFABCDEFABCD"))
    }
  }

  func testOnlyTaskExdateRegistryRemains() throws {
    let store = try TestSupport.freshStore()
    try store.writer.read { db in
      XCTAssertNotNil(
        try String.fetchOne(
          db, sql: "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
          arguments: ["task_recurrence_exceptions"]))
      XCTAssertNil(
        try String.fetchOne(
          db, sql: "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
          arguments: ["calendar_event_recurrence_exceptions"]))
    }
  }

  func testTaskCalendarLinksRejectDecisionTargetsAndLinkedBaseIdentityChanges() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try insert(
        db, id: "base", recurrence: #"{"FREQ":"DAILY"}"#, seriesId: nil,
        instanceDate: nil, state: nil, generation: generation, topology: topology)
      try insert(
        db, id: "decision", recurrence: nil, seriesId: "base",
        instanceDate: "2026-06-23", state: "replacement",
        generation: generation, topology: nil)
      for taskID in ["task-1", "task-2"] {
        try db.execute(
          sql: """
            INSERT INTO tasks (id, title, version, created_at, updated_at)
            VALUES (?, 'Linked task', ?, '2026-06-22T00:00:00.000Z',
                    '2026-06-22T00:00:00.000Z')
            """,
          arguments: [taskID, rowVersion])
      }
      try db.execute(
        sql: """
          INSERT INTO task_calendar_event_links
            (task_id, calendar_event_id, version, created_at, updated_at)
          VALUES ('task-1', 'base', ?, '2026-06-22T00:00:00.000Z',
                  '2026-06-22T00:00:00.000Z')
          """,
        arguments: [rowVersion])

      XCTAssertThrowsError(
        try db.execute(
          sql: """
            INSERT INTO task_calendar_event_links
              (task_id, calendar_event_id, version, created_at, updated_at)
            VALUES ('task-2', 'decision', ?, '2026-06-22T00:00:00.000Z',
                    '2026-06-22T00:00:00.000Z')
            """,
          arguments: [rowVersion])) { error in
            XCTAssertTrue("\(error)".contains("must target a base calendar event"))
          }
      XCTAssertThrowsError(
        try db.execute(
          sql: """
            UPDATE task_calendar_event_links
            SET calendar_event_id = 'decision'
            WHERE task_id = 'task-1' AND calendar_event_id = 'base'
            """)) { error in
              XCTAssertTrue("\(error)".contains("must target a base calendar event"))
            }
      XCTAssertThrowsError(
        try db.execute(
          sql: """
            UPDATE calendar_events
            SET recurrence = NULL,
                series_id = 'other-master',
                recurrence_instance_date = '2026-06-24',
                occurrence_state = 'cancelled',
                recurrence_generation = ?,
                recurrence_topology_version = NULL,
                content_version = NULL
            WHERE id = 'base'
            """,
          arguments: [generation])) { error in
            XCTAssertTrue("\(error)".contains("cannot become an occurrence decision"))
          }
    }
  }
}
