import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// At-a-glance dashboard read model shared by the app and MCP surfaces.
///
/// `loadOverviewSnapshot` composes per-list open counts, top-priority open
/// tasks, recently-completed rows, the current-focus summary,
/// habit activity, and the day-bucket counts (Attention / Overdue /
/// Today / Upcoming). The caller owns the read transaction (this operates on
/// the supplied `db` directly).
public enum Overview {
  /// Drop the in-process completion-streak cache for `db`. Call after inbound
  /// sync apply, which mutates completion state without bumping the
  /// `local_change_seq` the cache keys on (see ``OverviewStreakCache``).
  public static func invalidateStreakCache(_ db: Database) {
    OverviewStreakCache.shared.invalidate(db)
  }

  /// Section caps per surface. `lists == nil` includes every list; the snapshot
  /// still reports `listsTotal` / `listsTruncated`.
  public struct Limits: Sendable, Equatable {
    public let lists: Int?
    public let topTasks: Int
    public let recentlyCompleted: Int

    public init(lists: Int?, topTasks: Int, recentlyCompleted: Int) {
      self.lists = lists
      self.topTasks = topTasks
      self.recentlyCompleted = recentlyCompleted
    }

    /// Full app view: every list, 10 top tasks, 5 recently completed.
    public static func app() -> Limits { Limits(lists: nil, topTasks: 10, recentlyCompleted: 5) }
    /// MCP compact tool response: no lists, 5 top tasks, no recently completed.
    public static func mcpCompact() -> Limits {
      Limits(lists: 0, topTasks: 5, recentlyCompleted: 0)
    }
  }

  /// Hero-strip counts. `completionStreak` / `streakActiveToday` are filled in
  /// after the aggregate from the streak walk.
  public struct Stats: Sendable, Equatable {
    public var openCount: Int64
    public var overdueCount: Int64
    public var todayPoolCount: Int64
    public var attentionCount: Int64
    public var upcomingWeekCount: Int64
    public var completedToday: Int64
    public var completedThisWeek: Int64
    public var completedLastWeek: Int64
    public var somedayCount: Int64
    public var completionStreak: Int64
    public var streakActiveToday: Bool
  }

  public struct OverviewList: Sendable, Equatable {
    public let id: String
    public let name: String
    public let color: String?
    public let icon: String?
    public let description: String?
    public let aiNotes: String?
    public let createdAt: String
    public let updatedAt: String
    public let version: String
    public let openCount: Int64
  }

  public struct CurrentFocusSummary: Sendable, Equatable {
    public let taskCount: Int
    public let briefing: String?
    public let timezone: String?
  }

  public struct HabitSummary: Sendable, Equatable {
    public let count: Int64
    public let completedToday: Int64
  }

  public struct Snapshot: Sendable {
    public let date: String
    public let stats: Stats
    public let lists: [OverviewList]
    public let listsTotal: Int64
    public let listsTruncated: Bool
    public let topByPriority: [TaskRow]
    public let recentlyCompleted: [TaskRow]
    public let currentFocus: CurrentFocusSummary?
    public let habits: HabitSummary
  }

  // MARK: - Stats aggregate

  /// Single-SELECT aggregate producing every count except the streak.
  public static func loadOverviewStatsForBounds(
    _ db: Database, today: String, todayStartUtc: String, todayEndUtc: String,
    reviewWindowStartUtc: String, reviewWindowEndUtc: String, prevWeekStartUtc: String
  ) throws -> Stats {
    guard case .success(let todayDate) = IsoDate.parseIsoDate(today) else {
      throw StoreError.validation("invalid overview day '\(today)'")
    }

    let sql =
      "SELECT "
      + "SUM(CASE WHEN status IN (\(StatusName.actionableStatusSqlList)) THEN 1 ELSE 0 END), "
      + "SUM(CASE WHEN status = '\(StatusName.completed)' AND completed_at >= ?1 AND completed_at < ?2 THEN 1 ELSE 0 END), "
      + "SUM(CASE WHEN status = '\(StatusName.completed)' AND completed_at >= ?3 AND completed_at < ?4 THEN 1 ELSE 0 END), "
      + "SUM(CASE WHEN status = '\(StatusName.completed)' AND completed_at >= ?5 AND completed_at < ?3 THEN 1 ELSE 0 END), "
      + "SUM(CASE WHEN status = '\(StatusName.someday)' THEN 1 ELSE 0 END) "
      + "FROM tasks WHERE archived_at IS NULL"
    let row = try Row.fetchOne(
      db, sql: sql,
      arguments: [
        todayStartUtc, todayEndUtc, reviewWindowStartUtc, reviewWindowEndUtc, prevWeekStartUtc,
      ])
    let openCount = (row?[0] as Int64?) ?? 0
    let completedToday = (row?[1] as Int64?) ?? 0
    let completedThisWeek = (row?[2] as Int64?) ?? 0
    let completedLastWeek = (row?[3] as Int64?) ?? 0
    let somedayCount = (row?[4] as Int64?) ?? 0

    let dayBuckets = try TaskRepo.Read.countOpenTaskDayBuckets(
      db, asOfDate: todayDate, upcomingDays: 7)

    return Stats(
      openCount: openCount,
      overdueCount: dayBuckets.overdue,
      todayPoolCount: dayBuckets.todayPool,
      attentionCount: dayBuckets.overdue + dayBuckets.todayPool,
      upcomingWeekCount: dayBuckets.upcoming,
      completedToday: completedToday,
      completedThisWeek: completedThisWeek,
      completedLastWeek: completedLastWeek,
      somedayCount: somedayCount,
      completionStreak: 0,
      streakActiveToday: false)
  }

  // MARK: - Sections

  static func loadOverviewLists(_ db: Database, limit: Int?) throws -> (
    rows: [OverviewList], total: Int64, truncated: Bool
  ) {
    let page = try ListRepo.getListsWithCountsPage(db, limit: limit)
    let rows = page.rows.map { row in
      OverviewList(
        id: row.list.id, name: row.list.name, color: row.list.color,
        icon: row.list.icon, description: row.list.description, aiNotes: row.list.aiNotes,
        createdAt: row.list.createdAt.asString, updatedAt: row.list.updatedAt.asString,
        version: row.list.version, openCount: row.openCount)
    }
    return (rows, page.totalMatching, page.totalMatching > Int64(rows.count))
  }

  static func loadCurrentFocusSummary(_ db: Database, today: String) throws
    -> CurrentFocusSummary?
  {
    guard
      let row = try Row.fetchOne(
        db, sql: "SELECT briefing, timezone FROM current_focus WHERE date = ?",
        arguments: [today])
    else { return nil }
    let briefing: String? = row[0]
    let timezone: String? = row[1]
    // Count only focus items whose task still exists and is not in the Trash,
    // matching `loadCurrentFocus`'s read filter — a deleted (orphan soft-ref) or
    // archived task must not inflate the focus count.
    let taskCount =
      try Int64.fetchOne(
        db,
        sql: """
          SELECT COUNT(*) FROM current_focus_items cfi
          JOIN tasks t ON t.id = cfi.task_id
          WHERE cfi.date = ? AND t.archived_at IS NULL
          """,
        arguments: [today])
      ?? 0
    return CurrentFocusSummary(taskCount: Int(taskCount), briefing: briefing, timezone: timezone)
  }

  static func loadHabitSummary(_ db: Database, today: String) throws -> HabitSummary {
    let row = try Row.fetchOne(
      db,
      sql: """
        SELECT
          (SELECT COUNT(*) FROM habits WHERE archived = 0),
          (SELECT COUNT(DISTINCT h.id) FROM habits h
           INNER JOIN habit_completions hc ON h.id = hc.habit_id AND hc.completed_date = ?
           WHERE h.archived = 0 AND hc.value >= h.target_count)
        """,
      arguments: [today])
    return HabitSummary(count: (row?[0] as Int64?) ?? 0, completedToday: (row?[1] as Int64?) ?? 0)
  }

  // MARK: - Streak

  struct CompletionStreak: Equatable {
    let count: Int64
    let activeToday: Bool
  }

  /// Walk up to 365 days of completion timestamps, folding each into its local
  /// date, and count the contiguous run ending today (or yesterday).
  /// `loadOverviewSnapshot` memoizes this result per connection via
  /// ``OverviewStreakCache`` (keyed on `local_change_seq` + `today` +
  /// timezone); this function itself is pure and always re-walks the window —
  /// the cache is the caller's concern.
  static func queryCompletionStreak(
    _ db: Database, today: String, timezoneName: String?
  ) throws -> CompletionStreak {
    guard case .success(let todayParsed) = IsoDate.parseIsoDate(today) else {
      throw StoreError.validation("invalid overview day '\(today)'")
    }
    let tz = timezoneName.flatMap { Timezone.parseTimezoneName($0) } ?? TimeZone.current

    var localCal = Foundation.Calendar(identifier: .gregorian)
    localCal.timeZone = tz
    localCal.locale = Locale(identifier: "en_US_POSIX")

    func toLocalDate(_ completedAt: String) -> IsoDate.YMD? {
      guard let parsed = SyncTimestamp.parse(completedAt) else { return nil }
      let date = parsed.date
      let c = localCal.dateComponents([.year, .month, .day], from: date)
      return IsoDate.YMD(year: c.year ?? 0, month: c.month ?? 0, day: c.day ?? 0)
    }

    // earliest_cutoff = (today - 400d) at UTC midnight - 14h, as a sync timestamp.
    let earliestLocalDayNum = IsoDate.dayNumber(todayParsed) - 400
    let earliestMs = Int64(earliestLocalDayNum) * 86_400_000 - 14 * 3_600_000
    let earliestCutoff = SyncTimestampFormat.formatSyncTimestamp(
      Date(timeIntervalSince1970: Double(earliestMs) / 1000.0))

    var completedDays = Set<IsoDate.YMD>()
    let rows = try String.fetchAll(
      db,
      sql: "SELECT completed_at FROM tasks "
        + "WHERE status = 'completed' AND archived_at IS NULL "
        + "AND completed_at IS NOT NULL AND completed_at >= ?",
      arguments: [earliestCutoff])
    for raw in rows {
      if let day = toLocalDate(raw) { completedDays.insert(day) }
    }

    let activeToday = completedDays.contains(todayParsed)
    let startDate: IsoDate.YMD
    if activeToday {
      startDate = todayParsed
    } else {
      let yesterday = IsoDate.ymdFromDayNumber(IsoDate.dayNumber(todayParsed) - 1)
      if completedDays.contains(yesterday) {
        startDate = yesterday
      } else {
        return CompletionStreak(count: 0, activeToday: false)
      }
    }

    var streak: Int64 = 0
    let startNum = IsoDate.dayNumber(startDate)
    for offset in 0..<365 {
      let checkDate = IsoDate.ymdFromDayNumber(startNum - offset)
      if completedDays.contains(checkDate) {
        streak += 1
      } else {
        break
      }
    }
    return CompletionStreak(count: streak, activeToday: activeToday)
  }

  // MARK: - Snapshot composition

  /// Compose the full overview snapshot. `logicalDay`, when supplied, anchors
  /// every day-sensitive row and UTC completion window to one caller-captured
  /// day instead of consulting the wall clock again mid-composition.
  public static func loadOverviewSnapshot(
    _ db: Database, limits: Limits, logicalDay: String? = nil
  ) throws -> Snapshot {
    let today = try logicalDay ?? WorkflowTimezone.todayYmdForConn(db)
    let todayWindow = try WorkflowTimezone.dayWindowUtcBoundsForConn(
      db, endingOn: today, spanDays: 1)
    let reviewWindow = try WorkflowTimezone.dayWindowUtcBoundsForConn(
      db, endingOn: today, spanDays: 7)
    let prevWeekWindow = try WorkflowTimezone.dayWindowUtcBoundsForConn(
      db, endingOn: today, spanDays: 14)
    let timezoneName = try WorkflowTimezone.activeTimezoneName(db)

    var stats = try loadOverviewStatsForBounds(
      db, today: today, todayStartUtc: todayWindow.startUtc, todayEndUtc: todayWindow.endUtc,
      reviewWindowStartUtc: reviewWindow.startUtc, reviewWindowEndUtc: reviewWindow.endUtc,
      prevWeekStartUtc: prevWeekWindow.startUtc)
    let streak = try OverviewStreakCache.shared.value(
      db, today: today, timezone: timezoneName
    ) { db in
      try queryCompletionStreak(db, today: today, timezoneName: timezoneName)
    }
    stats.completionStreak = streak.count
    stats.streakActiveToday = streak.activeToday

    let listsPage = try loadOverviewLists(db, limit: limits.lists)
    let topByPriority = try TaskRepo.Read.getOpenTasksByPriority(
      db, today: today, limit: Int64(limits.topTasks))
    let recentlyCompleted = try TaskRepo.Read.getRecentlyCompletedTasks(
      db, limit: Int64(limits.recentlyCompleted))
    let currentFocus = try loadCurrentFocusSummary(db, today: today)
    let habits = try loadHabitSummary(db, today: today)

    return Snapshot(
      date: today, stats: stats, lists: listsPage.rows, listsTotal: listsPage.total,
      listsTruncated: listsPage.truncated, topByPriority: topByPriority,
      recentlyCompleted: recentlyCompleted, currentFocus: currentFocus, habits: habits)
  }

}
