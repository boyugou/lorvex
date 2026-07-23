import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Weekly-review read models shared by the app and MCP surfaces.
///
/// Three entry points compose the same window math, count queries, and row
/// mappers into different consumer shapes:
/// - `loadWeeklyReview` — the desktop app's full read model.
/// - `loadWeeklyReviewSnapshot` — a compact MCP "current snapshot" response.
/// - `loadWeeklyReviewBrief` — the conversational "what changed this week?"
///   briefing carrying per-section `total_matching` coverage.
///
/// The caller owns the read transaction.
public enum WeeklyReview {
  /// Trailing-day window for every weekly-review entry point.
  public static let days: Int64 = 7
  /// Upper bound on per-section row caps; validators reject caps outside
  /// `1...limitCap`.
  public static let limitCap: UInt32 = 500

  static let frequentlyDeferredMinCount: Int64 = 3

  // MARK: - Wire types

  public struct Window: Sendable, Equatable {
    public let from: String
    public let to: String
    public let startUtc: String
    public let endUtc: String
    public let days: Int64
  }

  public struct Counts: Sendable, Equatable {
    public let completedThisWeek: Int64
    public let createdThisWeek: Int64
    public let overdueOpen: Int64
    public let deferredOpen: Int64
    public let someday: Int64
  }

  public struct EstimateSummary: Sendable, Equatable {
    public let completedTotal: Int64
    public let completedWithEstimateCount: Int64
    public let estimateCoverageRatio: Double?
  }

  public struct TaskItem: Sendable, Equatable {
    public let id: String
    public let title: String
    public let listId: String
    public let status: String
    public let completedAt: String?
    public let dueDate: LorvexDate?
    public let deferCount: Int64
  }

  public struct StalledList: Sendable, Equatable {
    public let id: String
    public let name: String
    public let icon: String?
    public let color: String?
    public let openTaskCount: Int64
    public let lastActivity: String?
  }

  public struct Limits: Sendable, Equatable {
    public let completedThisWeek: UInt32
    public let stalledLists: UInt32
    public let frequentlyDeferred: UInt32
    public let overdueTasks: UInt32
    public let somedayItems: UInt32

    public init(
      completedThisWeek: UInt32, stalledLists: UInt32, frequentlyDeferred: UInt32,
      overdueTasks: UInt32, somedayItems: UInt32
    ) {
      self.completedThisWeek = completedThisWeek
      self.stalledLists = stalledLists
      self.frequentlyDeferred = frequentlyDeferred
      self.overdueTasks = overdueTasks
      self.somedayItems = somedayItems
    }
  }

  public struct SnapshotLimits: Sendable, Equatable {
    public let topCompleted: UInt32
    public let stalledLists: UInt32
    public let frequentlyDeferred: UInt32
    public let somedayItems: UInt32

    public init(
      topCompleted: UInt32, stalledLists: UInt32, frequentlyDeferred: UInt32, somedayItems: UInt32
    ) {
      self.topCompleted = topCompleted
      self.stalledLists = stalledLists
      self.frequentlyDeferred = frequentlyDeferred
      self.somedayItems = somedayItems
    }
  }

  public struct BriefLimits: Sendable, Equatable {
    public let completedThisWeek: UInt32
    public let stalledLists: UInt32
    public let frequentlyDeferred: UInt32
    public let somedayItems: UInt32

    public init(
      completedThisWeek: UInt32, stalledLists: UInt32, frequentlyDeferred: UInt32,
      somedayItems: UInt32
    ) {
      self.completedThisWeek = completedThisWeek
      self.stalledLists = stalledLists
      self.frequentlyDeferred = frequentlyDeferred
      self.somedayItems = somedayItems
    }
  }

  public struct BriefSectionEntry: Sendable, Equatable {
    public let limit: UInt32
    public let totalMatching: Int64
    public let returned: Int
    public let truncated: Bool
  }

  public struct BriefSectionMeta: Sendable, Equatable {
    public let completedThisWeek: BriefSectionEntry
    public let stalledLists: BriefSectionEntry
    public let frequentlyDeferred: BriefSectionEntry
    public let somedayItems: BriefSectionEntry
  }

  public struct ReadModel: Sendable, Equatable {
    public let window: Window
    public let counts: Counts
    public let estimateSummary: EstimateSummary
    public let completedThisWeek: [TaskItem]
    public let stalledLists: [StalledList]
    public let frequentlyDeferred: [TaskItem]
    public let overdueTasks: [TaskItem]
    public let somedayItems: [TaskItem]
    public let limits: Limits
  }

  public struct Snapshot: Sendable, Equatable {
    public let window: Window
    public let counts: Counts
    public let estimateSummary: EstimateSummary
    public let topCompleted: [TaskItem]
    public let stalledLists: [StalledList]
    public let frequentlyDeferred: [TaskItem]
    public let somedayItems: [TaskItem]
    public let limits: SnapshotLimits
  }

  public struct Brief: Sendable, Equatable {
    public let window: Window
    public let completedThisWeek: [TaskItem]
    public let stalledLists: [StalledList]
    public let frequentlyDeferred: [TaskItem]
    public let overdueCount: Int64
    public let somedayItems: [TaskItem]
    public let createdThisWeek: Int64
    public let estimateSummary: EstimateSummary
    public let sectionMeta: BriefSectionMeta
  }

  // MARK: - SQL constants

  static let completedThisWeekCountSQL = """
    SELECT COUNT(*) FROM tasks
         WHERE status = 'completed'
           AND tasks.archived_at IS NULL
           AND completed_at >= ?1
           AND completed_at < ?2
    """
  static let createdThisWeekCountSQL = """
    SELECT COUNT(*) FROM tasks
         WHERE tasks.archived_at IS NULL
           AND created_at >= ?1
           AND created_at < ?2
    """
  static let completedItemsSQL = """
    SELECT id, title, list_id, status, completed_at, due_date, defer_count
         FROM tasks
         WHERE status = 'completed'
           AND tasks.archived_at IS NULL
           AND completed_at >= ?1
           AND completed_at < ?2
         ORDER BY completed_at DESC, id ASC
         LIMIT ?3
    """
  static let stalledListsSQL = """
    SELECT l.id, l.name, l.icon, l.color,
                COUNT(t.id) AS open_task_count,
                MAX(datetime(t.updated_at)) AS last_activity
         FROM lists l
         JOIN tasks t ON t.list_id = l.id AND t.status IN (\(StatusName.actionableStatusSqlList)) AND t.archived_at IS NULL
         WHERE l.archived_at IS NULL
         GROUP BY l.id
         HAVING last_activity < datetime(?1)
         ORDER BY open_task_count DESC, last_activity ASC, l.id ASC
         LIMIT ?2
    """
  static let stalledTotalSQL = """
    SELECT COUNT(*) FROM (
            SELECT l.id
            FROM lists l
            JOIN tasks t ON t.list_id = l.id AND t.status IN (\(StatusName.actionableStatusSqlList)) AND t.archived_at IS NULL
            WHERE l.archived_at IS NULL
            GROUP BY l.id
            HAVING MAX(datetime(t.updated_at)) < datetime(?1)
        )
    """
  static let overdueItemsSQL = """
    SELECT id, title, list_id, status, completed_at, due_date, defer_count
         FROM tasks
         WHERE status IN (\(StatusName.actionableStatusSqlList))
           AND due_date IS NOT NULL
           AND due_date < ?1
           AND tasks.archived_at IS NULL
         ORDER BY due_date ASC, priority_effective ASC, id ASC
         LIMIT ?2
    """
  static let somedayItemsSQL = """
    SELECT id, title, list_id, status, completed_at, due_date, defer_count
         FROM tasks
         WHERE status = 'someday' AND tasks.archived_at IS NULL
         ORDER BY created_at DESC, id ASC
         LIMIT ?1
    """

  static func deferredItemsSQL() -> String {
    """
    SELECT id, title, list_id, status, completed_at, due_date, defer_count
             FROM tasks
             WHERE status IN (\(StatusName.actionableStatusSqlList)) AND tasks.archived_at IS NULL AND defer_count >= ?1
             ORDER BY defer_count DESC, \(TaskRepo.taskOrderBy)
             LIMIT ?2
    """
  }

  // MARK: - Window

  struct QueryWindow {
    let model: Window
    let startUtc: String
    let endUtc: String
    let toDay: String
  }

  /// `endingOn` anchors the 7-day window's final day; `nil` means today
  /// (the trailing window). Past weeks are first-class — the MCP snapshot
  /// tool's `week_of` lands here.
  static func loadWeeklyReviewWindow(_ db: Database, endingOn anchorDay: String? = nil) throws
    -> QueryWindow
  {
    let window: TrailingDayWindowUtcBounds
    if let anchorDay {
      window = try WorkflowTimezone.dayWindowUtcBoundsForConn(
        db, endingOn: anchorDay, spanDays: Int(days))
    } else {
      window = try WorkflowTimezone.trailingDayWindowUtcBoundsForConn(db, spanDays: Int(days))
    }
    return QueryWindow(
      model: Window(
        from: window.fromDay, to: window.toDay, startUtc: window.startUtc,
        endUtc: window.endUtc, days: days),
      startUtc: window.startUtc, endUtc: window.endUtc, toDay: window.toDay)
  }

  // MARK: - Row mappers / section loaders

  static func queryCount(_ db: Database, _ sql: String, _ args: StatementArguments) throws -> Int64
  {
    try Int64.fetchOne(db, sql: sql, arguments: args) ?? 0
  }

  static func taskItemFromRow(_ row: Row) -> TaskItem {
    let rawDue: String? = row[5]
    let due: LorvexDate? = rawDue.flatMap {
      if case .success(let d) = LorvexDate.parse($0) { return d } else { return nil }
    }
    return TaskItem(
      id: row[0], title: row[1], listId: row[2], status: row[3], completedAt: row[4],
      dueDate: due, deferCount: row[6])
  }

  static func loadTaskItems(_ db: Database, _ sql: String, _ args: StatementArguments) throws
    -> [TaskItem]
  {
    try Row.fetchAll(db, sql: sql, arguments: args).map(taskItemFromRow)
  }

  static func loadStalledLists(_ db: Database, startUtc: String, limit: UInt32) throws
    -> [StalledList]
  {
    let rows = try Row.fetchAll(db, sql: stalledListsSQL, arguments: [startUtc, limit])
    return rows.map { row in
      StalledList(
        id: row[0], name: row[1], icon: row[2], color: row[3],
        openTaskCount: row[4], lastActivity: row[5])
    }
  }

  static func loadEstimateSummary(_ db: Database, startUtc: String, endUtc: String) throws
    -> EstimateSummary
  {
    let s = try ReviewMetrics.loadTaskEstimateSummary(
      db, windowStartUtc: startUtc, windowEndUtc: endUtc)
    return EstimateSummary(
      completedTotal: s.completedTotal,
      completedWithEstimateCount: s.completedWithEstimateCount,
      estimateCoverageRatio: s.estimateCoverageRatio)
  }

  static func loadCounts(_ db: Database, window: QueryWindow) throws -> Counts {
    Counts(
      completedThisWeek: try queryCount(
        db, completedThisWeekCountSQL, [window.startUtc, window.endUtc]),
      createdThisWeek: try queryCount(
        db, createdThisWeekCountSQL, [window.startUtc, window.endUtc]),
      overdueOpen: try ReviewMetrics.overdueOpenCount(db, todayYmd: window.toDay),
      deferredOpen: try ReviewMetrics.deferredOpenCount(db, minCount: frequentlyDeferredMinCount),
      someday: try ReviewMetrics.somedayCount(db))
  }

  // MARK: - Validation

  static func validateLimit(_ name: String, _ value: UInt32) throws {
    if value == 0 || value > limitCap {
      throw StoreError.validation("\(name) must be between 1 and \(limitCap)")
    }
  }

  // MARK: - Entry points

  /// Full weekly-review read model. `endingOn` anchors the window's final
  /// day, `nil` = today.
  public static func loadWeeklyReview(
    _ db: Database, limits: Limits, endingOn anchorDay: String? = nil
  ) throws -> ReadModel {
    try validateLimit("completed_this_week", limits.completedThisWeek)
    try validateLimit("stalled_lists", limits.stalledLists)
    try validateLimit("frequently_deferred", limits.frequentlyDeferred)
    try validateLimit("overdue_tasks", limits.overdueTasks)
    try validateLimit("someday_items", limits.somedayItems)

    let window = try loadWeeklyReviewWindow(db, endingOn: anchorDay)
    let counts = try loadCounts(db, window: window)
    let completed = try loadTaskItems(
      db, completedItemsSQL, [window.startUtc, window.endUtc, limits.completedThisWeek])
    let stalled = try loadStalledLists(db, startUtc: window.startUtc, limit: limits.stalledLists)
    let deferred = try loadTaskItems(
      db, deferredItemsSQL(), [frequentlyDeferredMinCount, limits.frequentlyDeferred])
    let overdue = try loadTaskItems(db, overdueItemsSQL, [window.toDay, limits.overdueTasks])
    let someday = try loadTaskItems(db, somedayItemsSQL, [limits.somedayItems])
    let estimate = try loadEstimateSummary(db, startUtc: window.startUtc, endUtc: window.endUtc)

    return ReadModel(
      window: window.model, counts: counts, estimateSummary: estimate,
      completedThisWeek: completed, stalledLists: stalled, frequentlyDeferred: deferred,
      overdueTasks: overdue, somedayItems: someday, limits: limits)
  }

  /// Compact MCP snapshot.
  public static func loadWeeklyReviewSnapshot(
    _ db: Database, limits: SnapshotLimits, endingOn anchorDay: String? = nil
  ) throws
    -> Snapshot
  {
    try validateLimit("top_completed", limits.topCompleted)
    try validateLimit("stalled_lists", limits.stalledLists)
    try validateLimit("frequently_deferred", limits.frequentlyDeferred)
    try validateLimit("someday_items", limits.somedayItems)

    let window = try loadWeeklyReviewWindow(db, endingOn: anchorDay)
    let counts = try loadCounts(db, window: window)
    let topCompleted = try loadTaskItems(
      db, completedItemsSQL, [window.startUtc, window.endUtc, limits.topCompleted])
    let stalled = try loadStalledLists(db, startUtc: window.startUtc, limit: limits.stalledLists)
    let deferred = try loadTaskItems(
      db, deferredItemsSQL(), [frequentlyDeferredMinCount, limits.frequentlyDeferred])
    let someday = try loadTaskItems(db, somedayItemsSQL, [limits.somedayItems])
    let estimate = try loadEstimateSummary(db, startUtc: window.startUtc, endUtc: window.endUtc)

    return Snapshot(
      window: window.model, counts: counts, estimateSummary: estimate,
      topCompleted: topCompleted, stalledLists: stalled, frequentlyDeferred: deferred,
      somedayItems: someday, limits: limits)
  }

  static func sectionEntry(limit: UInt32, totalMatching: Int64, returned: Int) -> BriefSectionEntry
  {
    BriefSectionEntry(
      limit: limit, totalMatching: totalMatching, returned: returned,
      truncated: totalMatching > Int64(returned))
  }

  /// Conversational brief with per-section coverage.
  public static func loadWeeklyReviewBrief(_ db: Database, limits: BriefLimits) throws -> Brief {
    try validateLimit("completed_this_week", limits.completedThisWeek)
    try validateLimit("stalled_lists", limits.stalledLists)
    try validateLimit("frequently_deferred", limits.frequentlyDeferred)
    try validateLimit("someday_items", limits.somedayItems)

    let window = try loadWeeklyReviewWindow(db)
    let completedTotal = try queryCount(
      db, completedThisWeekCountSQL, [window.startUtc, window.endUtc])
    let completed = try loadTaskItems(
      db, completedItemsSQL, [window.startUtc, window.endUtc, limits.completedThisWeek])
    let stalledTotal = try queryCount(db, stalledTotalSQL, [window.startUtc])
    let stalled = try loadStalledLists(db, startUtc: window.startUtc, limit: limits.stalledLists)
    let deferredTotal = try ReviewMetrics.deferredOpenCount(
      db, minCount: frequentlyDeferredMinCount)
    let deferred = try loadTaskItems(
      db, deferredItemsSQL(), [frequentlyDeferredMinCount, limits.frequentlyDeferred])
    let overdueCount = try ReviewMetrics.overdueOpenCount(db, todayYmd: window.toDay)
    let somedayTotal = try ReviewMetrics.somedayCount(db)
    let someday = try loadTaskItems(db, somedayItemsSQL, [limits.somedayItems])
    let createdThisWeek = try queryCount(
      db, createdThisWeekCountSQL, [window.startUtc, window.endUtc])
    let estimate = try loadEstimateSummary(db, startUtc: window.startUtc, endUtc: window.endUtc)

    return Brief(
      window: window.model, completedThisWeek: completed, stalledLists: stalled,
      frequentlyDeferred: deferred, overdueCount: overdueCount, somedayItems: someday,
      createdThisWeek: createdThisWeek, estimateSummary: estimate,
      sectionMeta: BriefSectionMeta(
        completedThisWeek: sectionEntry(
          limit: limits.completedThisWeek, totalMatching: completedTotal,
          returned: completed.count),
        stalledLists: sectionEntry(
          limit: limits.stalledLists, totalMatching: stalledTotal, returned: stalled.count),
        frequentlyDeferred: sectionEntry(
          limit: limits.frequentlyDeferred, totalMatching: deferredTotal,
          returned: deferred.count),
        somedayItems: sectionEntry(
          limit: limits.somedayItems, totalMatching: somedayTotal, returned: someday.count)))
  }
}
