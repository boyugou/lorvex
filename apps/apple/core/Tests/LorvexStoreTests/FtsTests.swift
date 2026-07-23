import Foundation
import GRDB
import XCTest

@testable import LorvexStore

final class FtsTests: XCTestCase {

  // -- Canonical SQL pins -------------------------------------------------

  func testTasksTrigramTombstoneSQLIsCanonicalDeleteCommand() {
    let sql = FtsRepo.tasksTrigramTombstoneSQL
    XCTAssertTrue(sql.contains("INSERT INTO tasks_fts_trigram"))
    XCTAssertTrue(sql.contains("(tasks_fts_trigram, rowid, title, body, ai_notes)"))
    XCTAssertTrue(sql.contains("'delete'"))
  }

  func testTasksTrigramInsertSQLIsBareInsert() {
    let sql = FtsRepo.tasksTrigramInsertSQL
    XCTAssertTrue(sql.contains("INSERT INTO tasks_fts_trigram"))
    XCTAssertTrue(sql.contains("(rowid, title, body, ai_notes)"))
    XCTAssertFalse(sql.contains("'delete'"))
  }

  func testCalendarEventsTombstoneSQLIsCanonicalDeleteCommand() {
    let sql = FtsRepo.calendarEventsFtsTombstoneSQL
    XCTAssertTrue(sql.contains("INSERT INTO calendar_events_fts"))
    XCTAssertTrue(sql.contains("(calendar_events_fts, rowid, title, description, location)"))
    XCTAssertTrue(sql.contains("'delete'"))
  }

  func testCalendarEventsInsertSQLIsBareInsert() {
    let sql = FtsRepo.calendarEventsFtsInsertSQL
    XCTAssertTrue(sql.contains("INSERT INTO calendar_events_fts"))
    XCTAssertTrue(sql.contains("(rowid, title, description, location)"))
    XCTAssertFalse(sql.contains("'delete'"))
  }

  func testCalendarEventsOptimizeSQLUsesOptimizeCommand() {
    XCTAssertTrue(FtsRepo.calendarEventsFtsOptimizeSQL.contains("'optimize'"))
    XCTAssertTrue(FtsRepo.calendarEventsFtsOptimizeSQL.contains("calendar_events_fts"))
  }

  // -- Behavioural --------------------------------------------------------

  private func seedTask(
    _ db: Database, id: String, title: String, body: String?
  ) throws {
    // ensure inbox list exists
    try db.execute(
      sql: """
        INSERT OR IGNORE INTO lists (id, name, version, created_at, updated_at) \
        VALUES ('inbox', 'Inbox', '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
        """)
    try db.execute(
      sql: """
        INSERT INTO tasks (id, title, body, version, created_at, updated_at) \
        VALUES (?, ?, ?, '0000000000001_0000_0000000000000001', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
        """,
      arguments: [id, title, body])
  }

  private func trigramMatchCount(_ db: Database, query: String) throws -> Int64 {
    try Int64.fetchOne(
      db,
      sql: "SELECT COUNT(*) FROM tasks_fts_trigram WHERE tasks_fts_trigram MATCH ?",
      arguments: [query]) ?? 0
  }

  private func calendarMatchCount(_ db: Database, query: String) throws -> Int64 {
    try Int64.fetchOne(
      db,
      sql: "SELECT COUNT(*) FROM calendar_events_fts WHERE calendar_events_fts MATCH ?",
      arguments: [query]) ?? 0
  }

  func testTasksTrigramUpsertIsTombstoneThenInsert() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.seedTask(db, id: "t1", title: "写一个中文任务说明", body: "早上好")
      XCTAssertEqual(try self.trigramMatchCount(db, query: "\"中文任务\""), 1)
      let rowid = try Int64.fetchOne(db, sql: "SELECT rowid FROM tasks WHERE id = 't1'")!

      try FtsRepo.dropTasksTrigramTriggers(db)
      try FtsRepo.tasksFtsTrigramUpsert(
        db, rowid: rowid,
        previous: .init(title: "写一个中文任务说明", body: "早上好", aiNotes: nil),
        next: .init(title: "English title only", body: "plain ascii body", aiNotes: nil))

      XCTAssertEqual(try self.trigramMatchCount(db, query: "\"中文任务\""), 0)
      XCTAssertEqual(try self.trigramMatchCount(db, query: "\"plain ascii\""), 1)
    }
  }

  func testTasksTrigramDeleteRemovesPostingsOnly() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.seedTask(db, id: "t1", title: "写一个中文任务说明", body: nil)
      let rowid = try Int64.fetchOne(db, sql: "SELECT rowid FROM tasks WHERE id = 't1'")!
      XCTAssertEqual(try self.trigramMatchCount(db, query: "\"中文任务\""), 1)
      try FtsRepo.dropTasksTrigramTriggers(db)
      _ = try FtsRepo.tasksFtsTrigramDelete(
        db, rowid: rowid,
        previous: .init(title: "写一个中文任务说明", body: nil, aiNotes: nil))
      XCTAssertEqual(try self.trigramMatchCount(db, query: "\"中文任务\""), 0)
      let taskCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tasks WHERE id = 't1'") ?? 0
      XCTAssertEqual(taskCount, 1)
    }
  }

  private func insertCalendarEvent(
    _ db: Database, id: String, title: String,
    description: String? = nil, location: String? = nil
  ) throws {
    try db.execute(
      sql: """
        INSERT INTO calendar_events (
            id, title, description, location,
            start_date, all_day, event_type, recurrence_topology_version,
            content_version, version,
            created_at, updated_at
         ) VALUES (
            ?, ?, ?, ?,
            '2026-01-01', 1, 'event', '0000000000001_0000_0000000000000001',
            '0000000000001_0000_0000000000000001',
            '0000000000001_0000_0000000000000001',
            '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
         )
        """,
      arguments: [id, title, description, location])
  }

  func testCalendarEventsFtsUpsertIsTombstoneThenInsert() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertCalendarEvent(
        db, id: "ev1", title: "Architecture review",
        description: "Design discussion for the planning service",
        location: "Conf room A")
      XCTAssertEqual(try self.calendarMatchCount(db, query: "Architecture"), 1)
      let rowid = try Int64.fetchOne(db, sql: "SELECT rowid FROM calendar_events WHERE id = 'ev1'")!
      try FtsRepo.dropCalendarEventsFtsTriggers(db)
      try FtsRepo.calendarEventsFtsUpsert(
        db, rowid: rowid,
        previous: .init(
          title: "Architecture review",
          description: "Design discussion for the planning service",
          location: "Conf room A"),
        next: .init(
          title: "Sprint planning",
          description: "Backlog grooming",
          location: "Conf room B"))
      XCTAssertEqual(try self.calendarMatchCount(db, query: "Architecture"), 0)
      XCTAssertEqual(try self.calendarMatchCount(db, query: "Sprint"), 1)
    }
  }

  func testInstallTriggersRoundTripsForTasksTrigram() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.seedTask(db, id: "t1", title: "first title", body: nil)
      try FtsRepo.dropTasksTrigramTriggers(db)
      try FtsRepo.installTasksTrigramTriggers(db)
      try db.execute(sql: "UPDATE tasks SET title = '写一个中文任务说明' WHERE id = 't1'")
      XCTAssertEqual(try self.trigramMatchCount(db, query: "\"中文任务\""), 1)
    }
  }

  func testInstallTriggersRoundTripsForCalendarEvents() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertCalendarEvent(db, id: "ev1", title: "First title")
      try FtsRepo.dropCalendarEventsFtsTriggers(db)
      try FtsRepo.installCalendarEventsFtsTriggers(db)
      try db.execute(sql: "UPDATE calendar_events SET title = 'Sprint planning' WHERE id = 'ev1'")
      XCTAssertEqual(try self.calendarMatchCount(db, query: "Sprint"), 1)
    }
  }
}
