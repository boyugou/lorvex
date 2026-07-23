import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

/// Day-surface visibility tests for the `available_from` (defer-until) filter,
/// including the OVERDUE-WINS rule: a task hidden by a future `available_from`
/// drops out of day surfaces unless it is overdue, in which case it always
/// surfaces (never silently suppress a missed deadline).
final class TaskAvailableFromFilterTests: XCTestCase {
  private let today = "2026-06-15"

  private func insertTask(
    _ db: Database,
    _ id: String,
    status: String = "open",
    dueDate: String? = nil,
    plannedDate: String? = nil,
    availableFrom: String? = nil,
    priority: Int64? = nil
  ) throws {
    try db.execute(
      sql: """
        INSERT INTO tasks (id, title, status, due_date, planned_date, available_from, priority, \
        list_id, version, created_at, updated_at, defer_count) \
        VALUES (?, ?, ?, ?, ?, ?, ?, 'inbox', \
        '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00.000Z', \
        '2026-01-01T00:00:00.000Z', 0)
        """,
      arguments: [id, id, status, dueDate, plannedDate, availableFrom, priority])
  }

  private func ids(_ rows: [TaskRow]) -> [String] { rows.map { $0.core.id } }

  /// Seed the canonical fixture:
  /// - `visible`   planned today, no `available_from` → shown.
  /// - `boundary`  planned today, `available_from == today` → shown (inclusive).
  /// - `hidden`    planned today, `available_from` in the future → hidden.
  /// - `overdue`   due in the past, `available_from` in the future → overdue-wins.
  /// - `scheduled` planned in the future, `available_from` in the future, no due.
  private func seedFixture(_ store: LorvexStore) throws {
    try store.writer.write { db in
      try self.insertTask(db, "visible", plannedDate: self.today, priority: 1)
      try self.insertTask(
        db, "boundary", plannedDate: self.today, availableFrom: self.today, priority: 1)
      try self.insertTask(
        db, "hidden", plannedDate: self.today, availableFrom: "2026-06-20", priority: 1)
      try self.insertTask(
        db, "overdue", dueDate: "2026-06-10", availableFrom: "2026-06-20", priority: 1)
      try self.insertTask(
        db, "scheduled", plannedDate: "2026-06-25", availableFrom: "2026-06-25", priority: 1)
    }
  }

  // MARK: - Today pool

  func testHiddenExcludedFromTodayPoolButBoundaryVisible() throws {
    let store = try TestSupport.freshStore()
    try seedFixture(store)
    let pool = try store.writer.read { db in
      try TaskRepo.Read.getTodayTasks(
        db, predicate: TodayPredicate(date: IsoDate.YMD(year: 2026, month: 6, day: 15)),
        page: .default)
    }
    let poolIds = Set(ids(pool))
    XCTAssertTrue(poolIds.contains("visible"))
    XCTAssertTrue(poolIds.contains("boundary"), "available_from == today is visible")
    XCTAssertFalse(poolIds.contains("hidden"), "available_from > today is hidden")
    XCTAssertFalse(poolIds.contains("scheduled"))
    // The today pool never contains overdue rows regardless of hiding.
    XCTAssertFalse(poolIds.contains("overdue"))
  }

  // MARK: - Day-bucket counts

  func testDayBucketCountsExcludeHiddenButCountOverdue() throws {
    let store = try TestSupport.freshStore()
    try seedFixture(store)
    let parsed = try XCTUnwrap({ () -> IsoDate.YMD? in
      if case .success(let d) = IsoDate.parseIsoDate(self.today) { return d }
      return nil
    }())
    let counts = try store.writer.read { db in
      try TaskRepo.Read.countOpenTaskDayBuckets(db, asOfDate: parsed, upcomingDays: 30)
    }
    // today pool: visible + boundary (hidden excluded).
    XCTAssertEqual(counts.todayPool, 2)
    // overdue: the overdue-hidden task still counts.
    XCTAssertEqual(counts.overdue, 1)
    // upcoming (next 30d): `scheduled` is hidden (available_from in future) → excluded.
    XCTAssertEqual(counts.upcoming, 0)
  }

  // MARK: - Overview top-tasks pool

  func testGetOpenTasksByPriorityExcludesHidden() throws {
    let store = try TestSupport.freshStore()
    try seedFixture(store)
    let rows = try store.writer.read { db in
      try TaskRepo.Read.getOpenTasksByPriority(db, today: self.today, limit: 100)
    }
    let got = Set(ids(rows))
    XCTAssertTrue(got.isSuperset(of: ["visible", "boundary", "overdue"]))
    XCTAssertFalse(got.contains("hidden"))
    XCTAssertFalse(got.contains("scheduled"))
  }

  // MARK: - Scheduled section

  func testScheduledSectionReturnsHiddenNotOverdueOrderedByAvailableFrom() throws {
    let store = try TestSupport.freshStore()
    try seedFixture(store)
    let rows = try store.writer.read { db in
      try TaskRepo.Read.getScheduledTasks(db, today: self.today, limit: 100, offset: 0)
    }
    let got = ids(rows)
    // `hidden` (available_from 06-20) then `scheduled` (06-25), ordered ascending.
    XCTAssertEqual(got, ["hidden", "scheduled"])
    XCTAssertFalse(got.contains("overdue"), "overdue tasks never appear in the Scheduled section")
    XCTAssertFalse(got.contains("visible"))
    let count = try store.writer.read { db in
      try TaskRepo.Read.countScheduledTasks(db, today: self.today)
    }
    XCTAssertEqual(count, 2)
  }

  // MARK: - list_tasks availability filter (OPEN lane)

  private func listOpen(
    _ store: LorvexStore, availability: TaskRepo.TaskAvailabilityFilter
  ) throws -> Set<String> {
    let rows = try store.writer.read { db -> [TaskRow] in
      let query = TaskRepo.ListTasksQuery(
        status: .open, availability: availability, today: self.today, limit: 500)
      return try TaskRepo.Read.listTasks(db, query: query).rows
    }
    return Set(ids(rows))
  }

  func testListTasksAvailabilityVisibleHiddenAll() throws {
    let store = try TestSupport.freshStore()
    try seedFixture(store)

    let visible = try listOpen(store, availability: .visible)
    XCTAssertEqual(visible, ["visible", "boundary", "overdue"])

    let hidden = try listOpen(store, availability: .hidden)
    XCTAssertEqual(hidden, ["hidden", "scheduled"], "overdue-hidden is not 'hidden' — it wins")

    let all = try listOpen(store, availability: .all)
    XCTAssertEqual(all, ["visible", "boundary", "hidden", "overdue", "scheduled"])
  }

  func testListTasksVisibilityIgnoredWithoutTodayOrNonOpenLane() throws {
    let store = try TestSupport.freshStore()
    try seedFixture(store)
    // No `today` → no visibility predicate even with availability=.visible.
    let noToday = try store.writer.read { db -> [TaskRow] in
      let q = TaskRepo.ListTasksQuery(status: .open, availability: .visible, limit: 500)
      return try TaskRepo.Read.listTasks(db, query: q).rows
    }
    XCTAssertEqual(Set(ids(noToday)).count, 5, "no today → never truncated")
  }

  func testListTasksAvailableFromRangeFilter() throws {
    let store = try TestSupport.freshStore()
    try seedFixture(store)
    let rows = try store.writer.read { db -> [TaskRow] in
      let q = TaskRepo.ListTasksQuery(
        status: .open,
        availableFromRange: TaskRepo.TaskDateRange(from: "2026-06-21", to: "2026-06-30"),
        limit: 500)
      return try TaskRepo.Read.listTasks(db, query: q).rows
    }
    // Only `scheduled` (available_from 06-25) falls in [06-21, 06-30].
    XCTAssertEqual(Set(ids(rows)), ["scheduled"])
  }

  // MARK: - Focus auto-proposal candidates (DECISION #5)

  func testFocusCandidatesExcludeHidden() throws {
    let store = try TestSupport.freshStore()
    try seedFixture(store)
    let candidates = try store.writer.read { db in
      try FocusScheduleProposal.loadTaskCandidates(
        db, taskIds: ["visible", "hidden", "boundary", "overdue"], asOf: self.today)
    }
    let got = Set(candidates.map(\.id))
    XCTAssertTrue(got.contains("visible"))
    XCTAssertTrue(got.contains("boundary"))
    XCTAssertTrue(got.contains("overdue"), "overdue-wins: still a focus candidate")
    XCTAssertFalse(got.contains("hidden"), "hidden tasks are excluded from auto-proposal")
  }
}
