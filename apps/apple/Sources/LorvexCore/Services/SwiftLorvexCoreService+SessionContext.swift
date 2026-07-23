import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

extension SwiftLorvexCoreService {
  // MARK: - Overview / session context

  public func getOverviewCompact() async throws -> OverviewCompactSnapshot {
    try read { db in
      let snapshot = try Overview.loadOverviewSnapshot(
        db, limits: Overview.Limits.mcpCompact())
      let stats = OverviewCompactSnapshot.Stats(
        openCount: Int(snapshot.stats.openCount),
        overdueCount: Int(snapshot.stats.overdueCount),
        todayPoolCount: Int(snapshot.stats.todayPoolCount),
        attentionCount: Int(snapshot.stats.attentionCount),
        upcomingWeekCount: Int(snapshot.stats.upcomingWeekCount)
      )
      let topTasks = snapshot.topByPriority.map { row in
        OverviewCompactSnapshot.TopTask(
          id: row.core.id,
          title: row.core.title,
          status: row.core.status,
          listID: row.core.listId,
          priority: row.core.priority.map(Int.init),
          dueDate: row.scheduling.dueDate?.asString
        )
      }
      return OverviewCompactSnapshot(
        date: snapshot.date,
        stats: stats,
        topTasks: topTasks,
        currentFocusTaskCount: snapshot.currentFocus?.taskCount ?? 0
      )
    }
  }

  public func getSessionContext() async throws -> SessionContextSnapshot {
    try read { db in
      let preferences = try Self.readPreferences(db)
      let deviceID = try SyncCheckpoints.get(db, key: SyncCheckpoints.keyDeviceId)
      let date = try WorkflowTimezone.todayYmdForConn(db)
      let timezone = try WorkflowTimezone.anchoredTimezoneName(db)
      return SessionContextSnapshot(
        date: date,
        deviceID: deviceID,
        // Fixed `"unknown"` placeholder: this DB-only call (which also runs in
        // the separate MCP-host process) can't observe the live Cloud Sync
        // transport, so it reports `"unknown"` rather than asserting a mode. The
        // app layer, which knows the mode, derives the user-facing label.
        syncBackend: "unknown",
        timezone: timezone,
        workingHours: preferences["working_hours"]
      )
    }
  }
}
