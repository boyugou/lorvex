import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexWorkflow

extension SwiftLorvexCoreService {
  /// Builds the `TodaySnapshot` from the overview's top-by-priority tasks,
  /// enriching each so tags / checklist / reminders / lateness match the stable
  /// MCP/UI shape.
  public func loadToday() async throws -> TodaySnapshot {
    // The snapshot's database identity and local sequence must come from the
    // exact SQLite transaction that reads its rows. This identity-bound
    // maintenance transaction seeds the per-database id on a fresh install and
    // closes the managed-storage reset race without advertising a data change.
    try withWatchCommandMaintenanceWrite { db in
      try Self.loadTodaySnapshot(db)
    }
  }

  public func loadTask(id: LorvexTask.ID) async throws -> LorvexTask {
    try read { db in
      try Self.loadTaskMapped(db, id: id)
    }
  }

  /// See ``LorvexTaskServicing/loadWidgetStatsSource()``. Unions the uncapped,
  /// priority-ordered actionable pool with every started task — so a started
  /// task hidden by defer-until or ranked below the dashboard cap is still
  /// present — and reads the exact current-day completion window. Neither side
  /// is a top-N slice, so glance-surface counts stay exact above 500 rows.
  public func loadWidgetStatsSource() async throws -> WidgetStatsSource {
    try read { db in
      try Self.loadWidgetStatsSource(db)
    }
  }

  public func deferHistory(taskID: LorvexTask.ID, limit: Int) async throws
    -> [TaskDeferHistoryEntry]
  {
    guard limit > 0 else { return [] }
    return try read { db in
      try AiChangelogDeferHistory.deferHistory(db, taskId: taskID, limit: limit).map { row in
        TaskDeferHistoryEntry(
          deferredAt: row.deferredAt,
          structuredReason: row.structuredReason,
          note: row.note,
          initiatedBy: row.initiatedBy)
      }
    }
  }

  /// Load + enrich a task by id, mapping to `LorvexTask`. Throws
  /// `LorvexCoreError.taskNotFound` when the row is absent.
  static func loadTaskMapped(_ db: Database, id: String) throws -> LorvexTask {
    guard try TaskRepo.Read.getTask(db, taskId: TaskId(trusted: id)) != nil else {
      throw LorvexCoreError.taskNotFound
    }
    let enriched = try TaskResponse.loadEnrichedTaskJSON(db, taskId: TaskId(trusted: id))
    return try SwiftLorvexTaskDeserializers.task(enriched)
  }

  /// Build a `TodaySnapshot` from a mid-transaction `Database` — the synchronous
  /// core of `loadToday`, reused by the lifecycle/batch funnels so the rich
  /// return reflects the just-committed state without a second connection.
  static func loadTodaySnapshot(
    _ db: Database, logicalDay: String? = nil
  ) throws -> TodaySnapshot {
    let workspaceInstanceID = try SyncCheckpoints.getOrCreateDatabaseInstanceId(db)
    let resolvedLogicalDay = try logicalDay ?? WorkflowTimezone.todayYmdForConn(db)
    let timezone = try WorkflowTimezone.anchoredTimezoneName(db)
    let overview = try Overview.loadOverviewSnapshot(
      db, limits: Overview.Limits.app(), logicalDay: resolvedLogicalDay)
    let tasks = try Self.enrich(db, rows: overview.topByPriority)
    // The "In Progress" section reads its own uncapped query, not the
    // priority-capped `tasks` pool, so a started task ranked below the overview
    // cap still surfaces.
    let inProgressTasks = try Self.enrich(db, rows: TaskRepo.Read.getInProgressTasks(db))
    let openCount = Int(overview.stats.openCount)
    let summary: String
    switch openCount {
    case 0: summary = "All clear."
    case 1: summary = "1 open task."
    default: summary = "\(openCount) open tasks."
    }
    return TodaySnapshot(
      focusTitle: "Today",
      summary: summary,
      tasks: tasks,
      inProgressTasks: inProgressTasks,
      workspaceInstanceID: workspaceInstanceID,
      logicalDay: resolvedLogicalDay,
      timezone: timezone,
      localChangeSequence: Int(try LocalChangeSeq.read(db)))
  }
}
