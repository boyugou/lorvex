import Foundation
import GRDB
import LorvexDomain

extension TaskRepo {
  /// Batched edge mutations on `task_dependencies`.
  ///
  /// Sync outbox enqueue (one event per edge) remains the caller's
  /// responsibility — these helpers are pure SQL.
  public enum Dependencies {

    /// Hard upper bound on a single `dependsOnIds` batch (256): SQLite's
    /// default `SQLITE_MAX_VARIABLE_NUMBER` is 999, the preflight
    /// `IN(?, ?, …)` consumes one slot per endpoint plus one for `task_id`,
    /// and the multi-row INSERT adds three fixed binds (`task_id`, `version`,
    /// `now`).
    public static let maxDependsOnBatch: Int = 256

    /// Insert multiple dependency edges in one multi-row
    /// `INSERT OR IGNORE` statement.
    ///
    /// Preflights both endpoints (`taskId` and every `dependsOnIds`
    /// entry) for `status <> 'cancelled'` and `archived_at IS NULL` so a UI
    /// race that cancels or archives an endpoint between two writes cannot
    /// recreate an edge lifecycle cleanup must detach. Completed endpoints are
    /// deliberately allowed: dependency edges are retained as task history
    /// after completion. The preflight + INSERT pair runs
    /// inside `BEGIN IMMEDIATE` when the connection is currently in
    /// auto-commit; nested callers that already hold a transaction
    /// rely on their outer boundary's atomicity.
    ///
    /// Returns the number of rows newly inserted (duplicates collapse
    /// silently via `OR IGNORE`).
    ///
    /// Validation errors (`StoreError.validation`):
    /// - batch exceeds ``maxDependsOnBatch``
    /// - any `(taskId, depId)` is a self-reference
    /// - any endpoint is missing, archived, or cancelled
    @discardableResult
    public static func insertDependencyEdgesBatch(
      _ writer: any DatabaseWriter,
      taskId: TaskId,
      dependsOnIds: [TaskId],
      version: String,
      now: String
    ) throws -> Int {
      if dependsOnIds.isEmpty { return 0 }

      if dependsOnIds.count > maxDependsOnBatch {
        throw StoreError.validation(
          "task_dependency batch contains \(dependsOnIds.count) edges, which exceeds the "
            + "\(maxDependsOnBatch)-edge per-call cap (split into multiple calls)")
      }

      return try StoreTransactions.withImmediateTransaction(writer) { db in
        try insertDependencyEdgesBatchInner(
          db, taskId: taskId, dependsOnIds: dependsOnIds,
          version: version, now: now)
      }
    }

    /// Inner shape used when an outer transaction already exists. Use
    /// ``insertDependencyEdgesBatch(_:taskId:dependsOnIds:version:now:)``
    /// when working from a fresh writer; reach for this when composing
    /// inside an already-open `BEGIN IMMEDIATE`.
    @discardableResult
    public static func insertDependencyEdgesBatchInner(
      _ db: Database,
      taskId: TaskId,
      dependsOnIds: [TaskId],
      version: String,
      now: String
    ) throws -> Int {
      if dependsOnIds.isEmpty { return 0 }

      for depId in dependsOnIds where depId == taskId {
        throw StoreError.validation(
          "task_dependency self-reference rejected: task `\(taskId.rawValue)` "
            + "cannot depend on itself")
      }

      // Gather every endpoint, dedupe, then verify the count of non-cancelled,
      // non-archived rows matches. Completion preserves dependency history;
      // cancellation is the lifecycle state that detaches it.
      var endpointSet = Set<String>()
      var endpoints: [String] = []
      endpoints.reserveCapacity(1 + dependsOnIds.count)
      if endpointSet.insert(taskId.rawValue).inserted {
        endpoints.append(taskId.rawValue)
      }
      for d in dependsOnIds where endpointSet.insert(d.rawValue).inserted {
        endpoints.append(d.rawValue)
      }
      endpoints.sort()

      let placeholders = Sql.sqlInPlaceholders(endpoints.count, 0)
      let preflightSql =
        "SELECT COUNT(*) FROM tasks WHERE id IN (\(placeholders)) "
        + "AND status <> '\(StatusName.cancelled)' AND archived_at IS NULL"
      let live =
        try Int64.fetchOne(
          db, sql: preflightSql, arguments: StatementArguments(endpoints)) ?? 0
      if live != Int64(endpoints.count) {
        throw StoreError.validation(
          "task_dependency endpoint missing, archived, or cancelled")
      }

      var sql =
        "INSERT OR IGNORE INTO task_dependencies (task_id, depends_on_task_id, version, created_at) VALUES "
      // Positional binds: ?1 = task_id, ?2 = version, ?3 = now,
      // ?4… = each depends_on id.
      var args: [(any DatabaseValueConvertible)?] = [
        taskId.rawValue, version, now,
      ]
      for (i, depId) in dependsOnIds.enumerated() {
        if i > 0 { sql.append(", ") }
        let paramIdx = 4 + i
        sql.append("(?1, ?\(paramIdx), ?2, ?3)")
        args.append(depId.rawValue)
      }
      try db.execute(sql: sql, arguments: StatementArguments(args))
      return db.changesCount
    }

  }
}
