import Foundation
import GRDB
import LorvexDomain

extension TaskRepo.Read {

  // MARK: - Today

  /// Open tasks in the canonical today-pool bucket. Ordered by
  /// ``TaskRepo/taskOrderBy``.
  public static func getTodayTasks(
    _ db: Database, predicate: TodayPredicate, page: Pagination
  ) throws -> [TaskRow] {
    let date = predicate.date.canonicalString
    let pred = TaskReadBuckets.todayPoolBucketPredicate(
      taskAlias: "tasks", datePlaceholder: "?1")
    let visible = TaskReadBuckets.availableVisibilityPredicate(
      taskAlias: "tasks", datePlaceholder: "?1")
    let sql = """
      SELECT \(TaskRepo.taskColumns) FROM tasks \
      WHERE status IN (\(StatusName.actionableStatusSqlList)) \
      AND tasks.archived_at IS NULL \
      AND \(pred) \
      AND \(visible) \
      ORDER BY \(TaskRepo.taskOrderBy) \
      LIMIT ?2 OFFSET ?3
      """
    let rows = try Row.fetchAll(
      db, sql: sql, arguments: [date, Int64(page.limit), Int64(page.offset)])
    return try rows.map(TaskRepo.rowToTaskRow)
  }

  /// Count of open tasks in the today-pool bucket.
  public static func countTodayTasks(
    _ db: Database, predicate: TodayPredicate
  ) throws -> Int64 {
    let date = predicate.date.canonicalString
    let pred = TaskReadBuckets.todayPoolBucketPredicate(
      taskAlias: "tasks", datePlaceholder: "?1")
    let visible = TaskReadBuckets.availableVisibilityPredicate(
      taskAlias: "tasks", datePlaceholder: "?1")
    let sql = """
      SELECT COUNT(*) FROM tasks \
      WHERE status IN (\(StatusName.actionableStatusSqlList)) \
      AND tasks.archived_at IS NULL \
      AND \(pred) \
      AND \(visible)
      """
    return try Int64.fetchOne(db, sql: sql, arguments: [date]) ?? 0
  }

  // MARK: - Scheduled (defer-until / hidden)

  /// Open tasks currently hidden by `available_from` (defer-until) and not yet
  /// overdue — the "Scheduled" section. A row qualifies when
  /// `available_from > today` AND it is not overdue (`hiddenScheduledPredicate`,
  /// the exact negation of the day-surface visibility filter). Ordered
  /// date-first by `available_from ASC` with the canonical task key as the
  /// secondary tiebreaker (see `docs/design/SORT_KEYS.md`).
  public static func getScheduledTasks(
    _ db: Database, today: String, limit: UInt32, offset: UInt32
  ) throws -> [TaskRow] {
    let normalized = try normalizeToday(today)
    let hidden = TaskReadBuckets.hiddenScheduledPredicate(
      taskAlias: "tasks", datePlaceholder: "?1")
    let sql = """
      SELECT \(TaskRepo.taskColumns) FROM tasks \
      WHERE status IN (\(StatusName.actionableStatusSqlList)) \
        AND tasks.archived_at IS NULL \
        AND \(hidden) \
      ORDER BY tasks.available_from ASC, \(TaskRepo.taskOrderBy) \
      LIMIT ?2 OFFSET ?3
      """
    let rows = try Row.fetchAll(
      db, sql: sql, arguments: [normalized, Int64(limit), Int64(offset)])
    return try rows.map(TaskRepo.rowToTaskRow)
  }

  /// Count of open tasks in the Scheduled (hidden-and-not-overdue) section.
  public static func countScheduledTasks(
    _ db: Database, today: String
  ) throws -> Int64 {
    let normalized = try normalizeToday(today)
    let hidden = TaskReadBuckets.hiddenScheduledPredicate(
      taskAlias: "tasks", datePlaceholder: "?1")
    let sql = """
      SELECT COUNT(*) FROM tasks \
      WHERE status IN (\(StatusName.actionableStatusSqlList)) \
        AND tasks.archived_at IS NULL \
        AND \(hidden)
      """
    return try Int64.fetchOne(db, sql: sql, arguments: [normalized]) ?? 0
  }

  // MARK: - Upcoming

  /// Open tasks whose effective action date falls in `(from, from+days]`,
  /// excluding overdue / today-pool members. Ordered by
  /// `COALESCE(planned_date, due_date) ASC, priority_effective ASC,
  /// created_at DESC, id ASC`.
  public static func getUpcomingTasks(
    _ db: Database, predicate: UpcomingPredicate, page: Pagination
  ) throws -> [TaskRow] {
    let from = predicate.fromDate.canonicalString
    let to = IsoDate.addingDays(predicate.fromDate, Int(predicate.days))
      .canonicalString
    let pred = TaskReadBuckets.upcomingBucketPredicate(
      taskAlias: "tasks", fromPlaceholder: "?1", toPlaceholder: "?2")
    let visible = TaskReadBuckets.availableVisibilityPredicate(
      taskAlias: "tasks", datePlaceholder: "?1")
    let sql = """
      SELECT \(TaskRepo.taskColumns) FROM tasks \
      WHERE status IN (\(StatusName.actionableStatusSqlList)) \
      AND tasks.archived_at IS NULL \
      AND \(pred) \
      AND \(visible) \
      ORDER BY COALESCE(planned_date, due_date) ASC, priority_effective ASC, created_at DESC, id ASC \
      LIMIT ?3 OFFSET ?4
      """
    let rows = try Row.fetchAll(
      db, sql: sql,
      arguments: [from, to, Int64(page.limit), Int64(page.offset)])
    return try rows.map(TaskRepo.rowToTaskRow)
  }

  public static func countUpcomingTasks(
    _ db: Database, predicate: UpcomingPredicate
  ) throws -> Int64 {
    let from = predicate.fromDate.canonicalString
    let to = IsoDate.addingDays(predicate.fromDate, Int(predicate.days))
      .canonicalString
    let pred = TaskReadBuckets.upcomingBucketPredicate(
      taskAlias: "tasks", fromPlaceholder: "?1", toPlaceholder: "?2")
    let visible = TaskReadBuckets.availableVisibilityPredicate(
      taskAlias: "tasks", datePlaceholder: "?1")
    let sql = """
      SELECT COUNT(*) FROM tasks \
      WHERE status IN (\(StatusName.actionableStatusSqlList)) \
      AND tasks.archived_at IS NULL \
      AND \(pred) \
      AND \(visible)
      """
    return try Int64.fetchOne(db, sql: sql, arguments: [from, to]) ?? 0
  }

  // MARK: - Open task day bucket counts

  /// Canonical counts for the mutually-exclusive open-task day buckets.
  public struct OpenTaskDayBucketCounts: Sendable, Equatable {
    public let overdue: Int64
    public let todayPool: Int64
    public let upcoming: Int64
  }

  /// Count the three open-task day buckets from one shared SELECT.
  public static func countOpenTaskDayBuckets(
    _ db: Database, asOfDate: IsoDate.YMD, upcomingDays: UInt32
  ) throws -> OpenTaskDayBucketCounts {
    let from = asOfDate.canonicalString
    let to = IsoDate.addingDays(asOfDate, Int(upcomingDays)).canonicalString
    let overdue = TaskReadBuckets.overdueBucketPredicate(
      taskAlias: "tasks", datePlaceholder: "?1")
    let todayPool = TaskReadBuckets.todayPoolBucketPredicate(
      taskAlias: "tasks", datePlaceholder: "?1")
    let upcoming = TaskReadBuckets.upcomingBucketPredicate(
      taskAlias: "tasks", fromPlaceholder: "?1", toPlaceholder: "?2")
    // Overdue-wins: the OVERDUE column never applies the visibility filter, so a
    // hidden-but-overdue task is counted as overdue. Today-pool and upcoming
    // rows are non-overdue by construction, so hidden ones drop out of those
    // counts.
    let visible = TaskReadBuckets.availableVisibilityPredicate(
      taskAlias: "tasks", datePlaceholder: "?1")
    let sql = """
      SELECT \
         SUM(CASE WHEN \(overdue) THEN 1 ELSE 0 END) AS overdue, \
         SUM(CASE WHEN \(todayPool) AND \(visible) THEN 1 ELSE 0 END) AS today_pool, \
         SUM(CASE WHEN \(upcoming) AND \(visible) THEN 1 ELSE 0 END) AS upcoming \
      FROM tasks \
      WHERE status IN (\(StatusName.actionableStatusSqlList)) AND tasks.archived_at IS NULL
      """
    let row = try Row.fetchOne(db, sql: sql, arguments: [from, to])
    let o: Int64? = row?[0]
    let t: Int64? = row?[1]
    let u: Int64? = row?[2]
    return OpenTaskDayBucketCounts(
      overdue: o ?? 0, todayPool: t ?? 0, upcoming: u ?? 0)
  }

  // MARK: - Deferred

  /// Open tasks with `defer_count >= 1`, ordered by deferral pressure
  /// (`defer_count DESC, id ASC`). `listId == nil` returns the global
  /// view; supplying a list scopes to that list.
  public static func getDeferredTasks(
    _ db: Database, listId: String? = nil, page: Pagination
  ) throws -> [TaskRow] {
    let listClause = listId == nil ? "" : " AND list_id = ?1"
    let limOffset = listId == nil
      ? " LIMIT ?1 OFFSET ?2"
      : " LIMIT ?2 OFFSET ?3"
    let sql = """
      SELECT \(TaskRepo.taskColumns) FROM tasks \
      WHERE status IN (\(StatusName.actionableStatusSqlList)) AND defer_count >= 1 AND tasks.archived_at IS NULL\(listClause) \
      ORDER BY defer_count DESC, id ASC\(limOffset)
      """
    let rows: [Row]
    if let listId {
      rows = try Row.fetchAll(
        db, sql: sql,
        arguments: [listId, Int64(page.limit), Int64(page.offset)])
    } else {
      rows = try Row.fetchAll(
        db, sql: sql,
        arguments: [Int64(page.limit), Int64(page.offset)])
    }
    return try rows.map(TaskRepo.rowToTaskRow)
  }

  /// Count open tasks with `defer_count >= 1`.
  public static func countDeferredTasks(
    _ db: Database, listId: String? = nil
  ) throws -> Int64 {
    let listClause = listId == nil ? "" : " AND list_id = ?"
    let sql = """
      SELECT COUNT(*) FROM tasks \
      WHERE status IN (\(StatusName.actionableStatusSqlList)) AND defer_count >= 1 AND tasks.archived_at IS NULL\(listClause)
      """
    if let listId {
      return try Int64.fetchOne(db, sql: sql, arguments: [listId]) ?? 0
    }
    return try Int64.fetchOne(db, sql: sql) ?? 0
  }

  // MARK: - Helpers

  private static func normalizeToday(_ today: String) throws -> String {
    switch IsoDate.parseIsoDate(today) {
    case .success(let d): return d.canonicalString
    case .failure(let e):
      throw StoreError.validation(
        "invalid today date \"\(today)\": \(e.description)")
    }
  }
}
