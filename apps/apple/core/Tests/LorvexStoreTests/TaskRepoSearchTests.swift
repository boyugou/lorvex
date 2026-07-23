import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

/// Ports `repositories/task/read/tests/search.rs`,
/// `repositories/task/read/tests/trigram.rs`, and
/// `repositories/task/read/tests/fts_schema.rs`.
final class TaskRepoSearchTests: XCTestCase {

  /// Mirrors the Rust `insert_task` test helper. A `nil` `listId` falls
  /// through to a once-seeded `default-list`.
  private func insertTask(
    _ db: Database, _ id: String, _ title: String, _ status: String,
    dueDate: String? = nil, plannedDate: String? = nil,
    priority: Int64? = nil, listId: String? = nil
  ) throws {
    let resolved: String
    if let listId {
      resolved = listId
    } else {
      try insertList(db, "default-list", "Default")
      resolved = "default-list"
    }
    try db.execute(
      sql: """
        INSERT INTO tasks (id, title, status, due_date, planned_date, priority, list_id, \
        version, created_at, updated_at, completed_at, defer_count) \
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, \
        '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00.000Z', \
        '2026-01-01T00:00:00.000Z', \
        CASE WHEN ?3 = 'completed' THEN '2026-01-01T00:00:00.000Z' END, 0)
        """,
      arguments: [id, title, status, dueDate, plannedDate, priority, resolved])
  }

  private func insertList(_ db: Database, _ id: String, _ name: String) throws {
    try db.execute(
      sql: """
        INSERT OR IGNORE INTO lists (id, name, version, created_at, updated_at) \
        VALUES (?1, ?2, '0000000000000_0000_0000000000000000', \
                '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z')
        """,
      arguments: [id, name])
  }

  private func pred(
    _ query: String, status: [String]? = nil, lists: [String]? = nil, tags: [String]? = nil
  ) -> SearchPredicate {
    SearchPredicate(query: query, statusFilter: status, listFilter: lists, tagFilter: tags)
  }

  // ── FTS-only (search_tasks) ──────────────────────────────────

  func testSearchFindsByTitle() throws {
    let store = try TestSupport.freshStore()
    let tasks = try store.writer.write { db -> [TaskRow] in
      try self.insertTask(db, "t1", "Buy groceries", "open", priority: 2)
      try self.insertTask(db, "t2", "Write report", "open", priority: 1)
      return try TaskRepo.Search.searchTasks(
        db, predicate: self.pred("groceries"), page: .default)
    }
    XCTAssertEqual(tasks.count, 1)
    XCTAssertEqual(tasks[0].core.id, "t1")
  }

  func testSearchEmptyQueryReturnsEmpty() throws {
    let store = try TestSupport.freshStore()
    let tasks = try store.writer.write { db -> [TaskRow] in
      try self.insertTask(db, "t1", "Buy groceries", "open", priority: 2)
      return try TaskRepo.Search.searchTasks(db, predicate: self.pred(""), page: .default)
    }
    XCTAssertTrue(tasks.isEmpty)
  }

  func testSearchWithStatusFilter() throws {
    let store = try TestSupport.freshStore()
    let tasks = try store.writer.write { db -> [TaskRow] in
      try self.insertTask(db, "t1", "Buy groceries", "open", priority: 2)
      try self.insertTask(db, "t2", "Buy milk", "completed", priority: 1)
      return try TaskRepo.Search.searchTasks(
        db, predicate: self.pred("Buy", status: ["open"]), page: .default)
    }
    XCTAssertEqual(tasks.count, 1)
    XCTAssertEqual(tasks[0].core.id, "t1")
  }

  /// Status is the primary sort; BM25 is the within-bucket tiebreaker. An
  /// open task ranks above a completed task regardless of BM25 strength.
  func testSearchRanksStatusPrimaryOverBm25() throws {
    let store = try TestSupport.freshStore()
    let tasks = try store.writer.write { db -> [TaskRow] in
      try self.insertTask(db, "completed-exact", "weekly-report", "completed", priority: 1)
      try self.insertTask(
        db, "open-diluted", "Misc notes and the weekly-report attachment link", "open",
        priority: 2)
      return try TaskRepo.Search.searchTasks(
        db, predicate: self.pred("weekly-report"), page: .default)
    }
    XCTAssertEqual(tasks.count, 2)
    XCTAssertEqual(tasks[0].core.id, "open-diluted")
    XCTAssertEqual(tasks[1].core.id, "completed-exact")
  }

  // ── LIKE fallback ranking (CJK) ──────────────────────────────

  func testSearchLikeFallbackRanksExactTitleMatchAboveBodyMatch() throws {
    let store = try TestSupport.freshStore()
    let result = try store.writer.write { db -> TaskRepo.Search.Result in
      try self.insertTask(db, "t-body", "Shopping list", "open", priority: 2)
      try db.execute(
        sql: "UPDATE tasks SET body = '周末去市场买草莓和其他水果' WHERE id = 't-body'")
      try self.insertTask(db, "t-title", "草莓", "open", priority: 2)
      return try TaskRepo.Search.searchTasksWithFallback(
        db, predicate: self.pred("草莓"), page: .default)
    }
    XCTAssertEqual(result.totalMatching, 2)
    XCTAssertEqual(result.rows.count, 2)
    XCTAssertEqual(result.rows[0].core.id, "t-title")
    XCTAssertEqual(result.rows[1].core.id, "t-body")
  }

  func testSearchLikeFallbackRanksTitleAboveAiNotes() throws {
    let store = try TestSupport.freshStore()
    let result = try store.writer.write { db -> TaskRepo.Search.Result in
      try self.insertTask(db, "t-ai", "Weekly review", "open", priority: 2)
      try db.execute(
        sql:
          "UPDATE tasks SET ai_notes = 'User mentioned 項目 priorities during standup.' "
          + "WHERE id = 't-ai'")
      try self.insertTask(db, "t-title", "項目 kickoff agenda", "open", priority: 2)
      return try TaskRepo.Search.searchTasksWithFallback(
        db, predicate: self.pred("項目"), page: .default)
    }
    XCTAssertEqual(result.totalMatching, 2)
    XCTAssertEqual(result.rows.count, 2)
    XCTAssertEqual(result.rows[0].core.id, "t-title")
    XCTAssertEqual(result.rows[1].core.id, "t-ai")
  }

  // ── LIKE fallback count saturation (pagination) ──────────────

  /// Regression: when more matches exist than the count cap, the LIKE-fallback
  /// count reports `cap + 1` (a "more may exist" sentinel) rather than clamping
  /// to the cap. That keeps `consumed < totalMatching` true at the cap
  /// boundary, so pagination leaves `truncated` set and `nextOffset` non-nil
  /// instead of a client stopping early. Below the cap the exact count stands.
  func testSearchLikeFallbackCountSaturatesAboveCap() throws {
    let store = try TestSupport.freshStore()
    let (saturated, exact) = try store.writer.write {
      db -> (TaskRepo.Search.Result, TaskRepo.Search.Result) in
      for i in 0..<4 {
        try self.insertTask(db, "t\(i)", "alpha item \(i)", "open", priority: 2)
      }
      let saturated = try TaskRepo.Search.searchTasksLike(
        db, rawQuery: "alpha", pred: self.pred("alpha"),
        page: Pagination(limit: 2, offset: 0), countCap: 2)
      let exact = try TaskRepo.Search.searchTasksLike(
        db, rawQuery: "alpha", pred: self.pred("alpha"),
        page: Pagination(limit: 2, offset: 0), countCap: 10)
      return (saturated, exact)
    }
    // 4 rows match, cap 2 → count scans cap+1 and reports the sentinel 3 (> cap):
    // consumed(2) < totalMatching(3), so more pages remain.
    XCTAssertEqual(saturated.totalMatching, 3)
    XCTAssertEqual(saturated.rows.count, 2)
    // Below the cap the exact count is returned unchanged.
    XCTAssertEqual(exact.totalMatching, 4)
  }

  // ── Tag display_name matching (FTS + trigram) ────────────────

  func testSearchFtsMatchesTagDisplayName() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertTask(db, "t1", "Q2 planning session", "open", priority: 2)
      try db.execute(
        sql: """
          INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at) \
          VALUES ('tag-budget', 'budget', 'budget', \
                  '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
          """)
      try db.execute(
        sql: """
          INSERT INTO task_tags (task_id, tag_id, version, created_at) \
          VALUES ('t1', 'tag-budget', \
                  '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z')
          """)
    }
    try store.writer.read { db in
      let rows = try TaskRepo.Search.searchTasks(
        db, predicate: self.pred("budget"), page: .default)
      XCTAssertEqual(rows.count, 1, "FTS should find the task via its #budget tag")
      XCTAssertEqual(rows[0].core.id, "t1")

      let result = try TaskRepo.Search.searchTasksWithFallback(
        db, predicate: self.pred("budget"), page: .default)
      XCTAssertEqual(result.rows.count, 1)
      XCTAssertEqual(result.rows[0].core.id, "t1")
      XCTAssertEqual(result.totalMatching, 1)
    }
  }

  func testSearchTrigramMatchesCjkTagDisplayName() throws {
    let store = try TestSupport.freshStore()
    let result = try store.writer.write { db -> TaskRepo.Search.Result in
      try self.insertTask(db, "t1", "Q2 planning session", "open", priority: 2)
      try db.execute(
        sql: """
          INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at) \
          VALUES ('tag-budget-cjk', '预算管理', '预算管理', \
                  '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
          """)
      try db.execute(
        sql: """
          INSERT INTO task_tags (task_id, tag_id, version, created_at) \
          VALUES ('t1', 'tag-budget-cjk', \
                  '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z')
          """)
      return try TaskRepo.Search.searchTasksWithFallback(
        db, predicate: self.pred("预算管"), page: .default)
    }
    XCTAssertEqual(result.rows.count, 1)
    XCTAssertEqual(result.rows[0].core.id, "t1")
    XCTAssertEqual(result.totalMatching, 1)
  }

  func testFtsTagRenameRefreshesIndexedText() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertTask(db, "t1", "Planning session", "open", priority: 2)
      try db.execute(
        sql: """
          INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at) \
          VALUES ('tag-old', 'oldname', 'oldname', \
                  '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
          """)
      try db.execute(
        sql: """
          INSERT INTO task_tags (task_id, tag_id, version, created_at) \
          VALUES ('t1', 'tag-old', \
                  '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z')
          """)
    }
    try store.writer.write { db in
      let before = try TaskRepo.Search.searchTasks(
        db, predicate: self.pred("oldname"), page: .default)
      XCTAssertEqual(before.count, 1, "initial tag name should be indexed")

      try db.execute(sql: "UPDATE tags SET display_name = 'newname' WHERE id = 'tag-old'")

      let oldAfter = try TaskRepo.Search.searchTasks(
        db, predicate: self.pred("oldname"), page: .default)
      XCTAssertEqual(oldAfter.count, 0, "renamed tag must no longer match the old name via FTS")

      let newAfter = try TaskRepo.Search.searchTasks(
        db, predicate: self.pred("newname"), page: .default)
      XCTAssertEqual(newAfter.count, 1, "renamed tag must match the new name via FTS")
    }
  }

  func testFtsTagUnlinkRemovesFromIndex() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertTask(db, "t1", "Planning session", "open", priority: 2)
      try db.execute(
        sql: """
          INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at) \
          VALUES ('tag-budget', 'budget', 'budget', \
                  '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
          """)
      try db.execute(
        sql: """
          INSERT INTO task_tags (task_id, tag_id, version, created_at) \
          VALUES ('t1', 'tag-budget', \
                  '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z')
          """)
    }
    try store.writer.write { db in
      let before = try TaskRepo.Search.searchTasks(
        db, predicate: self.pred("budget"), page: .default)
      XCTAssertEqual(before.count, 1, "task should match via tag before unlink")

      try db.execute(
        sql: "DELETE FROM task_tags WHERE task_id = 't1' AND tag_id = 'tag-budget'")

      let after = try TaskRepo.Search.searchTasks(
        db, predicate: self.pred("budget"), page: .default)
      XCTAssertEqual(after.count, 0, "task should no longer match via tag after unlink")
    }
  }

  // ── CJK fallback dispatch ────────────────────────────────────

  func testSearchCjkUsesLikeFallback() throws {
    let store = try TestSupport.freshStore()
    let result = try store.writer.write { db -> TaskRepo.Search.Result in
      try self.insertTask(db, "t1", "写一个中文任务", "open", priority: 1)
      try self.insertTask(db, "t2", "Buy groceries", "open", priority: 2)
      return try TaskRepo.Search.searchTasksWithFallback(
        db, predicate: self.pred("中文"), page: .default)
    }
    XCTAssertEqual(result.rows.count, 1)
    XCTAssertEqual(result.rows[0].core.id, "t1")
    XCTAssertEqual(result.totalMatching, 1)
  }

  func testSearchCjkMixedScriptQuery() throws {
    let store = try TestSupport.freshStore()
    let result = try store.writer.write { db -> TaskRepo.Search.Result in
      try self.insertTask(db, "t1", "完成 report", "open", priority: 1)
      try self.insertTask(db, "t2", "Buy groceries", "open", priority: 2)
      return try TaskRepo.Search.searchTasksWithFallback(
        db, predicate: self.pred("完成"), page: .default)
    }
    XCTAssertEqual(result.rows.count, 1)
    XCTAssertEqual(result.rows[0].core.id, "t1")
  }

  // ── Trigram (CJK 3+ char) ────────────────────────────────────

  func testSearchTrigramFindsCjkSubstringAcrossIndexedColumns() throws {
    let store = try TestSupport.freshStore()
    let result = try store.writer.write { db -> TaskRepo.Search.Result in
      try self.insertTask(db, "t-title", "写一个中文任务说明", "open", priority: 2)
      try self.insertTask(db, "t-body", "Shopping list", "open", priority: 2)
      try db.execute(
        sql:
          "UPDATE tasks SET body = '周末去市场买草莓和其他水果 中文任务说明' WHERE id = 't-body'")
      try self.insertTask(db, "t-ai", "Weekly review", "open", priority: 2)
      try db.execute(
        sql: "UPDATE tasks SET ai_notes = '中文任务说明 AI 备注' WHERE id = 't-ai'")
      try self.insertTask(db, "t-miss", "Unrelated", "open", priority: 2)
      return try TaskRepo.Search.searchTasksWithFallback(
        db, predicate: self.pred("中文任务"), page: .default)
    }
    let ids = Set(result.rows.map { $0.core.id })
    XCTAssertEqual(result.totalMatching, 3)
    XCTAssertTrue(ids.contains("t-title"))
    XCTAssertTrue(ids.contains("t-body"))
    XCTAssertTrue(ids.contains("t-ai"))
    XCTAssertFalse(ids.contains("t-miss"))
  }

  func testSearchTrigramRanksExactTitleAboveBodyAboveAiNotes() throws {
    let store = try TestSupport.freshStore()
    let result = try store.writer.write { db -> TaskRepo.Search.Result in
      try self.insertTask(db, "t-ai", "Weekly review", "open", priority: 2)
      try db.execute(
        sql: "UPDATE tasks SET ai_notes = '项目进度 AI 备注' WHERE id = 't-ai'")
      try self.insertTask(db, "t-body", "Shopping list", "open", priority: 2)
      try db.execute(
        sql: "UPDATE tasks SET body = '周末讨论项目进度' WHERE id = 't-body'")
      try self.insertTask(db, "t-title", "项目进度", "open", priority: 2)
      return try TaskRepo.Search.searchTasksWithFallback(
        db, predicate: self.pred("项目进度"), page: .default)
    }
    XCTAssertEqual(result.rows.count, 3)
    XCTAssertEqual(result.rows[0].core.id, "t-title")
    XCTAssertEqual(result.rows[1].core.id, "t-body")
    XCTAssertEqual(result.rows[2].core.id, "t-ai")
  }

  func testTrigramUpdateTriggerReindexesOnTitleChange() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertTask(db, "t1", "周末买苹果", "open", priority: 2)
    }
    try store.writer.write { db in
      let before = try TaskRepo.Search.searchTasksWithFallback(
        db, predicate: self.pred("买苹果"), page: .default)
      XCTAssertEqual(before.rows.count, 1)

      try db.execute(sql: "UPDATE tasks SET title = '周末买香蕉' WHERE id = 't1'")

      let oldAfter = try TaskRepo.Search.searchTasksWithFallback(
        db, predicate: self.pred("买苹果"), page: .default)
      XCTAssertEqual(oldAfter.rows.count, 0)

      let newAfter = try TaskRepo.Search.searchTasksWithFallback(
        db, predicate: self.pred("买香蕉"), page: .default)
      XCTAssertEqual(newAfter.rows.count, 1)
    }
  }

  /// Functional half of the Rust `search_trigram_handles_5000_cjk_tasks_quickly`
  /// perf test: the wall-clock assertion is intentionally dropped (Swift/GRDB
  /// timing characteristics differ from rusqlite). This pins that a unique CJK
  /// substring is found among 5000 trigram-indexed rows.
  func testSearchTrigramFindsUniqueMatchAmong5000CjkTasks() throws {
    let store = try TestSupport.freshStore()
    let result = try store.writer.write { db -> TaskRepo.Search.Result in
      try self.insertList(db, "bench-list", "Bench")
      let pool = Array("任务项目计划想法笔记会议日程提醒目标工作学习练习阅读整理")
      for i in 0..<5000 {
        let base = i % pool.count
        let title = String((0..<6).map { pool[(base + $0) % pool.count] })
        let id = String(format: "bench-%05d", i)
        try db.execute(
          sql: """
            INSERT INTO tasks (id, title, status, list_id, version, created_at, updated_at, defer_count) \
            VALUES (?1, ?2, 'open', 'bench-list', '0000000000000_0000_0000000000000000', \
                    '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z', 0)
            """,
          arguments: [id, title])
      }
      try db.execute(
        sql: "UPDATE tasks SET title = '独特查询标记' WHERE id = 'bench-02500'")
      return try TaskRepo.Search.searchTasksWithFallback(
        db, predicate: self.pred("独特查询"), page: .default)
    }
    XCTAssertEqual(result.totalMatching, 1)
    XCTAssertEqual(result.rows[0].core.id, "bench-02500")
  }

  // ── is_fts_schema_missing classifier (fts_schema.rs) ─────────

  func testIsFtsSchemaMissingMatchesLiveSqliteMissingTableText() throws {
    let queue = try DatabaseQueue()
    try queue.read { db in
      do {
        _ = try Row.fetchAll(
          db, sql: "SELECT rowid FROM tasks_fts WHERE tasks_fts MATCH 'x'")
        XCTFail("expected missing-table error")
      } catch {
        XCTAssertTrue(
          TaskRepo.Search.isFtsSchemaMissing(error),
          "SQLite wording for missing-table drifted: \(error)")
      }
    }
  }

  func testIsFtsSchemaMissingRejectsRealErrors() throws {
    let queue = try DatabaseQueue()
    try queue.write { db in
      try db.execute(sql: "CREATE TABLE t (id INTEGER PRIMARY KEY, title TEXT)")
      do {
        _ = try Row.fetchAll(db, sql: "SELECT no_such_column FROM t")
        XCTFail("expected bad-column error")
      } catch {
        XCTAssertFalse(
          TaskRepo.Search.isFtsSchemaMissing(error),
          "generic SQL error should not be classified as schema-missing: \(error)")
      }
    }
  }
}
