import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

extension SwiftLorvexCoreService {
  // MARK: - Overview / session context

  /// See ``LorvexSystemServicing/loadOverviewTaskList()``. ``OverviewTaskListSnapshot/tasks``
  /// is the top of the workspace's priority order with the day's rows taken
  /// out: `get_overview` orients an assistant across the whole workspace, so
  /// undated and future-dated work belongs in the answer and a cap is
  /// appropriate.
  public func loadOverviewTaskList() async throws -> OverviewTaskListSnapshot {
    try read { db in
      let logicalDay = try WorkflowTimezone.todayYmdForConn(db)
      let today = try TaskRepo.Read.getTodayPoolTasks(db, today: logicalDay)
      let onToday = Set(today.map(\.core.id))
      // Every row of the day may precede the others in priority order, so
      // reading that many more rows leaves the full count of others whenever
      // the workspace holds them.
      let others = try TaskRepo.Read.getOpenTasksByPriority(
        db, today: logicalDay, limit: Int64(Self.overviewOtherTaskLimit + today.count)
      ).filter { !onToday.contains($0.core.id) }.prefix(Self.overviewOtherTaskLimit)
      return OverviewTaskListSnapshot(
        logicalDay: logicalDay,
        localChangeSequence: Int(try LocalChangeSeq.read(db)),
        tasks: try Self.enrich(db, rows: Array(others)),
        todayTasks: try Self.enrich(db, rows: today),
        briefing: try Overview.loadBriefing(db, date: logicalDay))
    }
  }

  /// How many tasks outside the day's list the overview task list carries.
  static let overviewOtherTaskLimit = 10

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
      let timezone = try WorkflowTimezone.anchoredTimezoneName(db)
      return SessionContextSnapshot(
        date: try WorkflowTimezone.todayYmdForConn(db, now: now),
        weekday: Self.localWeekdayName(now: now, timezoneName: timezone),
        localTime: Self.localTimeOfDay(now: now, timezoneName: timezone).asString,
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
