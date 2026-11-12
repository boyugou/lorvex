import Foundation
import LorvexCore

public struct WidgetSnapshotProjector: Sendable {
  public var calendar: Calendar
  public var now: @Sendable () -> Date

  public init(
    calendar: Calendar = .autoupdatingCurrent,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.calendar = calendar
    self.now = now
  }

  /// Projects the App-Group widget snapshot.
  ///
  /// The task list is ``TodaySnapshot/tasks``, Today's list in Today's order,
  /// each task carrying its time today (``LorvexTask/time(on:)``) and whether
  /// it waits on an unfinished task (``TodaySnapshot/blockedTaskIDs``), and
  /// narrowed to the system Focus filter's lists while one is active. The
  /// numeric stats (overdue / due-today / completed-today, top-level and
  /// per-list) come from `statsSource` when supplied: its uncapped actionable
  /// (open + in_progress) set and recently-completed set, so the counts reflect
  /// the whole workload rather than just the day and completed-today is a real
  /// count instead of a structural zero. When `statsSource` is nil the stats
  /// fall back to the day's list, which under-counts undated and future work
  /// and cannot see completed tasks — callers with core access should pass a
  /// `statsSource`.
  public func snapshot(
    storageGeneration: Int = 0,
    focusFilterRevision: Int = 0,
    logicalDay: String? = nil,
    today: TodaySnapshot,
    timezone: String?,
    hideTitles: Bool = false,
    focusFilter: FocusFilterConfiguration = .inactive,
    habitCatalog: HabitCatalogSnapshot? = nil,
    listCatalog: ListCatalogSnapshot? = nil,
    statsSource: WidgetStatsSource? = nil,
    events: [CalendarTimelineEvent] = []
  ) -> WidgetSnapshot {
    // The day's list as every glance shows it: Today's order, narrowed to the
    // Focus filter's lists while one is active.
    let dayTasks = today.tasks.filter { $0.status.isActionable }
    let listedTasks = Self.focusScoped(dayTasks, focusFilter: focusFilter)

    // Stats pool: the uncapped canonical actionable set (open + started) when a
    // `statsSource` is supplied, else the day's list. Overdue / due-today and
    // per-list counts are computed against all actionable tasks, not the
    // Focus-narrowed subset, so they reflect the full workload.
    let statsBase =
      statsSource?.actionableTasks.filter { $0.status.isActionable }
      ?? dayTasks.map(WidgetStatsTask.init)
    // Completed-today is counted off the canonical recently-completed set (the
    // day's list is actionable-only, so it never contains a completed task).
    let completedBase = statsSource?.completedTodayTasks ?? today.tasks
    let productCalendar = Self.calendar(timezoneName: timezone, fallback: calendar)

    let nowDate = now()
    let todayYmd = logicalDay ?? Self.localDateOnlyString(from: nowDate, calendar: productCalendar)
    let privateTitle = String(
      localized: "widget.task.private", defaultValue: "Private task",
      table: "Localizable", bundle: WidgetSupportL10n.bundle)
    let tasks = listedTasks.map { task in
      let time = task.time(on: todayYmd)
      return WidgetSnapshot.TodayTask(
        id: task.id,
        title: hideTitles ? privateTitle : task.title,
        status: task.status.rawValue,
        dueDate: task.dueDate.map(Self.dateOnlyString),
        priority: task.priority.tier,
        listID: task.listID,
        estimatedMinutes: task.estimatedMinutes,
        scheduledStart: time.map { lorvexStoredClockTime(minutes: $0.lowerBound) },
        scheduledEnd: time.map { lorvexStoredClockTime(minutes: $0.upperBound) },
        isBlocked: today.blockedTaskIDs.contains(task.id),
        delegation: LorvexTaskDelegationMarker(task: task)
      )
    }

    // `task.dueDate` is a UTC-midnight Date — the stored `due_date`
    // `YYYY-MM-DD` is parsed in UTC — so its canonical wall-calendar day must
    // be read back in UTC, exactly as the surfaced `dueDate` string is.
    // "Today" is the user's perceived local day, read via `calendar`.
    // Comparing the two as `YYYY-MM-DD` strings keeps the due-today/overdue
    // counts consistent with the displayed date and correct across time zones —
    // a plain `calendar.isDate(_:inSameDayAs:)` against the local calendar
    // would shift a UTC-anchored due date by a day for any user not on UTC.
    let dueTodayPredicate: (WidgetStatsTask) -> Bool = { task in
      guard let dueDate = task.dueDate else { return false }
      return Self.dateOnlyString(from: dueDate) == todayYmd
    }
    let overduePredicate: (WidgetStatsTask) -> Bool = { task in
      guard let dueDate = task.dueDate else { return false }
      return Self.dateOnlyString(from: dueDate) < todayYmd
    }
    // "Completed today" keys off the actual completion instant (`completed_at`),
    // read back as the user's local day — NOT the due date. Keying off `dueDate`
    // counted tasks merely *due* today (even if finished days ago) and missed
    // tasks completed today that are due on another day (or have no due date).
    let completedTodayPredicate: (LorvexTask) -> Bool = { task in
      guard task.status == .completed, let completedAt = task.completedAt,
        let completedDate = LorvexDateFormatters.iso8601Fractional.date(from: completedAt)
          ?? LorvexDateFormatters.iso8601.date(from: completedAt)
      else { return false }
      return Self.localDateOnlyString(from: completedDate, calendar: productCalendar) == todayYmd
    }
    let dueTodayCount = statsBase.filter(dueTodayPredicate).count
    let overdueCount = statsBase.filter(overduePredicate).count
    // The production stats source already queried completed rows inside the
    // product-timezone UTC bounds for `logicalDay`. Count that bounded set
    // directly; re-projecting each completion through a device calendar can
    // incorrectly discard valid rows after travel. The predicate remains only
    // for preview/test fallbacks that do not supply the canonical source.
    let completedTodayCount = statsSource == nil
      ? completedBase.filter(completedTodayPredicate).count
      : completedBase.count

    let habitSummaries: [WidgetSnapshot.HabitSummary] =
      habitCatalog?.habits
        .filter { !$0.archived && $0.isListed(on: todayYmd) }
        .map { habit in
          WidgetSnapshot.HabitSummary(
            id: habit.id,
            name: habit.name,
            icon: habit.icon,
            completedToday: habit.completionsToday,
            target: habit.targetCount,
            color: habit.color,
            isSkipped: habit.isSkipped
          )
        } ?? []

    let listStats: [WidgetSnapshot.ListStats] = listCatalog?.lists.map { list in
      let openInList = statsBase.filter { $0.listID == list.id }
      return WidgetSnapshot.ListStats(
        id: list.id,
        stats: .init(
          todayCount: listedTasks.filter { $0.listID == list.id }.count,
          overdueCount: openInList.filter(overduePredicate).count,
          dueTodayCount: openInList.filter(dueTodayPredicate).count,
          completedTodayCount: completedBase.filter {
            $0.listID == list.id && (statsSource != nil || completedTodayPredicate($0))
          }.count
        ))
    } ?? []

    return WidgetSnapshot(
      generatedAt: Self.timestampString(from: nowDate),
      storageGeneration: storageGeneration,
      focusFilterRevision: focusFilterRevision,
      workspaceInstanceID: today.workspaceInstanceID
        ?? WidgetSnapshot.unscopedWorkspaceInstanceID,
      localChangeSequence: today.localChangeSequence,
      timezone: timezone,
      logicalDay: todayYmd,
      stats: .init(
        todayCount: listedTasks.count,
        overdueCount: overdueCount,
        dueTodayCount: dueTodayCount,
        completedTodayCount: completedTodayCount
      ),
      // The briefing speaks about the whole day, so a Focus-narrowed list, like
      // hidden titles, goes without it.
      briefing: hideTitles || focusFilter.isActive ? nil : today.briefing,
      tasks: tasks,
      habits: habitSummaries,
      lists: listCatalog?.lists.map {
        WidgetSnapshot.ListSummary(id: $0.id, name: $0.name, icon: $0.icon)
      } ?? [],
      listStats: listStats,
      events: Self.todayEvents(events, on: todayYmd, hideTitles: hideTitles)
    )
  }

  /// The most events a snapshot carries: more than any widget draws, so the
  /// ones that end first can age out while later ones take their place.
  static let maximumEvents = 12

  /// `events` that occur on `day` as the widget draws them, in the order of
  /// the day's agenda: each event's share of the day's clock, and "Busy" for
  /// its title while titles are hidden. A Focus filter keeps them: it narrows
  /// the day's lists, and an event belongs to none.
  static func todayEvents(
    _ events: [CalendarTimelineEvent], on day: String, hideTitles: Bool
  ) -> [WidgetSnapshot.TodayEvent] {
    let busy = String(
      localized: "today.schedule.busy", defaultValue: "Busy",
      table: "Localizable", bundle: WidgetSupportL10n.bundle)
    return events.filter { $0.occurs(on: day) }.sortedForAgenda(on: day)
      .prefix(maximumEvents)
      .map { event in
        let span = event.clockSpan(on: day)
        return WidgetSnapshot.TodayEvent(
          id: event.id,
          title: hideTitles ? busy : event.title,
          // A color is a `#RRGGBB` token; anything longer is not one.
          color: event.color.flatMap { $0.utf8.count <= 16 ? $0 : nil },
          startMinutes: span?.start,
          endMinutes: span?.end,
          isCarriedOver: span != nil && event.dayPart(on: day) == .lastDay)
      }
  }

  private static func calendar(timezoneName: String?, fallback: Calendar) -> Calendar {
    guard let timezoneName, let timezone = TimeZone(identifier: timezoneName) else {
      return fallback
    }
    var resolved = Calendar(identifier: .gregorian)
    resolved.locale = Locale(identifier: "en_US_POSIX")
    resolved.timeZone = timezone
    return resolved
  }

}
