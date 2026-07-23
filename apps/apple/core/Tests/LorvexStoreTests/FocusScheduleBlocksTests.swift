import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

/// Ports `focus_schedule_blocks/tests.rs` verbatim.
final class FocusScheduleBlocksTests: XCTestCase {
  private typealias Repo = FocusScheduleBlocksRepo
  private typealias Entry = FocusScheduleBlocksRepo.ScheduleBlockEntry

  private func insertScheduleHeader(_ db: Database, _ date: String) throws {
    try db.execute(
      sql: """
        INSERT INTO focus_schedule (date, timezone, version, created_at, updated_at) \
        VALUES (?1, 'UTC', '0000000000000_0000_a0a0a0a0a0a0a0a0', \
        '2026-03-27T00:00:00Z', '2026-03-27T00:00:00Z')
        """,
      arguments: [date])
  }

  func testMaterializeInsertsBlocksInOrder() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertScheduleHeader(db, "2026-03-27")
      let blocks = [
        Entry(
          blockType: "task", startMinutes: 540, endMinutes: 600,
          taskId: "01943a6d-b5c8-7e1f-9a12-3456789abcd1",
          title: "Work on feature"),
        Entry(blockType: "buffer", startMinutes: 600, endMinutes: 630, title: "Break"),
      ]
      try Repo.materializeScheduleBlocks(db, date: "2026-03-27", blocks: blocks)

      let count = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM focus_schedule_blocks WHERE date = '2026-03-27'")
      XCTAssertEqual(count, 2)

      let firstType = try String.fetchOne(
        db,
        sql: """
          SELECT block_type FROM focus_schedule_blocks \
          WHERE date = '2026-03-27' ORDER BY position ASC LIMIT 1
          """)
      XCTAssertEqual(firstType, "task")
    }
  }

  func testMaterializeReplacesExistingBlocks() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertScheduleHeader(db, "2026-03-27")
      try Repo.materializeScheduleBlocks(
        db, date: "2026-03-27",
        blocks: [
          Entry(
            blockType: "task", startMinutes: 0, endMinutes: 60,
            taskId: "01943a6d-b5c8-7e1f-9a12-3456789abcd2")
        ])
      try Repo.materializeScheduleBlocks(
        db, date: "2026-03-27",
        blocks: [
          Entry(
            blockType: "event", startMinutes: 120, endMinutes: 180,
            calendarEventId: "01943a6d-b5c8-7e1f-9a12-3456789abcde", eventSource: .canonical,
            title: "Meeting"),
          Entry(
            blockType: "task", startMinutes: 180, endMinutes: 240,
            taskId: "01943a6d-b5c8-7e1f-9a12-3456789abcd3"),
        ])
      let count = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM focus_schedule_blocks WHERE date = '2026-03-27'")
      XCTAssertEqual(count, 2)
    }
  }

  func testMaterializeEmptyClearsAll() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertScheduleHeader(db, "2026-03-27")
      try Repo.materializeScheduleBlocks(
        db, date: "2026-03-27",
        blocks: [
          Entry(
            blockType: "task", startMinutes: 0, endMinutes: 60,
            taskId: "01943a6d-b5c8-7e1f-9a12-3456789abcd4")
        ])
      try Repo.materializeScheduleBlocks(db, date: "2026-03-27", blocks: [])
      let count = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM focus_schedule_blocks WHERE date = '2026-03-27'")
      XCTAssertEqual(count, 0)
    }
  }

  func testMaterializeRejectsZeroLengthAndInvertedIntervals() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertScheduleHeader(db, "2026-03-27")
      try Repo.materializeScheduleBlocks(
        db, date: "2026-03-27",
        blocks: [Entry(blockType: "buffer", startMinutes: 0, endMinutes: 30, title: "Keep")])
      for (start, end) in [(60, 60), (120, 60), (-1, 60), (60, 1441)] {
        XCTAssertThrowsError(
          try Repo.materializeScheduleBlocks(
            db, date: "2026-03-27",
            blocks: [Entry(blockType: "buffer", startMinutes: Int64(start), endMinutes: Int64(end))]))
      }
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM focus_schedule_blocks WHERE date = '2026-03-27'"),
        1)
      XCTAssertEqual(
        try String.fetchOne(
          db,
          sql: "SELECT title FROM focus_schedule_blocks WHERE date = '2026-03-27'"),
        "Keep")
    }
  }

  func testMaterializePrevalidatesAllBlockProvenanceBeforeReplacingExistingRows() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertScheduleHeader(db, "2026-03-27")
      try Repo.materializeScheduleBlocks(
        db, date: "2026-03-27",
        blocks: [Entry(blockType: "buffer", startMinutes: 0, endMinutes: 30, title: "Keep")])

      let invalidBlocks = [
        Entry(
          blockType: "event", startMinutes: 60, endMinutes: 90,
          calendarEventId: "not-a-uuid", eventSource: .canonical, title: "Invalid canonical"),
        Entry(
          blockType: "event", startMinutes: 60, endMinutes: 90,
          calendarEventId: "01943a6d-b5c8-7e1f-9a12-3456789abcde", eventSource: .provider,
          title: "Invalid provider"),
        Entry(blockType: "event", startMinutes: 60, endMinutes: 90, title: "Missing source"),
        Entry(
          blockType: "task", startMinutes: 60, endMinutes: 90, taskId: "not-a-uuid",
          title: "Invalid task identity"),
        Entry(
          blockType: "task", startMinutes: 60, endMinutes: 90,
          taskId: "01943a6d-b5c8-7e1f-9a12-3456789abcd5",
          eventSource: .provider, title: "Invalid task"),
      ]

      for invalidBlock in invalidBlocks {
        XCTAssertThrowsError(
          try Repo.materializeScheduleBlocks(
            db, date: "2026-03-27", blocks: [invalidBlock]))
        XCTAssertEqual(
          try String.fetchOne(
            db,
            sql: "SELECT title FROM focus_schedule_blocks WHERE date = '2026-03-27'"),
          "Keep")
      }
    }
  }

  func testSchemaRejectsNoncanonicalTaskIdentityFromRawSQL() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertScheduleHeader(db, "2026-03-27")
      for taskID in [
        "not-a-uuid",
        "01943A6D-B5C8-7E1F-9A12-3456789ABCD6",
      ] {
        XCTAssertThrowsError(
          try db.execute(
            sql: """
              INSERT INTO focus_schedule_blocks
                (date, position, block_type, start_minutes, end_minutes, task_id)
              VALUES ('2026-03-27', 0, 'task', 60, 90, ?)
              """,
            arguments: [taskID])
        ) { error in
          XCTAssertEqual((error as? DatabaseError)?.resultCode, .SQLITE_CONSTRAINT)
        }
      }

      // The identity remains a soft reference: a canonical UUID can arrive
      // before its task aggregate during arbitrary-order sync apply.
      try db.execute(
        sql: """
          INSERT INTO focus_schedule_blocks
            (date, position, block_type, start_minutes, end_minutes, task_id)
          VALUES ('2026-03-27', 0, 'task', 60, 90,
                  '01943a6d-b5c8-7e1f-9a12-3456789abcd6')
          """)
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM focus_schedule_blocks"), 1)
    }
  }

  func testCanonicalEventCleanupLookupUsesPartialIndex() throws {
    let store = try TestSupport.freshStore()
    try store.writer.read { db in
      let plan = try Row.fetchAll(
        db,
        sql: "EXPLAIN QUERY PLAN SELECT date FROM focus_schedule_blocks WHERE calendar_event_id = ?",
        arguments: ["01943a6d-b5c8-7e1f-9a12-3456789abcde"])
      let planText = plan.map { (($0[3] as String?) ?? "") }.joined(separator: "\n")
      XCTAssertTrue(
        planText.contains("idx_focus_schedule_blocks_calendar_event"),
        "canonical-event cleanup must use the event-reference partial index:\n\(planText)")
    }
  }

  func testUpsertHeaderSetsTimezoneOnCreate() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try Repo.upsertFocusScheduleHeader(
        db, date: "2026-03-27", rationale: "Morning plan", timezone: "America/New_York",
        version: "0000000000001_0000_0000000000000001", now: "2026-03-27T08:00:00Z")
      let row = try Row.fetchOne(
        db,
        sql: "SELECT timezone, rationale FROM focus_schedule WHERE date = '2026-03-27'")!
      XCTAssertEqual(row[0], "America/New_York")
      XCTAssertEqual(row[1], "Morning plan")
    }
  }

  func testUpsertHeaderPreservesTimezoneOnUpdate() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try Repo.upsertFocusScheduleHeader(
        db, date: "2026-03-27", rationale: "First", timezone: "America/New_York",
        version: "0000000000001_0000_0000000000000001", now: "2026-03-27T08:00:00Z")
      try Repo.upsertFocusScheduleHeader(
        db, date: "2026-03-27", rationale: "Updated rationale", timezone: "Asia/Tokyo",
        version: "0000000000002_0000_0000000000000002", now: "2026-03-27T12:00:00Z")
      let row = try Row.fetchOne(
        db,
        sql:
          "SELECT timezone, rationale, version FROM focus_schedule WHERE date = '2026-03-27'")!
      XCTAssertEqual(row[0], "America/New_York")
      XCTAssertEqual(row[1], "Updated rationale")
      XCTAssertEqual(row[2], "0000000000002_0000_0000000000000002")
    }
  }

  func testUpsertFocusScheduleHeaderLwwGateRejectsStaleVersion() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      let applied1 = try Repo.upsertFocusScheduleHeader(
        db, date: "2026-04-26", rationale: "winning rationale",
        timezone: "America/New_York",
        version: "0002000000000_0001_a000000000000001", now: "2026-04-26T08:00:00Z")
      XCTAssertTrue(applied1)

      let applied2 = try Repo.upsertFocusScheduleHeader(
        db, date: "2026-04-26", rationale: "stale rationale",
        timezone: "America/New_York",
        version: "0001000000000_0001_b000000000000001", now: "2026-04-26T09:00:00Z")
      XCTAssertFalse(applied2)

      let row = try Row.fetchOne(
        db,
        sql:
          "SELECT rationale, version, updated_at FROM focus_schedule WHERE date = '2026-04-26'")!
      XCTAssertEqual(row[0], "winning rationale")
      XCTAssertEqual(row[1], "0002000000000_0001_a000000000000001")
      XCTAssertEqual(row[2], "2026-04-26T08:00:00Z")
    }
  }

  private func seedBaseline(_ db: Database, _ date: String, _ version: String) throws {
    try db.execute(
      sql: """
        INSERT INTO focus_schedule (date, rationale, timezone, version, created_at, updated_at) \
        VALUES (?1, 'baseline', 'UTC', ?2, '2026-04-19T08:00:00Z', '2026-04-19T08:00:00Z')
        """,
      arguments: [date, version])
  }

  private func readState(_ db: Database, _ date: String) throws -> (String?, String) {
    let row = try Row.fetchOne(
      db, sql: "SELECT rationale, version FROM focus_schedule WHERE date = ?1",
      arguments: [date])!
    return (row[0], row[1])
  }

  func testSyncVersionCmpGreaterRejectsEqualAndLowerVersions() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.seedBaseline(db, "2026-04-19", "0001000000000_0001_de1cea0000000000")

      var written = try Repo.syncUpsertFocusSchedule(
        db, date: "2026-04-19", rationale: "attempted-equal", timezone: "UTC",
        version: "0001000000000_0001_de1cea0000000000", createdAt: "2026-04-19T09:00:00Z",
        updatedAt: "2026-04-19T09:00:00Z", versionCmp: .greater)
      XCTAssertFalse(written)
      var state = try self.readState(db, "2026-04-19")
      XCTAssertEqual(state.0, "baseline")
      XCTAssertEqual(state.1, "0001000000000_0001_de1cea0000000000")

      written = try Repo.syncUpsertFocusSchedule(
        db, date: "2026-04-19", rationale: "attempted-older", timezone: "UTC",
        version: "0000999999999_0001_de1cea0000000000", createdAt: "2026-04-19T09:00:00Z",
        updatedAt: "2026-04-19T09:00:00Z", versionCmp: .greater)
      XCTAssertFalse(written)

      written = try Repo.syncUpsertFocusSchedule(
        db, date: "2026-04-19", rationale: "newer-wins", timezone: "UTC",
        version: "0001000000001_0001_de1cea0000000000", createdAt: "2026-04-19T09:00:00Z",
        updatedAt: "2026-04-19T09:00:00Z", versionCmp: .greater)
      XCTAssertTrue(written)
      state = try self.readState(db, "2026-04-19")
      XCTAssertEqual(state.0, "newer-wins")
      XCTAssertEqual(state.1, "0001000000001_0001_de1cea0000000000")
    }
  }

  func testSyncVersionCmpGreaterOrEqualAcceptsEqualVersionReplay() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.seedBaseline(db, "2026-04-20", "0001000000000_0001_de1cea0000000000")

      var written = try Repo.syncUpsertFocusSchedule(
        db, date: "2026-04-20", rationale: "rehydrated", timezone: "UTC",
        version: "0001000000000_0001_de1cea0000000000", createdAt: "2026-04-19T09:00:00Z",
        updatedAt: "2026-04-19T09:00:00Z", versionCmp: .greaterOrEqual)
      XCTAssertTrue(written)
      let state = try self.readState(db, "2026-04-20")
      XCTAssertEqual(state.0, "rehydrated")
      XCTAssertEqual(state.1, "0001000000000_0001_de1cea0000000000")

      written = try Repo.syncUpsertFocusSchedule(
        db, date: "2026-04-20", rationale: "attempted-older", timezone: "UTC",
        version: "0000999999999_0001_de1cea0000000000", createdAt: "2026-04-19T09:00:00Z",
        updatedAt: "2026-04-19T09:00:00Z", versionCmp: .greaterOrEqual)
      XCTAssertFalse(written)
    }
  }

  func testSyncVersionCmpAsSqlEmitsStaticSafeOperators() {
    XCTAssertEqual(FocusScheduleBlocksRepo.SyncVersionCmp.greater.asSql, ">")
    XCTAssertEqual(FocusScheduleBlocksRepo.SyncVersionCmp.greaterOrEqual.asSql, ">=")
  }
}
