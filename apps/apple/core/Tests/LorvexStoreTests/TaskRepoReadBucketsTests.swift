import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

/// Ports the bucket / today / upcoming / overdue read tests under
/// `repositories/task/read/tests/` plus the deferred read contracts.
final class TaskRepoReadBucketsTests: XCTestCase {

  private func ymd(_ y: Int, _ m: Int, _ d: Int) -> IsoDate.YMD {
    IsoDate.YMD(year: y, month: m, day: d)
  }

  /// Mirrors the Rust `insert_task(id, title, status, due_date,
  /// planned_date, priority, list_id)` helper. `listId` defaults to the
  /// schema-seeded `inbox` list.
  private func insertTask(
    _ db: Database,
    _ id: String,
    _ title: String,
    _ status: String,
    dueDate: String? = nil,
    plannedDate: String? = nil,
    priority: Int64? = nil,
    listId: String = "inbox"
  ) throws {
    try db.execute(
      sql: """
        INSERT INTO tasks (id, title, status, due_date, planned_date, priority, list_id, \
        version, created_at, updated_at, completed_at, defer_count) \
        VALUES (?, ?, ?, ?, ?, ?, ?, \
        '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00.000Z', \
        '2026-01-01T00:00:00.000Z', CASE WHEN ? = 'completed' \
        THEN '2026-01-01T00:00:00.000Z' END, 0)
        """,
      arguments: [id, title, status, dueDate, plannedDate, priority, listId, status])
  }

  private func ids(_ rows: [TaskRow]) -> [String] { rows.map { $0.core.id } }

  // MARK: - Today

  func testTodayReturnsPlannedDateLteToday() throws {
    let store = try TestSupport.freshStore()
    let rows = try store.writer.write { db -> [TaskRow] in
      try self.insertTask(db, "t1", "Planned today", "open", plannedDate: "2026-03-23", priority: 2)
      try self.insertTask(
        db, "t2", "Planned yesterday", "open", plannedDate: "2026-03-22", priority: 1)
      try self.insertTask(
        db, "t3", "Planned tomorrow", "open", plannedDate: "2026-03-24", priority: 1)
      return try TaskRepo.Read.getTodayTasks(
        db, predicate: TodayPredicate(date: self.ymd(2026, 3, 23)), page: .default)
    }
    let i = ids(rows)
    XCTAssertTrue(i.contains("t1"))
    XCTAssertTrue(i.contains("t2"))
    XCTAssertFalse(i.contains("t3"))
  }

  func testTodayReturnsDueDateWhenNoPlannedDate() throws {
    let store = try TestSupport.freshStore()
    let rows = try store.writer.write { db -> [TaskRow] in
      try self.insertTask(db, "t1", "Due today", "open", dueDate: "2026-03-23", priority: 1)
      try self.insertTask(db, "t2", "Due tomorrow", "open", dueDate: "2026-03-24", priority: 1)
      return try TaskRepo.Read.getTodayTasks(
        db, predicate: TodayPredicate(date: self.ymd(2026, 3, 23)), page: .default)
    }
    let i = ids(rows)
    XCTAssertTrue(i.contains("t1"))
    XCTAssertFalse(i.contains("t2"))
  }

  func testTodayExcludesCompletedTasks() throws {
    let store = try TestSupport.freshStore()
    let rows = try store.writer.write { db -> [TaskRow] in
      try self.insertTask(
        db, "t1", "Completed task", "completed", dueDate: "2026-03-23", priority: 1)
      return try TaskRepo.Read.getTodayTasks(
        db, predicate: TodayPredicate(date: self.ymd(2026, 3, 23)), page: .default)
    }
    XCTAssertTrue(rows.isEmpty)
  }

  func testTodayExcludesDeadlineOverdue() throws {
    let store = try TestSupport.freshStore()
    let rows = try store.writer.write { db -> [TaskRow] in
      try self.insertTask(db, "t1", "Overdue task", "open", dueDate: "2026-03-20", priority: 1)
      return try TaskRepo.Read.getTodayTasks(
        db, predicate: TodayPredicate(date: self.ymd(2026, 3, 23)), page: .default)
    }
    XCTAssertTrue(rows.isEmpty)
  }

  func testTodayOrdersByIdAscWhenPriorityAndDueDateTie() throws {
    let store = try TestSupport.freshStore()
    let rows = try store.writer.write { db -> [TaskRow] in
      try self.insertTask(db, "task-charlie", "C", "open", dueDate: "2026-03-23", priority: 1)
      try self.insertTask(db, "task-bravo", "B", "open", dueDate: "2026-03-23", priority: 1)
      try self.insertTask(db, "task-alpha", "A", "open", dueDate: "2026-03-23", priority: 1)
      return try TaskRepo.Read.getTodayTasks(
        db, predicate: TodayPredicate(date: self.ymd(2026, 3, 23)), page: .default)
    }
    XCTAssertEqual(ids(rows), ["task-alpha", "task-bravo", "task-charlie"])
  }

  // MARK: - Upcoming

  func testUpcomingReturnsTasksInRange() throws {
    let store = try TestSupport.freshStore()
    let rows = try store.writer.write { db -> [TaskRow] in
      try self.insertTask(db, "t1", "In range planned", "open", plannedDate: "2026-03-25", priority: 1)
      try self.insertTask(db, "t2", "In range due", "open", dueDate: "2026-03-26", priority: 1)
      try self.insertTask(db, "t3", "Out of range", "open", dueDate: "2026-04-05", priority: 1)
      try self.insertTask(db, "t4", "Before range", "open", dueDate: "2026-03-22", priority: 1)
      return try TaskRepo.Read.getUpcomingTasks(
        db, predicate: UpcomingPredicate(fromDate: self.ymd(2026, 3, 23), days: 7),
        page: .default)
    }
    let i = ids(rows)
    XCTAssertTrue(i.contains("t1"))
    XCTAssertTrue(i.contains("t2"))
    XCTAssertFalse(i.contains("t3"))
    XCTAssertFalse(i.contains("t4"))
  }

  func testUpcomingExcludesNonOpen() throws {
    let store = try TestSupport.freshStore()
    let rows = try store.writer.write { db -> [TaskRow] in
      try self.insertTask(
        db, "t1", "Cancelled in range", "cancelled", dueDate: "2026-03-25", priority: 1)
      return try TaskRepo.Read.getUpcomingTasks(
        db, predicate: UpcomingPredicate(fromDate: self.ymd(2026, 3, 23), days: 7),
        page: .default)
    }
    XCTAssertTrue(rows.isEmpty)
  }

  // MARK: - Open task day buckets

  func testCountOpenTaskDayBucketsMatchesCanonicalBucketQueries() throws {
    let store = try TestSupport.freshStore()
    let counts = try store.writer.write { db -> TaskRepo.Read.OpenTaskDayBucketCounts in
      try self.insertTask(db, "overdue", "Overdue", "open", dueDate: "2026-03-20", priority: 1)
      try self.insertTask(
        db, "past-planned", "Past planned", "open", dueDate: "2026-03-26",
        plannedDate: "2026-03-20", priority: 2)
      try self.insertTask(db, "due-today", "Due today", "open", dueDate: "2026-03-23", priority: 3)
      try self.insertTask(db, "upcoming", "Upcoming", "open", dueDate: "2026-03-27", priority: 1)
      return try TaskRepo.Read.countOpenTaskDayBuckets(
        db, asOfDate: self.ymd(2026, 3, 23), upcomingDays: 7)
    }
    XCTAssertEqual(
      counts,
      TaskRepo.Read.OpenTaskDayBucketCounts(overdue: 1, todayPool: 2, upcoming: 1))
  }

  // MARK: - Deferred

  func testDeferredReturnsOnlyDeferredOpenTasks() throws {
    let store = try TestSupport.freshStore()
    let rows = try store.writer.write { db -> [TaskRow] in
      try self.insertTask(db, "d1", "Deferred twice", "open", priority: 1)
      try self.insertTask(db, "d2", "Deferred once", "open", priority: 1)
      try self.insertTask(db, "open-none", "Never deferred", "open", priority: 1)
      try self.insertTask(db, "done", "Deferred but completed", "completed", priority: 1)
      try db.execute(sql: "UPDATE tasks SET defer_count = 3 WHERE id = 'd1'")
      try db.execute(sql: "UPDATE tasks SET defer_count = 1 WHERE id = 'd2'")
      try db.execute(sql: "UPDATE tasks SET defer_count = 5 WHERE id = 'done'")
      return try TaskRepo.Read.getDeferredTasks(db, page: .default)
    }
    // Ordered by defer_count DESC, id ASC; completed excluded.
    XCTAssertEqual(ids(rows), ["d1", "d2"])
  }

  func testDeferredScopesToListWhenProvided() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try db.execute(
        sql: """
          INSERT INTO lists (id, name, version, created_at, updated_at) \
          VALUES ('other', 'Other', '0000000000000_0000_0000000000000000', \
          '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z')
          """)
      try self.insertTask(db, "in-inbox", "Inbox deferred", "open", priority: 1)
      try self.insertTask(db, "in-other", "Other deferred", "open", priority: 1, listId: "other")
      try db.execute(sql: "UPDATE tasks SET defer_count = 1 WHERE id IN ('in-inbox', 'in-other')")
    }
    try store.writer.read { db in
      let scoped = try TaskRepo.Read.getDeferredTasks(db, listId: "other", page: .default)
      XCTAssertEqual(self.ids(scoped), ["in-other"])
      XCTAssertEqual(try TaskRepo.Read.countDeferredTasks(db, listId: "other"), 1)
      XCTAssertEqual(try TaskRepo.Read.countDeferredTasks(db), 2)
    }
  }

}
