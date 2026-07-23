import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Single-day "evidence" read model backing the Review-surface day panel.
///
/// Composes the same window math, count queries, and row mappers
/// ``WeeklyReview`` / ``ReviewMetrics`` use, scoped to one local calendar day:
/// the day a task was completed/created (UTC-bounded via the single-day
/// ``WorkflowTimezone`` window), the still-open tasks that were due that day,
/// habit activity for the day, and calendar events overlapping it.
///
/// The caller owns the read transaction. Every clause reuses the conventions
/// encoded in ``WeeklyReview`` (UTC day bounds, `archived_at IS NULL`, the
/// canonical task ORDER BY, `value >= target_count` for habit "completed").
public enum DayReview {
  /// Upper bound on the completed-tasks row cap; validators reject caps
  /// outside `1...limitCap`. Matches the weekly-review section semantics.
  public static let limitCap: UInt32 = 50

  public struct TaskItem: Sendable, Equatable {
    public let id: String
    public let title: String
    public let status: String
    public let deferCount: Int64
  }

  public struct DaySummary: Sendable, Equatable {
    public let date: String
    public let completedCount: Int64
    public let topCompleted: [TaskItem]
    public let createdCount: Int64
    public let dueOpenCount: Int64
    public let habitsCompleted: Int64
    public let habitsTotal: Int64
    public let eventCount: Int64
  }

  // MARK: - SQL constants

  static let completedCountSQL = """
    SELECT COUNT(*) FROM tasks
         WHERE status = 'completed'
           AND tasks.archived_at IS NULL
           AND completed_at >= ?1
           AND completed_at < ?2
    """
  static let completedItemsSQL = """
    SELECT id, title, status, defer_count
         FROM tasks
         WHERE status = 'completed'
           AND tasks.archived_at IS NULL
           AND completed_at >= ?1
           AND completed_at < ?2
         ORDER BY \(TaskRepo.taskOrderBy)
         LIMIT ?3
    """
  static let createdCountSQL = """
    SELECT COUNT(*) FROM tasks
         WHERE tasks.archived_at IS NULL
           AND created_at >= ?1
           AND created_at < ?2
    """
  /// Still-open tasks whose `due_date` equals the day — "what didn't get
  /// done". `due_date` is a bare `YYYY-MM-DD` string, compared directly.
  static let dueOpenCountSQL = """
    SELECT COUNT(*) FROM tasks
         WHERE status IN (\(StatusName.actionableStatusSqlList))
           AND tasks.archived_at IS NULL
           AND due_date = ?1
    """
  /// Active habits and the subset whose logged completion `value` met the
  /// target on the day. Identical shape to ``Overview/loadHabitSummary``.
  static let habitSummarySQL = """
    SELECT
      (SELECT COUNT(*) FROM habits WHERE archived = 0),
      (SELECT COUNT(DISTINCT h.id) FROM habits h
       INNER JOIN habit_completions hc ON h.id = hc.habit_id AND hc.completed_date = ?1
       WHERE h.archived = 0 AND hc.value >= h.target_count)
    """
  /// Provider mirrors remain a stored-span count. Canonical events use the
  /// timeline engine below so recurring occurrences and three-state occurrence
  /// decisions have exactly the same visibility as the calendar surface.
  static let providerEventCountSQL = """
    SELECT COUNT(*) FROM provider_calendar_events
      WHERE start_date <= ?1 AND COALESCE(end_date, start_date) >= ?1
    """

  // MARK: - Validation

  static func validateLimit(_ name: String, _ value: UInt32) throws {
    if value == 0 || value > limitCap {
      throw StoreError.validation("\(name) must be between 1 and \(limitCap)")
    }
  }

  // MARK: - Entry point

  /// Day-summary read model for the local calendar day `date` (`YYYY-MM-DD`),
  /// interpreted in the user's configured timezone. `completedLimit` caps
  /// ``DaySummary/topCompleted`` and must be in `1...limitCap`.
  public static func loadDaySummary(
    _ db: Database, date: String, completedLimit: UInt32
  ) throws -> DaySummary {
    try validateLimit("completed_limit", completedLimit)

    let window = try WorkflowTimezone.dayWindowUtcBoundsForConn(
      db, endingOn: date, spanDays: 1)
    let day = window.toDay

    let completedCount =
      try Int64.fetchOne(db, sql: completedCountSQL, arguments: [window.startUtc, window.endUtc])
      ?? 0
    let topCompleted = try Row.fetchAll(
      db, sql: completedItemsSQL,
      arguments: [window.startUtc, window.endUtc, completedLimit]
    ).map { row in
      TaskItem(id: row[0], title: row[1], status: row[2], deferCount: row[3])
    }
    let createdCount =
      try Int64.fetchOne(db, sql: createdCountSQL, arguments: [window.startUtc, window.endUtc]) ?? 0
    let dueOpenCount = try Int64.fetchOne(db, sql: dueOpenCountSQL, arguments: [day]) ?? 0

    let habitRow = try Row.fetchOne(db, sql: habitSummarySQL, arguments: [day])
    let habitsTotal = (habitRow?[0] as Int64?) ?? 0
    let habitsCompleted = (habitRow?[1] as Int64?) ?? 0

    let anchorTimezone = try WorkflowTimezone.anchoredTimezoneName(db)
    let canonicalEventCount = try CalendarTimelineQueries.getCalendarTimeline(
      db, from: day, to: day, accessMode: .off, anchorTimezone: anchorTimezone
    ).count
    let providerEventCount =
      try Int.fetchOne(db, sql: providerEventCountSQL, arguments: [day]) ?? 0
    let eventCount = Int64(canonicalEventCount) + Int64(providerEventCount)

    return DaySummary(
      date: day, completedCount: completedCount, topCompleted: topCompleted,
      createdCount: createdCount, dueOpenCount: dueOpenCount,
      habitsCompleted: habitsCompleted, habitsTotal: habitsTotal, eventCount: eventCount)
  }
}
