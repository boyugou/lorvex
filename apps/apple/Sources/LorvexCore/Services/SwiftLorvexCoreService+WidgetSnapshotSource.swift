import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexWorkflow

extension SwiftLorvexCoreService: LorvexWidgetSnapshotSourceServicing {
  /// Captures every database-backed widget input under one immediate
  /// transaction and one managed-storage shared cutover lease. The transaction
  /// seeds/reads workspace identity, so the returned generation, workspace,
  /// sequence, rows, counts, and focus ordering all describe the same physical
  /// store revision.
  public func loadWidgetSnapshotSource(date: String?) async throws -> WidgetSnapshotSource {
    try withWatchCommandMaintenanceWrite { db in
      // Capture the logical day only after entering the SQLite transaction.
      // Production passes nil so the persisted product timezone, not the host
      // device timezone, owns the boundary and no caller-to-await midnight race
      // can mix two days.
      let logicalDay = try date ?? WorkflowTimezone.todayYmdForConn(db)
      let timezone = try WorkflowTimezone.anchoredTimezoneName(db)
      let today = try Self.loadTodaySnapshot(db, logicalDay: logicalDay)
      Self.afterWidgetTodayReadForTesting?()

      let currentFocus: CurrentFocusPlan?
      if let header = try Self.currentFocusHeader(db, date: logicalDay) {
        let storedIDs = try CurrentFocusItemsRepo.queryFocusTaskIds(db, date: logicalDay)
        let taskIDs = try Self.filterExistingNonArchivedTaskIDs(db, ids: storedIDs)
        currentFocus = SwiftLorvexFocusDeserializers.currentFocusPlan(
          date: logicalDay,
          taskIDs: taskIDs,
          briefing: header.briefing,
          timezone: header.timezone,
          localChangeSequence: Int(try LocalChangeSeq.read(db)))
      } else {
        currentFocus = nil
      }

      let habits = try Self.loadHabitsSnapshot(db, date: logicalDay)
      let listRows = try ListRepo.getAllListsWithCounts(db)
      let lists = ListCatalogSnapshot(
        lists: listRows.map(SwiftLorvexListDeserializers.list))
      let stats = try Self.loadWidgetStatsSource(db, date: logicalDay)
      let managedPath = self.openedManagedDatabasePathSnapshot()
      let storageGeneration = managedPath
        .flatMap { ManagedStorageGeneration.read(forDatabase: $0) } ?? 0

      return WidgetSnapshotSource(
        storageGeneration: storageGeneration,
        logicalDay: logicalDay,
        timezone: timezone,
        today: today,
        currentFocus: currentFocus,
        habits: habits,
        lists: lists,
        stats: stats)
    }
  }

  static func loadWidgetStatsSource(
    _ db: Database, date: String? = nil
  ) throws -> WidgetStatsSource {
    let logicalDay = try date ?? WorkflowTimezone.todayYmdForConn(db)
    let completionWindow = try WorkflowTimezone.dayWindowUtcBoundsForConn(
      db, endingOn: logicalDay, spanDays: 1)
    let actionable = try Self.enrich(
      db, rows: TaskRepo.Read.getWidgetActionableTasks(db, today: logicalDay))
    let completed = try Self.enrich(
      db,
      rows: TaskRepo.Read.getCompletedTasks(
        db, startUtc: completionWindow.startUtc, endUtc: completionWindow.endUtc))
    return WidgetStatsSource(
      actionableTasks: actionable,
      completedTodayTasks: completed)
  }
}
