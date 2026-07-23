import Foundation
import GRDB
import LorvexDomain

/// Canonical task-count + estimate-coverage projections shared by every
/// weekly-review surface (UI, CLI, MCP brief, MCP snapshot) so the counts
/// never drift across read paths.
///
/// Pure SQL over the `tasks` table; takes a `Database` and uses positional
/// binds.
public enum ReviewMetrics {

  /// Open + non-archived tasks whose `due_date` lex-order precedes
  /// `todayYmd` (canonical `YYYY-MM-DD`).
  ///
  /// `todayYmd` MUST be in the user's local timezone YMD; passing a
  /// UTC YMD on a tz-shifted device produces off-by-one results at
  /// the day boundary.
  public static func overdueOpenCount(_ db: Database, todayYmd: String) throws -> Int64 {
    let row = try Row.fetchOne(
      db,
      sql: "SELECT COUNT(*) FROM tasks "
        + "WHERE status IN (\(StatusName.actionableStatusSqlList)) "
        + "AND archived_at IS NULL "
        + "AND due_date IS NOT NULL "
        + "AND due_date < ?1",
      arguments: [todayYmd])
    return row?[0] ?? 0
  }

  /// Open + non-archived tasks deferred at least `minCount` times. The
  /// threshold is exposed as a parameter so future tuning of the
  /// "frequently deferred" callout does not fork the SQL.
  public static func deferredOpenCount(_ db: Database, minCount: Int64) throws -> Int64 {
    let row = try Row.fetchOne(
      db,
      sql: "SELECT COUNT(*) FROM tasks "
        + "WHERE status IN (\(StatusName.actionableStatusSqlList)) "
        + "AND archived_at IS NULL "
        + "AND defer_count >= ?1",
      arguments: [minCount])
    return row?[0] ?? 0
  }

  /// Non-archived tasks parked in the `someday` bucket. Used by the
  /// weekly-review surfaces as part of the orientation block.
  public static func somedayCount(_ db: Database) throws -> Int64 {
    let row = try Row.fetchOne(
      db,
      sql: "SELECT COUNT(*) FROM tasks WHERE status = ?1 AND archived_at IS NULL",
      arguments: [TaskStatus.someday.rawValue])
    return row?[0] ?? 0
  }

  /// Estimate-coverage summary for completed tasks inside
  /// `[windowStartUtc, windowEndUtc)`. Timestamps are canonical RFC3339
  /// millisecond-Z (lex order = chronological).
  public struct TaskEstimateSummary: Equatable, Sendable {
    public var completedTotal: Int64
    public var completedWithEstimateCount: Int64
    public var estimateCoverageRatio: Double?

    public init(
      completedTotal: Int64,
      completedWithEstimateCount: Int64,
      estimateCoverageRatio: Double?
    ) {
      self.completedTotal = completedTotal
      self.completedWithEstimateCount = completedWithEstimateCount
      self.estimateCoverageRatio = estimateCoverageRatio
    }
  }

  public static func loadTaskEstimateSummary(
    _ db: Database,
    windowStartUtc: String,
    windowEndUtc: String
  ) throws -> TaskEstimateSummary {
    let sql = """
      SELECT
        COUNT(*) AS completed_total,
        COALESCE(SUM(CASE
          WHEN estimated_minutes IS NOT NULL AND estimated_minutes > 0 THEN 1
          ELSE 0
        END), 0) AS completed_with_estimate_count
      FROM tasks
      WHERE status = 'completed'
        AND archived_at IS NULL
        AND completed_at IS NOT NULL
        AND completed_at >= ?1
        AND completed_at < ?2
      """
    guard let row = try Row.fetchOne(db, sql: sql, arguments: [windowStartUtc, windowEndUtc]) else {
      return TaskEstimateSummary(
        completedTotal: 0,
        completedWithEstimateCount: 0,
        estimateCoverageRatio: nil)
    }
    let completedTotal: Int64 = row[0]
    let completedWithEstimateCount: Int64 = row[1]
    let estimateCoverageRatio: Double? =
      completedTotal > 0
      ? Double(completedWithEstimateCount) / Double(completedTotal)
      : nil
    return TaskEstimateSummary(
      completedTotal: completedTotal,
      completedWithEstimateCount: completedWithEstimateCount,
      estimateCoverageRatio: estimateCoverageRatio)
  }
}
