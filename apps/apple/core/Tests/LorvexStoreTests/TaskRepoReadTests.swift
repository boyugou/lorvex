import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

final class TaskRepoReadTests: XCTestCase {

  private func tid(_ id: String) -> TaskId { TaskId(trusted: id) }

  /// Insert a minimal task. `listId` defaults to the schema-seeded `inbox`
  /// so callers don't have to thread a fresh list through every test.
  private func insertTask(
    _ db: Database,
    id: String,
    title: String = "task",
    status: String = "open",
    listId: String = "inbox",
    priority: Int64? = nil,
    dueDate: String? = nil,
    plannedDate: String? = nil,
    completedAt: String? = nil,
    archivedAt: String? = nil,
    createdAt: String = "2026-01-01T00:00:00.000Z",
    updatedAt: String = "2026-01-01T00:00:00.000Z"
  ) throws {
    let resolvedCompletedAt = status == StatusName.completed ? (completedAt ?? updatedAt) : nil
    try db.execute(
      sql: """
        INSERT INTO tasks (id, title, status, list_id, priority, due_date, \
                           planned_date, completed_at, archived_at, version, \
                           created_at, updated_at, defer_count) \
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, \
                '0000000000000_0000_0000000000000000', ?, ?, 0)
        """,
      arguments: [
        id, title, status, listId, priority, dueDate,
        plannedDate, resolvedCompletedAt, archivedAt, createdAt, updatedAt,
      ])
  }

  // MARK: - getTask

  func testGetTaskReturnsRowWithDecomposedSubStructs() throws {
    let store = try TestSupport.freshStore()
    let row = try store.writer.write { db -> TaskRow? in
      try self.insertTask(
        db, id: "t1", title: "Buy milk", priority: 2,
        dueDate: "2026-04-10", plannedDate: "2026-04-09")
      return try TaskRepo.Read.getTask(db, taskId: self.tid("t1"))
    }
    let task = try XCTUnwrap(row)
    XCTAssertEqual(task.core.id, "t1")
    XCTAssertEqual(task.core.title, "Buy milk")
    XCTAssertEqual(task.core.status, "open")
    XCTAssertEqual(task.core.listId, "inbox")
    XCTAssertEqual(task.core.priority, 2)
    XCTAssertEqual(task.core.version, "0000000000000_0000_0000000000000000")
    XCTAssertEqual(task.scheduling.dueDate?.asString, "2026-04-10")
    XCTAssertEqual(task.scheduling.plannedDate?.asString, "2026-04-09")
    XCTAssertEqual(task.scheduling.deferCount, 0)
    XCTAssertNil(task.scheduling.estimatedMinutes)
    XCTAssertNil(task.lifecycle.completedAt)
    XCTAssertNil(task.lifecycle.archivedAt)
    XCTAssertNil(task.recurrence.recurrence)
    XCTAssertNil(task.recurrence.recurrenceExceptions)
  }

  func testGetTaskReturnsNilForMissingId() throws {
    let store = try TestSupport.freshStore()
    let row = try store.writer.read { db in
      try TaskRepo.Read.getTask(db, taskId: self.tid("missing"))
    }
    XCTAssertNil(row)
  }

  func testGetTaskIncludesTrashedRows() throws {
    let store = try TestSupport.freshStore()
    let row = try store.writer.write { db -> TaskRow? in
      try self.insertTask(db, id: "t1", archivedAt: "2026-04-01T00:00:00.000Z")
      return try TaskRepo.Read.getTask(db, taskId: self.tid("t1"))
    }
    let task = try XCTUnwrap(row)
    XCTAssertEqual(task.lifecycle.archivedAt, "2026-04-01T00:00:00.000Z")
  }

  func testGetTaskUnscheduledDueShape() throws {
    let store = try TestSupport.freshStore()
    let row = try store.writer.write { db -> TaskRow? in
      try self.insertTask(db, id: "t1")
      return try TaskRepo.Read.getTask(db, taskId: self.tid("t1"))
    }
    let task = try XCTUnwrap(row)
    XCTAssertNil(task.scheduling.dueDate)
  }

  func testGetTaskOnDayDueShape() throws {
    let store = try TestSupport.freshStore()
    let row = try store.writer.write { db -> TaskRow? in
      try self.insertTask(db, id: "t1", dueDate: "2026-04-10")
      return try TaskRepo.Read.getTask(db, taskId: self.tid("t1"))
    }
    let task = try XCTUnwrap(row)
    XCTAssertEqual(task.scheduling.dueDate?.asString, "2026-04-10")
  }

  // MARK: - taskExistsActive

  func testTaskExistsActiveTrueForActiveTask() throws {
    let store = try TestSupport.freshStore()
    let exists = try store.writer.write { db -> Bool in
      try self.insertTask(db, id: "t1")
      return try TaskRepo.Read.taskExistsActive(db, taskId: self.tid("t1"))
    }
    XCTAssertTrue(exists)
  }

  func testTaskExistsActiveFalseForMissingId() throws {
    let store = try TestSupport.freshStore()
    let exists = try store.writer.read { db in
      try TaskRepo.Read.taskExistsActive(db, taskId: self.tid("nope"))
    }
    XCTAssertFalse(exists)
  }

  func testTaskExistsActiveFalseForTrashedRow() throws {
    let store = try TestSupport.freshStore()
    let exists = try store.writer.write { db -> Bool in
      try self.insertTask(db, id: "t1", archivedAt: "2026-04-01T00:00:00.000Z")
      return try TaskRepo.Read.taskExistsActive(db, taskId: self.tid("t1"))
    }
    XCTAssertFalse(exists)
  }

  // MARK: - getOpenTasksByPriority

  func testGetOpenTasksByPriorityOrdersByEffectivePriorityThenDueThenId() throws {
    let store = try TestSupport.freshStore()
    let rows = try store.writer.write { db -> [TaskRow] in
      // Mix of priorities + due dates to exercise the full ORDER BY key.
      try self.insertTask(db, id: "a", priority: 3, dueDate: "2026-04-12")
      try self.insertTask(db, id: "b", priority: 1, dueDate: "2026-04-20")
      try self.insertTask(db, id: "c", priority: 1, dueDate: "2026-04-15")
      // No-priority should sort last (priority_effective sentinel = 4).
      try self.insertTask(db, id: "d", dueDate: "2026-04-01")
      try self.insertTask(db, id: "e", priority: 2)
      return try TaskRepo.Read.getOpenTasksByPriority(db, today: "2026-04-01", limit: 100)
    }
    XCTAssertEqual(rows.map(\.core.id), ["c", "b", "e", "a", "d"])
  }

  func testGetOpenTasksByPriorityFiltersByStatusAndArchive() throws {
    let store = try TestSupport.freshStore()
    let rows = try store.writer.write { db -> [TaskRow] in
      try self.insertTask(db, id: "open1", priority: 1)
      try self.insertTask(db, id: "done", status: "completed", priority: 1)
      try self.insertTask(db, id: "cancelled", status: "cancelled", priority: 1)
      try self.insertTask(db, id: "someday", status: "someday", priority: 1)
      try self.insertTask(
        db, id: "trashed", priority: 1, archivedAt: "2026-04-01T00:00:00.000Z")
      return try TaskRepo.Read.getOpenTasksByPriority(db, today: "2026-04-01", limit: 100)
    }
    XCTAssertEqual(rows.map(\.core.id), ["open1"])
  }

  func testGetOpenTasksByPriorityRespectsLimit() throws {
    let store = try TestSupport.freshStore()
    let rows = try store.writer.write { db -> [TaskRow] in
      for i in 1...5 {
        try self.insertTask(db, id: "t\(i)", priority: 1)
      }
      return try TaskRepo.Read.getOpenTasksByPriority(db, today: "2026-04-01", limit: 2)
    }
    XCTAssertEqual(rows.count, 2)
    // `id ASC` tiebreaker — first two ids alphabetically.
    XCTAssertEqual(rows.map(\.core.id), ["t1", "t2"])
  }

  // MARK: - getRecentlyCompletedTasks

  func testGetRecentlyCompletedTasksOrdersByCompletedAtDescThenIdAsc() throws {
    let store = try TestSupport.freshStore()
    let rows = try store.writer.write { db -> [TaskRow] in
      try self.insertTask(
        db, id: "a", status: "completed", completedAt: "2026-04-01T00:00:00.000Z")
      try self.insertTask(
        db, id: "b", status: "completed", completedAt: "2026-04-03T00:00:00.000Z")
      try self.insertTask(
        db, id: "c", status: "completed", completedAt: "2026-04-02T00:00:00.000Z")
      // Same completed_at as b — tiebreaker is id ASC.
      try self.insertTask(
        db, id: "bb", status: "completed", completedAt: "2026-04-03T00:00:00.000Z")
      return try TaskRepo.Read.getRecentlyCompletedTasks(db, limit: 100)
    }
    XCTAssertEqual(rows.map(\.core.id), ["b", "bb", "c", "a"])
  }

  // MARK: - getTasksByTag

  private func insertTag(
    _ db: Database, id: String, name: String, lookupKey: String
  ) throws {
    try db.execute(
      sql: """
        INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at) \
        VALUES (?, ?, ?, '0000000000000_0000_0000000000000000', \
                '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z')
        """,
      arguments: [id, name, lookupKey])
  }

  private func insertTaskTag(_ db: Database, taskId: String, tagId: String) throws {
    try db.execute(
      sql: """
        INSERT INTO task_tags (task_id, tag_id, version, created_at) \
        VALUES (?, ?, '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00.000Z')
        """,
      arguments: [taskId, tagId])
  }

  func testGetTasksByTagByTagIdReturnsCanonicallyOrdered() throws {
    let store = try TestSupport.freshStore()
    let rows = try store.writer.write { db -> [TaskRow] in
      try self.insertTag(db, id: "tag-1", name: "Work", lookupKey: "work")
      try self.insertTask(db, id: "a", priority: 3, dueDate: "2026-04-10")
      try self.insertTask(db, id: "b", priority: 1)
      try self.insertTask(db, id: "c", priority: 2)
      try self.insertTask(db, id: "d", priority: 1)  // not tagged
      try self.insertTaskTag(db, taskId: "a", tagId: "tag-1")
      try self.insertTaskTag(db, taskId: "b", tagId: "tag-1")
      try self.insertTaskTag(db, taskId: "c", tagId: "tag-1")
      return try TaskRepo.Read.getTasksByTag(
        db, tagId: TagId(trusted: "tag-1"), limit: 100, offset: 0)
    }
    // b (p1) < c (p2) < a (p3); 'd' excluded.
    XCTAssertEqual(rows.map(\.core.id), ["b", "c", "a"])
  }

  func testGetTasksByTagByLookupKeyResolvesMinIdWinner() throws {
    let store = try TestSupport.freshStore()
    let rows = try store.writer.write { db -> [TaskRow] in
      // Two tag rows share the same lookup_key (mid-convergence
      // duplicate). The min-id winner is what the merger picks, and
      // the read must agree.
      try self.insertTag(db, id: "tag-z", name: "Work", lookupKey: "work")
      try self.insertTag(db, id: "tag-a", name: "Work", lookupKey: "work")
      try self.insertTask(db, id: "t-on-a", priority: 1)
      try self.insertTask(db, id: "t-on-z", priority: 1)
      try self.insertTaskTag(db, taskId: "t-on-a", tagId: "tag-a")
      try self.insertTaskTag(db, taskId: "t-on-z", tagId: "tag-z")
      return try TaskRepo.Read.getTasksByTag(
        db, tagLookupKey: "work", limit: 100, offset: 0)
    }
    // tag-a wins (lex-min id); only tasks tagged with tag-a surface.
    XCTAssertEqual(rows.map(\.core.id), ["t-on-a"])
  }

  func testGetTasksByTagExcludesArchivedTasks() throws {
    let store = try TestSupport.freshStore()
    let rows = try store.writer.write { db -> [TaskRow] in
      try self.insertTag(db, id: "tag-1", name: "Work", lookupKey: "work")
      try self.insertTask(db, id: "live", priority: 1)
      try self.insertTask(
        db, id: "trashed", priority: 1, archivedAt: "2026-04-01T00:00:00.000Z")
      try self.insertTaskTag(db, taskId: "live", tagId: "tag-1")
      try self.insertTaskTag(db, taskId: "trashed", tagId: "tag-1")
      return try TaskRepo.Read.getTasksByTag(
        db, tagId: TagId(trusted: "tag-1"), limit: 100, offset: 0)
    }
    XCTAssertEqual(rows.map(\.core.id), ["live"])
  }

  func testGetTasksByTagWithNeitherKeyReturnsEmpty() throws {
    let store = try TestSupport.freshStore()
    let rows = try store.writer.read { db in
      try TaskRepo.Read.getTasksByTag(db, limit: 100, offset: 0)
    }
    XCTAssertTrue(rows.isEmpty)
  }

  func testGetTasksByTagUnknownLookupKeyReturnsEmpty() throws {
    let store = try TestSupport.freshStore()
    let rows = try store.writer.read { db in
      try TaskRepo.Read.getTasksByTag(
        db, tagLookupKey: "no-such-tag", limit: 100, offset: 0)
    }
    XCTAssertTrue(rows.isEmpty)
  }

  func testGetTasksByTagRespectsLimitAndOffset() throws {
    let store = try TestSupport.freshStore()
    let rows = try store.writer.write { db -> [TaskRow] in
      try self.insertTag(db, id: "tag-1", name: "Work", lookupKey: "work")
      for idx in 1...5 {
        try self.insertTask(db, id: "t\(idx)", priority: 1)
        try self.insertTaskTag(db, taskId: "t\(idx)", tagId: "tag-1")
      }
      return try TaskRepo.Read.getTasksByTag(
        db, tagId: TagId(trusted: "tag-1"), limit: 2, offset: 2)
    }
    XCTAssertEqual(rows.map(\.core.id), ["t3", "t4"])
  }

  func testGetRecentlyCompletedTasksFiltersByStatusAndArchive() throws {
    let store = try TestSupport.freshStore()
    let rows = try store.writer.write { db -> [TaskRow] in
      try self.insertTask(db, id: "open1", status: "open")
      try self.insertTask(
        db, id: "done1", status: "completed", completedAt: "2026-04-01T00:00:00.000Z")
      try self.insertTask(
        db, id: "cancelled", status: "cancelled", completedAt: "2026-04-01T00:00:00.000Z")
      try self.insertTask(
        db, id: "doneTrashed", status: "completed",
        completedAt: "2026-04-02T00:00:00.000Z",
        archivedAt: "2026-04-03T00:00:00.000Z")
      return try TaskRepo.Read.getRecentlyCompletedTasks(db, limit: 100)
    }
    XCTAssertEqual(rows.map(\.core.id), ["done1"])
  }
}
