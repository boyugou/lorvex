import GRDB
import LorvexStore
import XCTest

@testable import LorvexWorkflow

/// Ports `weekly_review/tests.rs`. Seeding uses raw INSERTs in place of the
/// Rust `ListBuilder` / `TaskBuilder` fixtures (no Swift analog), preserving
/// their defaults: task `created_at`/`updated_at` default to the seed timestamp
/// `2026-03-20T00:00:00.000Z` and status defaults to `open`. The fixture relies
/// on `datetime('now', '-N day(s)')` for the completed-this-week window, exactly
/// as the Rust test does, so the timezone is the system default and "this week"
/// is relative to the wall clock at run time.
final class WeeklyReviewTests: XCTestCase {
  private static let version = "0000000000000_0000_0000000000000000"
  private static let staleTs = "2026-03-01T00:00:00Z"
  private static let seedTs = "2026-03-20T00:00:00.000Z"

  private func insertList(
    _ db: Database, id: String, name: String, icon: String? = nil, color: String? = nil
  ) throws {
    try db.execute(
      sql: "INSERT INTO lists (id, name, icon, color, version, created_at, updated_at) "
        + "VALUES (?, ?, ?, ?, ?, ?, ?)",
      arguments: [id, name, icon, color, Self.version, Self.staleTs, Self.staleTs])
  }

  private func insertTask(
    _ db: Database, id: String, title: String, status: String = "open", listId: String,
    dueDate: String? = nil, deferCount: Int64 = 0, updatedAt: String = seedTs
  ) throws {
    try db.execute(
      sql: "INSERT INTO tasks (id, title, status, list_id, due_date, defer_count, "
        + "version, created_at, updated_at, completed_at) "
        + "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, CASE WHEN ? = 'completed' THEN ? END)",
      arguments: [
        id, title, status, listId, dueDate, deferCount, Self.version, Self.seedTs, updatedAt,
        status, Self.seedTs,
      ])
  }

  private func seedFixture(_ db: Database) throws {
    try insertList(db, id: "list-a", name: "Alpha", icon: "circle", color: "#111111")
    try insertList(db, id: "list-b", name: "Beta")

    let yesterday = try WorkflowTimezone.datePlusDaysYmdForConn(db, days: -1)
    let today = try WorkflowTimezone.todayYmdForConn(db)
    let tomorrow = try WorkflowTimezone.datePlusDaysYmdForConn(db, days: 1)

    try insertTask(db, id: "completed-a", title: "Completed A", status: "completed", listId: "list-a")
    try insertTask(db, id: "completed-b", title: "Completed B", status: "completed", listId: "list-a")
    try db.execute(
      sql: "UPDATE tasks SET completed_at = datetime('now', '-1 day') WHERE id = 'completed-a'")
    try db.execute(
      sql: "UPDATE tasks SET completed_at = datetime('now', '-2 days') WHERE id = 'completed-b'")

    try insertTask(
      db, id: "deferred-high", title: "Deferred high", listId: "list-a", dueDate: tomorrow,
      deferCount: 8, updatedAt: Self.staleTs)
    try insertTask(
      db, id: "deferred-low", title: "Deferred low", listId: "list-a", dueDate: tomorrow,
      deferCount: 3, updatedAt: Self.staleTs)
    try insertTask(
      db, id: "overdue", title: "Overdue", listId: "list-b", dueDate: yesterday,
      updatedAt: Self.staleTs)
    try insertTask(
      db, id: "today-not-overdue", title: "Today", listId: "list-b", dueDate: today,
      updatedAt: Self.staleTs)
    try insertTask(
      db, id: "someday", title: "Someday", status: "someday", listId: "list-b")
  }

  func testSharedWeeklyReviewModelsPinCountsSectionsAndOrdering() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in try seedFixture(db) }

    let (read, snapshot, brief) = try store.writer.read {
      db -> (WeeklyReview.ReadModel, WeeklyReview.Snapshot, WeeklyReview.Brief) in
      let read = try WeeklyReview.loadWeeklyReview(
        db,
        limits: .init(
          completedThisWeek: 10, stalledLists: 10, frequentlyDeferred: 10, overdueTasks: 10,
          somedayItems: 10))
      let snapshot = try WeeklyReview.loadWeeklyReviewSnapshot(
        db,
        limits: .init(
          topCompleted: 10, stalledLists: 10, frequentlyDeferred: 10, somedayItems: 10))
      let brief = try WeeklyReview.loadWeeklyReviewBrief(
        db,
        limits: .init(
          completedThisWeek: 10, stalledLists: 10, frequentlyDeferred: 10, somedayItems: 10))
      return (read, snapshot, brief)
    }

    XCTAssertEqual(read.counts.completedThisWeek, 2)
    XCTAssertEqual(snapshot.counts.completedThisWeek, read.counts.completedThisWeek)
    XCTAssertEqual(
      brief.sectionMeta.completedThisWeek.totalMatching, read.counts.completedThisWeek)
    XCTAssertEqual(read.counts.overdueOpen, 1)
    XCTAssertEqual(brief.overdueCount, 1)

    XCTAssertEqual(read.completedThisWeek.map { $0.id }, ["completed-a", "completed-b"])
    XCTAssertEqual(snapshot.topCompleted, read.completedThisWeek)
    XCTAssertEqual(brief.completedThisWeek, read.completedThisWeek)

    XCTAssertEqual(read.frequentlyDeferred.map { $0.id }, ["deferred-high", "deferred-low"])
    XCTAssertEqual(snapshot.frequentlyDeferred, read.frequentlyDeferred)
    XCTAssertEqual(brief.frequentlyDeferred, read.frequentlyDeferred)

    XCTAssertEqual(read.stalledLists.map { $0.id }, ["list-a", "list-b"])
    XCTAssertEqual(snapshot.stalledLists, read.stalledLists)
    XCTAssertEqual(brief.stalledLists, read.stalledLists)

    // Someday items are loaded into every consumer shape and stay in sync.
    XCTAssertEqual(read.counts.someday, 1)
    XCTAssertEqual(read.somedayItems.map { $0.id }, ["someday"])
    XCTAssertEqual(snapshot.somedayItems, read.somedayItems)
    XCTAssertEqual(brief.somedayItems, read.somedayItems)
  }

  /// Regression: an archived list with stale open tasks must not resurface in
  /// the stalled-lists section or its `total_matching`, matching every other
  /// list read that hides archived lists (archiving leaves the tasks intact).
  func testStalledListsExcludeArchivedLists() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      try insertList(db, id: "active", name: "Active")
      try db.execute(
        sql: "INSERT INTO lists (id, name, version, created_at, updated_at, archived_at) "
          + "VALUES (?, ?, ?, ?, ?, ?)",
        arguments: [
          "archived", "Archived", Self.version, Self.staleTs, Self.staleTs, Self.staleTs,
        ])
      try insertTask(
        db, id: "active-task", title: "Active stale", listId: "active", updatedAt: Self.staleTs)
      try insertTask(
        db, id: "archived-task", title: "Archived stale", listId: "archived",
        updatedAt: Self.staleTs)
    }

    let (read, brief) = try store.writer.read {
      db -> (WeeklyReview.ReadModel, WeeklyReview.Brief) in
      let read = try WeeklyReview.loadWeeklyReview(
        db,
        limits: .init(
          completedThisWeek: 10, stalledLists: 10, frequentlyDeferred: 10, overdueTasks: 10,
          somedayItems: 10))
      let brief = try WeeklyReview.loadWeeklyReviewBrief(
        db,
        limits: .init(
          completedThisWeek: 10, stalledLists: 10, frequentlyDeferred: 10, somedayItems: 10))
      return (read, brief)
    }

    XCTAssertEqual(read.stalledLists.map { $0.id }, ["active"])
    XCTAssertEqual(brief.stalledLists.map { $0.id }, ["active"])
    XCTAssertEqual(brief.sectionMeta.stalledLists.totalMatching, 1)
  }
}
