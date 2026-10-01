import Foundation
import GRDB
import LorvexDomain

extension TaskRepo {
  /// Read-side queries against the `tasks` table.
  ///
  /// Every query returns rows projected through ``TaskRepo/taskColumns``
  /// and mapped through ``TaskRepo/rowToTaskRow(_:)``. Active-row callers
  /// must layer `archived_at IS NULL` explicitly — single-row lookups
  /// (``getTask(_:taskId:)``) intentionally include Trash rows for the
  /// restore / permanent-delete flows.
  public enum Read {

    // -------------------------------------------------------------------
    // Single-row + existence
    // -------------------------------------------------------------------

    /// Look up one task by id, regardless of Trash state.
    ///
    /// Returns `nil` when no row matches. The unfiltered shape exists
    /// because two camps of caller need it:
    ///
    /// - Restore / permanent-delete flows that must operate on trashed
    ///   rows.
    /// - Post-INSERT / post-DUPLICATE materialization paths that just
    ///   wrote the row and so know `archived_at IS NULL` by
    ///   construction.
    ///
    /// Callers needing "active task" semantics must filter
    /// `archived_at IS NULL` themselves, or reach for a dedicated
    /// active-only read path.
    public static func getTask(_ db: Database, taskId: TaskId) throws -> TaskRow? {
      let row = try Row.fetchOne(
        db,
        sql: "SELECT \(TaskRepo.taskColumns) FROM tasks WHERE id = ?",
        arguments: [taskId.rawValue])
      guard let row else { return nil }
      return try TaskRepo.rowToTaskRow(row)
    }

    /// Batch row fetch by id in one `WHERE id IN (…)` round trip, returned
    /// keyed by id. Ids are deduplicated; the result omits ids with no matching
    /// row, so a caller that needs input order or a missing-id diagnostic
    /// reconstructs both from the returned map. Like ``getTask``, this does NOT
    /// filter Trash — `archived_at IS NULL` filtering is the caller's job.
    public static func getTasksByIds(_ db: Database, ids: [String]) throws -> [String: TaskRow] {
      if ids.isEmpty { return [:] }
      var seen = Set<String>()
      var deduped: [String] = []
      deduped.reserveCapacity(ids.count)
      for id in ids where seen.insert(id).inserted {
        deduped.append(id)
      }
      let placeholders = Sql.sqlInPlaceholders(deduped.count, 0)
      let rows = try Row.fetchAll(
        db,
        sql: "SELECT \(TaskRepo.taskColumns) FROM tasks WHERE id IN (\(placeholders))",
        arguments: StatementArguments(deduped))
      var out: [String: TaskRow] = [:]
      out.reserveCapacity(rows.count)
      for row in rows {
        let id: String = row["id"]
        out[id] = try TaskRepo.rowToTaskRow(row)
      }
      return out
    }

    /// Returns `true` when a row exists in `tasks` for the given id and is
    /// NOT in Trash. The canonical implementation of the
    /// `WHERE id = ? AND archived_at IS NULL` existence check every IPC /
    /// MCP boundary uses to render a "Task not found" diagnostic when a
    /// referenced id either does not exist or has been moved to Trash.
    public static func taskExistsActive(_ db: Database, taskId: TaskId) throws -> Bool {
      let count =
        try Int64.fetchOne(
          db,
          sql: "SELECT 1 FROM tasks WHERE id = ? AND archived_at IS NULL",
          arguments: [taskId.rawValue]) ?? 0
      return count != 0
    }

    // -------------------------------------------------------------------
    // Overview reads
    // -------------------------------------------------------------------

    /// Actionable tasks (`open` or `in_progress`) in canonical overview
    /// priority order.
    ///
    /// Filters `status IN ('open', 'in_progress') AND archived_at IS NULL`, excludes tasks hidden
    /// by `available_from` (defer-until) via
    /// ``TaskReadBuckets/availableVisibilityPredicate(taskAlias:datePlaceholder:)``
    /// with overdue-wins, and orders by ``TaskRepo/taskOrderBy`` —
    /// `priority_effective ASC, due_date ASC NULLS LAST, id ASC`. `today` is the
    /// canonical `YYYY-MM-DD` reference for the hide-until check; `limit` caps
    /// the returned slice.
    public static func getOpenTasksByPriority(
      _ db: Database, today: String, limit: Int64
    ) throws -> [TaskRow] {
      let visible = TaskReadBuckets.availableVisibilityPredicate(
        taskAlias: "tasks", datePlaceholder: ":today")
      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT \(TaskRepo.taskColumns) FROM tasks \
          WHERE status IN (\(StatusName.actionableStatusSqlList)) AND tasks.archived_at IS NULL \
          AND \(visible) \
          ORDER BY \(TaskRepo.taskOrderBy) \
          LIMIT :limit
          """,
        arguments: ["today": today, "limit": limit])
      return try rows.map(TaskRepo.rowToTaskRow)
    }

    /// The day surface's actionable pool: every task today holds, uncapped and
    /// in Today's order — started tasks first, then the rest, each group in
    /// canonical ``TaskRepo/taskOrderBy`` order. Membership is
    /// `overdue ∪ (today_pool ∧ visible) ∪ in_progress`.
    ///
    /// The first two arms reuse the canonical bucket predicates, so the list can
    /// never disagree with ``Overview/Stats/attentionCount``, which is derived
    /// from the same buckets. Overdue is folded in rather than split out — a
    /// missed day still belongs to today — and, like the OVERDUE bucket, skips the
    /// visibility conjunct so a defer-until cannot suppress a blown deadline.
    ///
    /// The `in_progress` arm is date-independent on purpose: a task stays started
    /// across days, so started work never falls off the day just because no date
    /// points at it. Started tasks lead because they are what the user is in the
    /// middle of; every surface that shows the day reads this one order.
    ///
    /// Deliberately date-bounded and uncapped, unlike
    /// ``getOpenTasksByPriority(_:today:limit:)``: that read answers "what is most
    /// important overall" for a summary, and capping a summary is fine. A day
    /// surface answers "what does today hold", where an undated backlog item is
    /// wrong and a hidden commitment is worse than a long list.
    public static func getTodayPoolTasks(
      _ db: Database, today: String
    ) throws -> [TaskRow] {
      let overdue = TaskReadBuckets.overdueBucketPredicate(
        taskAlias: "tasks", datePlaceholder: ":today")
      let todayPool = TaskReadBuckets.todayPoolBucketPredicate(
        taskAlias: "tasks", datePlaceholder: ":today")
      let visible = TaskReadBuckets.availableVisibilityPredicate(
        taskAlias: "tasks", datePlaceholder: ":today")
      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT \(TaskRepo.taskColumns) FROM tasks \
          WHERE status IN (\(StatusName.actionableStatusSqlList)) AND tasks.archived_at IS NULL \
          AND (\(overdue) \
               OR (\(todayPool) AND \(visible)) \
               OR tasks.status = '\(StatusName.inProgress)') \
          ORDER BY tasks.status = '\(StatusName.inProgress)' DESC, \(TaskRepo.taskOrderBy)
          """,
        arguments: ["today": today])
      return try rows.map(TaskRepo.rowToTaskRow)
    }

    /// Count of actionable, non-archived tasks across the whole workspace.
    ///
    /// The single number behind a day surface's headline ("N open tasks"), read on
    /// its own so a caller that wants only the count does not pay for the full
    /// overview aggregate — lists, top-by-priority, recently-completed, and the
    /// streak walk — to reach one field of it.
    public static func countActionableTasks(_ db: Database) throws -> Int64 {
      let row = try Row.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM tasks "
          + "WHERE status IN (\(StatusName.actionableStatusSqlList)) "
          + "AND archived_at IS NULL")
      return row?[0] ?? 0
    }

    /// Ids, among `taskIDs`, that cannot be started because at least one task
    /// they depend on is still active. Empty input returns empty.
    ///
    /// Day surfaces show a blocked task rather than hiding it — it was planned
    /// for today, so silently dropping it reads as data loss — but they must be
    /// able to mark it, since it is the one row in the list that cannot be
    /// picked up.
    public static func blockedTaskIDs(
      _ db: Database, among taskIDs: [String]
    ) throws -> Set<String> {
      guard !taskIDs.isEmpty else { return [] }
      let placeholders = databaseQuestionMarks(count: taskIDs.count)
      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT DISTINCT td.task_id AS task_id FROM task_dependencies td \
          JOIN tasks AS blocker ON blocker.id = td.depends_on_task_id \
          WHERE td.task_id IN (\(placeholders)) \
          AND blocker.status IN (\(StatusName.activeStatusSqlList)) \
          AND blocker.archived_at IS NULL
          """,
        arguments: StatementArguments(taskIDs))
      return Set(rows.compactMap { $0["task_id"] as String? })
    }

    /// Every started (`in_progress`) task, uncapped, in canonical
    /// ``TaskRepo/taskOrderBy`` order.
    ///
    /// Filters `status = 'in_progress' AND archived_at IS NULL`. Deliberately
    /// unbounded and free of the day-pool / defer-until visibility gates that
    /// cap ``getOpenTasksByPriority``: an explicitly started task is active work
    /// that must surface in Today's "In Progress" section in full, never sliced
    /// to a priority-capped overview snapshot. A started task carrying a future
    /// `available_from` still shows — starting overrides hide-until.
    public static func getInProgressTasks(_ db: Database) throws -> [TaskRow] {
      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT \(TaskRepo.taskColumns) FROM tasks \
          WHERE status = ? AND tasks.archived_at IS NULL \
          ORDER BY \(TaskRepo.taskOrderBy)
          """,
        arguments: [StatusName.inProgress])
      return try rows.map(TaskRepo.rowToTaskRow)
    }

    /// Every task that contributes to glance-surface workload statistics.
    ///
    /// Open tasks follow the ordinary day-surface visibility rule (including
    /// overdue-wins), while an explicitly started task remains visible even if
    /// it carries a future `available_from`. Unlike the dashboard query this is
    /// deliberately uncapped: callers use it for exact aggregate counts, never
    /// as a rendered top-N list.
    public static func getWidgetActionableTasks(
      _ db: Database, today: String
    ) throws -> [TaskRow] {
      let visible = TaskReadBuckets.availableVisibilityPredicate(
        taskAlias: "tasks", datePlaceholder: ":today")
      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT \(TaskRepo.taskColumns) FROM tasks \
          WHERE status IN (\(StatusName.actionableStatusSqlList)) \
          AND tasks.archived_at IS NULL \
          AND (status = :started OR \(visible)) \
          ORDER BY \(TaskRepo.taskOrderBy)
          """,
        arguments: ["today": today, "started": StatusName.inProgress])
      return try rows.map(TaskRepo.rowToTaskRow)
    }

    /// Recently completed tasks in deterministic overview order.
    ///
    /// Filters `status = 'completed' AND archived_at IS NULL` and orders
    /// by `completed_at DESC, id ASC`. `limit` caps the returned slice.
    public static func getRecentlyCompletedTasks(_ db: Database, limit: Int64) throws -> [TaskRow]
    {
      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT \(TaskRepo.taskColumns) FROM tasks \
          WHERE status = ? AND tasks.archived_at IS NULL \
          ORDER BY completed_at DESC, id ASC \
          LIMIT ?
          """,
        arguments: [StatusName.completed, limit])
      return try rows.map(TaskRepo.rowToTaskRow)
    }

    /// Completed tasks whose completion instant falls in the half-open UTC
    /// window `[startUtc, endUtc)`, uncapped and deterministically ordered.
    ///
    /// This is the exact-count counterpart to `getRecentlyCompletedTasks`: a
    /// top-N recent slice cannot answer "completed today" once a busy day
    /// exceeds that slice.
    public static func getCompletedTasks(
      _ db: Database, startUtc: String, endUtc: String
    ) throws -> [TaskRow] {
      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT \(TaskRepo.taskColumns) FROM tasks \
          WHERE status = ? AND tasks.archived_at IS NULL \
          AND completed_at >= ? AND completed_at < ? \
          ORDER BY completed_at DESC, id ASC
          """,
        arguments: [StatusName.completed, startUtc, endUtc])
      return try rows.map(TaskRepo.rowToTaskRow)
    }

    // -------------------------------------------------------------------
    // Tag-scoped read
    // -------------------------------------------------------------------

    /// Tasks scoped to a single tag, identified either directly by
    /// `tagId` or by ``Tag/normalizeLookupKey(_:)``-equivalent
    /// `tagLookupKey`. `tagId` wins when both are supplied; supplying
    /// neither returns `[]`.
    ///
    /// Lookup-key resolution selects the deterministic
    /// `ORDER BY id ASC LIMIT 1` winner to match the
    /// `merge_duplicate_tags` rule — `tags.lookup_key` has no UNIQUE
    /// index because the sync merger needs to hold two rows
    /// mid-convergence; the min-id-wins tiebreaker keeps pre-merge
    /// reads in agreement with the eventually-converged state.
    ///
    /// Results follow the canonical ``TaskRepo/taskOrderBy`` sort.
    /// `archived_at IS NULL` filtering is applied (Trash rows never
    /// surface through this path).
    public static func getTasksByTag(
      _ db: Database,
      tagId: TagId? = nil,
      tagLookupKey: String? = nil,
      limit: Int64,
      offset: Int64
    ) throws -> [TaskRow] {
      let resolvedTagId: String
      if let tagId {
        resolvedTagId = tagId.rawValue
      } else if let tagLookupKey {
        let maybeId =
          try String.fetchOne(
            db,
            sql: "SELECT id FROM tags WHERE lookup_key = ? ORDER BY id ASC LIMIT 1",
            arguments: [tagLookupKey])
        guard let id = maybeId else { return [] }
        resolvedTagId = id
      } else {
        return []
      }

      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT \(TaskRepo.taskColumnsQualified("t")) FROM tasks t \
          JOIN task_tags tt ON t.id = tt.task_id \
          WHERE tt.tag_id = ? AND t.archived_at IS NULL \
          ORDER BY \(TaskRepo.taskOrderByQualified("t")) \
          LIMIT ? OFFSET ?
          """,
        arguments: [resolvedTagId, limit, offset])
      return try rows.map(TaskRepo.rowToTaskRow)
    }

    public static func countTasksByTag(
      _ db: Database,
      tagId: TagId? = nil,
      tagLookupKey: String? = nil
    ) throws -> Int {
      let resolvedTagId: String
      if let tagId {
        resolvedTagId = tagId.rawValue
      } else if let tagLookupKey {
        let maybeId =
          try String.fetchOne(
            db,
            sql: "SELECT id FROM tags WHERE lookup_key = ? ORDER BY id ASC LIMIT 1",
            arguments: [tagLookupKey])
        guard let id = maybeId else { return 0 }
        resolvedTagId = id
      } else {
        return 0
      }

      return try Int.fetchOne(
        db,
        sql: """
          SELECT COUNT(*) FROM tasks t \
          JOIN task_tags tt ON t.id = tt.task_id \
          WHERE tt.tag_id = ? AND t.archived_at IS NULL
          """,
        arguments: [resolvedTagId]) ?? 0
    }

  }
}
