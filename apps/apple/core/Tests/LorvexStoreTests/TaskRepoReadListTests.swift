import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

/// Ports the `list_tasks` cases from the Rust
/// `repositories/task/read/tests/list_filters.rs` suite (the
/// `get_list_tasks_with_recent_completed` cases in that file are already
/// covered by `TaskRepoReadTests.swift` and are not duplicated here), plus the
/// inline `datetime_range_tests` / `is_bare_ymd` unit tests from `list.rs`.
final class TaskRepoReadListTests: XCTestCase {

  /// Mirrors the Rust `insert_task(id, title, status, due_date, planned_date,
  /// priority, list_id)` helper. `listId` defaults to the schema-seeded
  /// `inbox` list (the Rust helper materializes a `default-list`; both are
  /// arbitrary valid lists for these filter tests).
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

  private func insertDependency(_ db: Database, taskId: String, dependsOn: String) throws {
    try db.execute(
      sql: """
        INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at) \
        VALUES (?, ?, '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z')
        """,
      arguments: [taskId, dependsOn])
  }

  private func ids(_ result: TaskRepo.ListTasksResult) -> [String] {
    result.rows.map { $0.core.id }
  }

  // MARK: - status / tags / text / total

  func testFiltersStatusTagsTextAndCountsTotal() throws {
    let store = try TestSupport.freshStore()
    let result = try store.writer.write { db -> TaskRepo.ListTasksResult in
      try self.insertTask(db, "alpha", "Alpha roadmap", "open", dueDate: "2026-03-24", priority: 1)
      try self.insertTask(
        db, "beta", "Beta roadmap", "completed", dueDate: "2026-03-25", priority: 2)
      try self.insertTask(db, "gamma", "Gamma", "open", dueDate: "2026-03-26", priority: 3)
      try db.execute(
        sql: """
          INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at) \
          VALUES ('tag-work', 'Work', 'work', \
          '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
          """)
      for taskId in ["alpha", "beta"] {
        try db.execute(
          sql: """
            INSERT INTO task_tags (task_id, tag_id, version, created_at) \
            VALUES (?, 'tag-work', '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z')
            """,
          arguments: [taskId])
      }
      var q = TaskRepo.ListTasksQuery()
      q.status = .all
      q.tags = ["work"]
      q.text = "road"
      q.limit = 1
      return try TaskRepo.Read.listTasks(db, query: q)
    }
    XCTAssertEqual(result.totalMatching, 2)
    XCTAssertEqual(result.rows.count, 1)
    XCTAssertEqual(result.rows[0].core.id, "alpha")
  }

  func testTextFilterMatchesTitleBodyAndAiNotesWithEscape() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertTask(db, "title-hit", "needle in title", "open")
      try self.insertTask(db, "body-hit", "boring", "open")
      try db.execute(
        sql: "UPDATE tasks SET body = 'has a needle inside the body' WHERE id = 'body-hit'")
      try self.insertTask(db, "ainotes-hit", "boring", "open")
      try db.execute(
        sql: "UPDATE tasks SET ai_notes = 'AI sees a needle' WHERE id = 'ainotes-hit'")
      try self.insertTask(db, "miss", "haystack only", "open")

      var q = TaskRepo.ListTasksQuery()
      q.status = .all
      q.text = "needle"
      let result = try TaskRepo.Read.listTasks(db, query: q)
      XCTAssertEqual(self.ids(result).sorted(), ["ainotes-hit", "body-hit", "title-hit"])
      XCTAssertEqual(result.totalMatching, 3)

      // SQLite LIKE is ASCII case-insensitive by default.
      var upperQ = TaskRepo.ListTasksQuery()
      upperQ.status = .all
      upperQ.text = "NEEDLE"
      let upper = try TaskRepo.Read.listTasks(db, query: upperQ)
      XCTAssertEqual(upper.totalMatching, 3)

      // Whitespace-only text input is treated as no filter (trim + empty).
      try self.insertTask(db, "extra", "extra", "open")
      var blankQ = TaskRepo.ListTasksQuery()
      blankQ.status = .all
      blankQ.text = "   "
      let blank = try TaskRepo.Read.listTasks(db, query: blankQ)
      XCTAssertGreaterThanOrEqual(blank.rows.count, 4, "blank text must not filter")
    }
  }

  func testTextFilterEscapesLikeMetacharacters() throws {
    let store = try TestSupport.freshStore()
    let result = try store.writer.write { db -> TaskRepo.ListTasksResult in
      try self.insertTask(db, "exact", "we hit 100% coverage", "open")
      try self.insertTask(db, "false-positive", "we hit 1000 lines", "open")
      var q = TaskRepo.ListTasksQuery()
      q.status = .all
      q.text = "100%"
      return try TaskRepo.Read.listTasks(db, query: q)
    }
    XCTAssertEqual(ids(result), ["exact"])
    XCTAssertEqual(result.totalMatching, 1)
  }

  // MARK: - blocking / dependency direction

  func testFiltersDependencyDirection() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertTask(db, "blocker", "Blocker", "open", priority: 1)
      try self.insertTask(db, "blocked", "Blocked", "open", priority: 2)
      try self.insertDependency(db, taskId: "blocked", dependsOn: "blocker")

      var blockedQ = TaskRepo.ListTasksQuery()
      blockedQ.blocking = .blockedOnly
      let blocked = try TaskRepo.Read.listTasks(db, query: blockedQ)

      var blockersQ = TaskRepo.ListTasksQuery()
      blockersQ.blocking = .blockingOthers
      let blockers = try TaskRepo.Read.listTasks(db, query: blockersQ)

      XCTAssertEqual(blocked.rows[0].core.id, "blocked")
      XCTAssertEqual(blockers.rows[0].core.id, "blocker")
    }
  }

  func testDependencyFiltersIgnoreArchivedEndpoints() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertTask(db, "archived-blocker", "Hidden blocker", "open", priority: 1)
      try self.insertTask(db, "blocked-visible", "Blocked visible", "open", priority: 2)
      try self.insertTask(db, "visible-blocker", "Visible blocker", "open", priority: 1)
      try self.insertTask(db, "archived-dependent", "Hidden dependent", "open", priority: 2)
      try self.insertDependency(db, taskId: "blocked-visible", dependsOn: "archived-blocker")
      try self.insertDependency(db, taskId: "archived-dependent", dependsOn: "visible-blocker")
      try db.execute(
        sql: """
          UPDATE tasks SET archived_at = '2026-04-25T12:00:00.000Z' \
          WHERE id IN ('archived-blocker', 'archived-dependent')
          """)

      var blockedQ = TaskRepo.ListTasksQuery()
      blockedQ.blocking = .blockedOnly
      let blocked = try TaskRepo.Read.listTasks(db, query: blockedQ)

      var blockersQ = TaskRepo.ListTasksQuery()
      blockersQ.blocking = .blockingOthers
      let blockers = try TaskRepo.Read.listTasks(db, query: blockersQ)

      XCTAssertTrue(
        blocked.rows.isEmpty, "visible tasks should not be blocked by Trash rows")
      XCTAssertTrue(
        blockers.rows.isEmpty, "visible tasks should not count hidden Trash dependents")
    }
  }

  func testBlockingFilterBlockedAndBlockingIntersectsPredicates() throws {
    let store = try TestSupport.freshStore()
    let result = try store.writer.write { db -> TaskRepo.ListTasksResult in
      try self.insertTask(db, "top", "Top", "open", priority: 1)
      try self.insertTask(db, "middle", "Middle", "open", priority: 2)
      try self.insertTask(db, "bottom", "Bottom", "open", priority: 3)
      try self.insertDependency(db, taskId: "middle", dependsOn: "top")
      try self.insertDependency(db, taskId: "bottom", dependsOn: "middle")
      var q = TaskRepo.ListTasksQuery()
      q.blocking = .blockedAndBlocking
      return try TaskRepo.Read.listTasks(db, query: q)
    }
    XCTAssertEqual(result.totalMatching, 1)
    XCTAssertEqual(result.rows[0].core.id, "middle")
  }

  func testBlockingFilterFromFlagsNormalizesLegacyPair() {
    XCTAssertEqual(
      TaskRepo.BlockingFilter.fromFlags(blockedOnly: false, blockingOthers: false), .any)
    XCTAssertEqual(
      TaskRepo.BlockingFilter.fromFlags(blockedOnly: true, blockingOthers: false), .blockedOnly)
    XCTAssertEqual(
      TaskRepo.BlockingFilter.fromFlags(blockedOnly: false, blockingOthers: true), .blockingOthers)
    XCTAssertEqual(
      TaskRepo.BlockingFilter.fromFlags(blockedOnly: true, blockingOthers: true),
      .blockedAndBlocking)
  }

  // MARK: - date presence

  /// `scheduledRange` selects on the calendar day the reference product's
  /// calendar uses — `COALESCE(planned_date, due_date)`: planned wins when
  /// both exist, due is the fallback, and a task with neither never matches.
  func testScheduledRangeCoalescesPlannedOverDue() throws {
    let store = try TestSupport.freshStore()
    let result = try store.writer.write { db -> TaskRepo.ListTasksResult in
      try self.insertTask(
        db, "planned-only", "Planned only", "open", plannedDate: "2026-04-15", priority: 2)
      try self.insertTask(
        db, "due-only", "Due only", "open", dueDate: "2026-04-15", priority: 2)
      try self.insertTask(
        db, "planned-wins", "Planned wins", "open", dueDate: "2026-04-15",
        plannedDate: "2026-04-20", priority: 2)
      try self.insertTask(db, "undated", "Undated", "open", priority: 2)
      var q = TaskRepo.ListTasksQuery()
      q.scheduledRange = .init(from: "2026-04-15", to: "2026-04-15")
      return try TaskRepo.Read.listTasks(db, query: q)
    }
    let ids = Set(result.rows.map { $0.core.id })
    XCTAssertEqual(ids, ["planned-only", "due-only"])
  }

  func testDuePresencePresentReturnsOnlyDatedRows() throws {
    let store = try TestSupport.freshStore()
    let result = try store.writer.write { db -> TaskRepo.ListTasksResult in
      try self.insertTask(db, "with-due", "With due", "open", dueDate: "2026-04-01", priority: 2)
      try self.insertTask(db, "no-due", "No due", "open", priority: 2)
      var q = TaskRepo.ListTasksQuery()
      q.duePresence = .present
      return try TaskRepo.Read.listTasks(db, query: q)
    }
    XCTAssertEqual(result.totalMatching, 1)
    XCTAssertEqual(result.rows[0].core.id, "with-due")
  }

  func testDuePresenceAbsentReturnsOnlyUndatedRows() throws {
    let store = try TestSupport.freshStore()
    let result = try store.writer.write { db -> TaskRepo.ListTasksResult in
      try self.insertTask(db, "with-due", "With due", "open", dueDate: "2026-04-01", priority: 2)
      try self.insertTask(db, "no-due", "No due", "open", priority: 2)
      var q = TaskRepo.ListTasksQuery()
      q.duePresence = .absent
      return try TaskRepo.Read.listTasks(db, query: q)
    }
    XCTAssertEqual(result.totalMatching, 1)
    XCTAssertEqual(result.rows[0].core.id, "no-due")
  }

  func testPlannedPresenceFiltersIndependentlyOfDue() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertTask(
        db, "planned", "Planned", "open", plannedDate: "2026-04-01", priority: 2)
      try self.insertTask(
        db, "unplanned", "Unplanned", "open", dueDate: "2026-04-01", priority: 2)

      var presentQ = TaskRepo.ListTasksQuery()
      presentQ.plannedPresence = .present
      let present = try TaskRepo.Read.listTasks(db, query: presentQ)

      var absentQ = TaskRepo.ListTasksQuery()
      absentQ.plannedPresence = .absent
      let absent = try TaskRepo.Read.listTasks(db, query: absentQ)

      XCTAssertEqual(present.rows.count, 1)
      XCTAssertEqual(present.rows[0].core.id, "planned")
      XCTAssertEqual(absent.rows.count, 1)
      XCTAssertEqual(absent.rows[0].core.id, "unplanned")
    }
  }

  // MARK: - sort direction (priority_effective NULLIF sentinel)

  func testPriorityDueDescPushesUnprioritizedLast() throws {
    let store = try TestSupport.freshStore()
    let result = try store.writer.write { db -> TaskRepo.ListTasksResult in
      try self.insertTask(db, "p1", "P1", "open", priority: 1)
      try self.insertTask(db, "p2", "P2", "open", priority: 2)
      try self.insertTask(db, "p3", "P3", "open", priority: 3)
      try self.insertTask(db, "px", "PX", "open")
      var q = TaskRepo.ListTasksQuery()
      q.status = .all
      q.sortBy = .priorityDue
      q.sortDirection = .desc
      return try TaskRepo.Read.listTasks(db, query: q)
    }
    XCTAssertEqual(
      ids(result), ["p3", "p2", "p1", "px"],
      "unprioritized must sort last under DESC")
  }

  func testPriorityDueAscKeepsUnprioritizedLast() throws {
    let store = try TestSupport.freshStore()
    let result = try store.writer.write { db -> TaskRepo.ListTasksResult in
      try self.insertTask(db, "p1", "P1", "open", priority: 1)
      try self.insertTask(db, "p2", "P2", "open", priority: 2)
      try self.insertTask(db, "px", "PX", "open")
      var q = TaskRepo.ListTasksQuery()
      q.status = .all
      q.sortBy = .priorityDue
      q.sortDirection = .asc
      return try TaskRepo.Read.listTasks(db, query: q)
    }
    XCTAssertEqual(ids(result), ["p1", "p2", "px"])
  }

  // MARK: - datetime range widening (ports the inline `datetime_range_tests`)

  /// Mirrors the Rust `run(range)` — drives the real production
  /// ``TaskRepo/Read/pushRange`` `datetime` branch over `completed_at` and
  /// captures the SQL fragment + bind values it actually emits, so a future
  /// edit to the widening rule is caught here rather than passing silently.
  private func runDatetimeRange(
    _ range: TaskRepo.TaskDateRange
  ) -> (String, [DatabaseValueConvertible?]) {
    var sql = ""
    var values: [DatabaseValueConvertible?] = []
    TaskRepo.Read.pushRange(
      into: &sql, values: &values, column: "completed_at", range: range, widening: .datetime)
    return (sql, values)
  }

  private func text(_ value: DatabaseValueConvertible?) -> String? {
    guard let value, case let .string(s) = value.databaseValue.storage else { return nil }
    return s
  }

  func testBareYmdToWidensToEndOfDay() throws {
    let (sql, vals) = runDatetimeRange(TaskRepo.TaskDateRange(from: nil, to: "2026-04-26"))
    XCTAssertEqual(sql, " AND completed_at <= ?")
    XCTAssertEqual(vals.count, 1)
    XCTAssertEqual(text(vals[0]), "2026-04-26T23:59:59.999Z")
  }

  func testBareYmdCapIncludesMicrosecondRows() throws {
    let (_, vals) = runDatetimeRange(TaskRepo.TaskDateRange(from: nil, to: "2026-04-26"))
    let cap = try XCTUnwrap(text(vals[0]))
    let rowWithMicros = "2026-04-26T23:59:59.123456Z"
    XCTAssertTrue(
      Array(rowWithMicros.utf8).lexicographicallyPrecedes(Array(cap.utf8)),
      "row \(rowWithMicros) must lex-compare <= cap \(cap)")
  }

  func testRfc3339ToPassesThroughVerbatim() throws {
    let (sql, vals) = runDatetimeRange(
      TaskRepo.TaskDateRange(from: nil, to: "2026-04-26T10:00:00Z"))
    XCTAssertEqual(sql, " AND completed_at <= ?")
    XCTAssertEqual(text(vals[0]), "2026-04-26T10:00:00Z")
  }

  func testFromIsPassedThroughUnchanged() throws {
    let (sql, vals) = runDatetimeRange(
      TaskRepo.TaskDateRange(from: "2026-04-01T00:00:00Z", to: nil))
    XCTAssertEqual(sql, " AND completed_at >= ?")
    XCTAssertEqual(text(vals[0]), "2026-04-01T00:00:00Z")
  }

  /// End-to-end: a row whose `completed_at` carries microsecond precision
  /// must fall inside an inclusive bare-`YYYY-MM-DD` upper bound, and a row
  /// on the following day must not. Exercises the whole widening pipeline
  /// through SQLite rather than the fragment builder alone.
  func testDatetimeRangeWideningIncludesMicrosecondRowEndToEnd() throws {
    let store = try TestSupport.freshStore()
    let result = try store.writer.write { db -> TaskRepo.ListTasksResult in
      try self.insertTask(db, "in-window", "In window", "completed")
      try db.execute(
        sql: "UPDATE tasks SET completed_at = '2026-04-26T23:59:59.123456Z' WHERE id = 'in-window'")
      try self.insertTask(db, "next-day", "Next day", "completed")
      try db.execute(
        sql: "UPDATE tasks SET completed_at = '2026-04-27T00:00:00.000000Z' WHERE id = 'next-day'")
      var q = TaskRepo.ListTasksQuery()
      q.status = .all
      q.completedRange = TaskRepo.TaskDateRange(from: "2026-04-26", to: "2026-04-26")
      return try TaskRepo.Read.listTasks(db, query: q)
    }
    XCTAssertEqual(ids(result), ["in-window"])
    XCTAssertEqual(result.totalMatching, 1)
  }

  /// Regression: stored timestamps are millisecond `.mmmZ` (`SyncTimestamp`),
  /// so the largest value a day can hold is `T23:59:59.999Z`. A bare
  /// `YYYY-MM-DD` upper bound must include that final-millisecond row. The
  /// former `.999999Z` cap byte-sorted *before* `.999Z` (the row's `Z`
  /// outranks the cap's fourth fractional digit) and silently dropped it.
  func testDatetimeRangeWideningIncludesFinalMillisecondRowEndToEnd() throws {
    let store = try TestSupport.freshStore()
    let result = try store.writer.write { db -> TaskRepo.ListTasksResult in
      try self.insertTask(db, "last-ms", "Last millisecond", "completed")
      try db.execute(
        sql: "UPDATE tasks SET completed_at = '2026-04-26T23:59:59.999Z' WHERE id = 'last-ms'")
      try self.insertTask(db, "next-day", "Next day", "completed")
      try db.execute(
        sql: "UPDATE tasks SET completed_at = '2026-04-27T00:00:00.000Z' WHERE id = 'next-day'")
      var q = TaskRepo.ListTasksQuery()
      q.status = .all
      q.completedRange = TaskRepo.TaskDateRange(from: "2026-04-26", to: "2026-04-26")
      return try TaskRepo.Read.listTasks(db, query: q)
    }
    XCTAssertEqual(ids(result), ["last-ms"])
    XCTAssertEqual(result.totalMatching, 1)
  }

  func testIsBareYmdRecognizesOnlyCanonicalForm() {
    XCTAssertTrue(TaskRepo.Read.isBareYmd("2026-04-26"))
    XCTAssertTrue(TaskRepo.Read.isBareYmd("0000-00-00"))
    XCTAssertFalse(TaskRepo.Read.isBareYmd("2026-04-26 "))
    XCTAssertFalse(TaskRepo.Read.isBareYmd("2026-04-26T"))
    XCTAssertFalse(TaskRepo.Read.isBareYmd("2026-04-26T00:00:00Z"))
    XCTAssertFalse(TaskRepo.Read.isBareYmd("2026-4-26"))
    XCTAssertFalse(TaskRepo.Read.isBareYmd("2026/04/26"))
    XCTAssertFalse(TaskRepo.Read.isBareYmd(""))
    XCTAssertFalse(TaskRepo.Read.isBareYmd("2026-04-2"))
  }
}
