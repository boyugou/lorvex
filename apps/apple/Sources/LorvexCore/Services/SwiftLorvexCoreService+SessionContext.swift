import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

extension SwiftLorvexCoreService {
  // MARK: - Overview / session context

  /// See ``LorvexSystemServicing/loadOverviewTaskList()``. Reads the overview's
  /// top-by-priority slice, not the day pool: `get_overview` orients an assistant
  /// across the whole workspace, so undated and future-dated work belongs in the
  /// answer and a cap is appropriate.
  public func loadOverviewTaskList() async throws -> OverviewTaskListSnapshot {
    try read { db in
      let logicalDay = try WorkflowTimezone.todayYmdForConn(db)
      let overview = try Overview.loadOverviewSnapshot(
        db, limits: Overview.Limits.mcpFull(), logicalDay: logicalDay)
      return OverviewTaskListSnapshot(
        logicalDay: logicalDay,
        localChangeSequence: Int(try LocalChangeSeq.read(db)),
        tasks: try Self.enrich(db, rows: overview.topByPriority),
        todayTasks: try Self.enrich(
          db, rows: TaskRepo.Read.getTodayPoolTasks(db, today: logicalDay)),
        briefing: overview.briefing)
    }
  }

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
        hasBriefing: snapshot.briefing != nil
      )
    }
  }

  public func getSessionContext() async throws -> SessionContextSnapshot {
    let now = wallClock()
    return try read { db in
      let preferences = try Self.readPreferences(db)
      let deviceID = try SyncCheckpoints.get(db, key: SyncCheckpoints.keyDeviceId)
      let timezone = try WorkflowTimezone.anchoredTimezoneName(db)
      return SessionContextSnapshot(
        date: try WorkflowTimezone.todayYmdForConn(db, now: now),
        weekday: Self.localWeekdayName(now: now, timezoneName: timezone),
        localTime: Self.localTimeOfDay(now: now, timezoneName: timezone).asString,
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

  /// The wall-clock time of `now` in `timezoneName`, to the minute. An
  /// unparseable zone name falls back to the system zone, matching how the
  /// workflow layer resolves today's date.
  static func localTimeOfDay(now: Date, timezoneName: String) -> TimeOfDay {
    let calendar = Self.gregorianCalendar(timezoneName: timezoneName)
    return TimeOfDay.fromMinutesSaturating(
      calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now))
  }

  /// The English weekday name (`Monday` … `Sunday`) of `now` in
  /// `timezoneName`, independent of the device language, because assistants
  /// read it as data.
  static func localWeekdayName(now: Date, timezoneName: String) -> String {
    var calendar = Self.gregorianCalendar(timezoneName: timezoneName)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar.weekdaySymbols[calendar.component(.weekday, from: now) - 1]
  }

  private static func gregorianCalendar(timezoneName: String) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = Timezone.parseTimezoneName(timezoneName) ?? TimeZone.current
    return calendar
  }
}
