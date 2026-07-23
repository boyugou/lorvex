import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

/// `in_progress` joins `open` in the actionable pools: it surfaces wherever
/// `status = 'open'` meant "actionable", while archived rows stay excluded like
/// any archived task.
final class InProgressQueryInclusionTests: XCTestCase {
  private func insert(
    _ db: Database, id: String, status: String, archivedAt: String? = nil
  ) throws {
    try db.execute(
      sql:
        "INSERT INTO tasks (id, title, status, list_id, archived_at, version, "
        + "created_at, updated_at, completed_at, defer_count) "
        + "VALUES (?1, ?1, ?2, 'inbox', ?3, "
        + "'0000000000000_0000_0000000000000000', "
        + "'2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z', "
        + "CASE WHEN ?2 = 'completed' THEN '2026-01-01T00:00:00.000Z' END, 0)",
      arguments: [id, status, archivedAt])
  }

  /// The overview/today actionable pool (`getOpenTasksByPriority`) includes
  /// in_progress alongside open and excludes terminal rows.
  func testActionablePoolIncludesInProgress() throws {
    let store = try TestSupport.freshStore()
    let ids = try store.writer.write { db -> Set<String> in
      try self.insert(db, id: "open1", status: "open")
      try self.insert(db, id: "wip1", status: "in_progress")
      try self.insert(db, id: "done1", status: "completed")
      try self.insert(db, id: "someday1", status: "someday")
      let rows = try TaskRepo.Read.getOpenTasksByPriority(db, today: "2026-04-01", limit: 50)
      return Set(rows.map { $0.core.id })
    }
    XCTAssertTrue(ids.contains("open1"))
    XCTAssertTrue(ids.contains("wip1"), "in_progress joins the actionable pool")
    XCTAssertFalse(ids.contains("done1"))
    XCTAssertFalse(ids.contains("someday1"), "someday stays parked, not in the actionable pool")
  }

  /// An archived in_progress task is excluded from the actionable pool, exactly
  /// like any archived task.
  func testArchivedInProgressExcluded() throws {
    let store = try TestSupport.freshStore()
    let ids = try store.writer.write { db -> Set<String> in
      try self.insert(db, id: "wip1", status: "in_progress")
      try self.insert(
        db, id: "wipArchived", status: "in_progress", archivedAt: "2026-02-01T00:00:00Z")
      let rows = try TaskRepo.Read.getOpenTasksByPriority(db, today: "2026-04-01", limit: 50)
      return Set(rows.map { $0.core.id })
    }
    XCTAssertTrue(ids.contains("wip1"))
    XCTAssertFalse(ids.contains("wipArchived"), "archived in_progress is excluded")
  }

  /// The `.actionable` list filter binds `status IN (open, in_progress)`, so the
  /// Tasks-workspace open lane surfaces a started task and excludes parked /
  /// terminal work.
  func testActionableListFilterIncludesOpenAndInProgressOnly() throws {
    let store = try TestSupport.freshStore()
    let ids = try store.writer.write { db -> Set<String> in
      try self.insert(db, id: "open1", status: "open")
      try self.insert(db, id: "wip1", status: "in_progress")
      try self.insert(db, id: "someday1", status: "someday")
      try self.insert(db, id: "done1", status: "completed")
      try self.insert(db, id: "cancelled1", status: "cancelled")
      let result = try TaskRepo.Read.listTasks(
        db, query: TaskRepo.ListTasksQuery(status: .actionable, limit: 50, offset: 0))
      return Set(result.rows.map { $0.core.id })
    }
    XCTAssertEqual(ids, ["open1", "wip1"], "actionable = open + in_progress only")
  }

  /// `getInProgressTasks` returns every started task, uncapped, and excludes
  /// archived rows and every non-started status.
  func testGetInProgressTasksReturnsOnlyStartedRows() throws {
    let store = try TestSupport.freshStore()
    let ids = try store.writer.write { db -> [String] in
      try self.insert(db, id: "open1", status: "open")
      try self.insert(db, id: "wip1", status: "in_progress")
      try self.insert(db, id: "wip2", status: "in_progress")
      try self.insert(
        db, id: "wipArchived", status: "in_progress", archivedAt: "2026-02-01T00:00:00Z")
      try self.insert(db, id: "done1", status: "completed")
      return try TaskRepo.Read.getInProgressTasks(db).map { $0.core.id }
    }
    XCTAssertEqual(
      Set(ids), ["wip1", "wip2"],
      "only non-archived in_progress rows, no cap, no other status")
  }

  /// A list's open_count (list health snapshot) counts in_progress as active
  /// work alongside open.
  func testListOpenCountIncludesInProgress() throws {
    let store = try TestSupport.freshStore()
    let openCount = try store.writer.write { db -> Int64 in
      try self.insert(db, id: "open1", status: "open")
      try self.insert(db, id: "wip1", status: "in_progress")
      try self.insert(db, id: "done1", status: "completed")
      return try Int64.fetchOne(
        db,
        sql:
          "SELECT COUNT(*) FROM tasks WHERE list_id = 'inbox' "
          + "AND status IN (\(StatusName.actionableStatusSqlList)) AND archived_at IS NULL")!
    }
    XCTAssertEqual(openCount, 2, "open + in_progress both count as active work")
  }
}
