import Foundation
import LorvexCore

public struct WidgetSnapshotProjector: Sendable {
  public var maxFocusTasks: Int
  public var calendar: Calendar
  public var now: @Sendable () -> Date

  public init(
    maxFocusTasks: Int = 6,
    calendar: Calendar = .autoupdatingCurrent,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.maxFocusTasks = max(1, maxFocusTasks)
    self.calendar = calendar
    self.now = now
  }

  /// Projects the App-Group widget snapshot.
  ///
  /// The rendered focus/today task lists come from ``TodaySnapshot/tasks`` — the
  /// priority-capped top-N dashboard pool, which is the correct set to show. The
  /// numeric stats (focus / overdue / due-today / completed-today, top-level and
  /// per-list) come from `statsSource` when supplied: its uncapped actionable
  /// (open + in_progress) set and recently-completed set, so the counts reflect
  /// the whole workload rather than the ≤N slice and completed-today is a real
  /// count instead of a structural zero. When `statsSource` is nil the stats fall
  /// back to the dashboard pool (the pre-canonical behavior), which under-counts
  /// past the cap and cannot see completed tasks — callers with core access
  /// should pass a `statsSource`.
  public func snapshot(
    storageGeneration: Int = 0,
    focusFilterRevision: Int = 0,
    logicalDay: String? = nil,
    today: TodaySnapshot,
    currentFocus: CurrentFocusPlan?,
    timezone: String?,
    hideTitles: Bool = false,
    focusFilter: FocusFilterConfiguration = .inactive,
    habitCatalog: HabitCatalogSnapshot? = nil,
    listCatalog: ListCatalogSnapshot? = nil,
    statsSource: WidgetStatsSource? = nil
  ) -> WidgetSnapshot {
    let expandBeyondFocus = focusFilter.isActive && focusFilter.showNonFocusTasks

    // Rendered pool: the priority-capped dashboard list drives the focus/today
    // task lists the widget actually shows.
    let renderActionable = today.tasks.filter { $0.status.isActionable }
    let renderFiltered = focusFilteredTasks(
      from: renderActionable, currentFocus: currentFocus, focusFilter: focusFilter)
    let orderedTasks = focusOrderedTasks(
      from: renderFiltered, currentFocus: currentFocus, expandBeyondFocus: expandBeyondFocus)

    // Stats pool: the uncapped canonical actionable set (open + started) when a
    // `statsSource` is supplied, else the dashboard pool. Overdue/due-today and
    // per-list open counts are computed against `statsBase` — all actionable
    // tasks, not just the focus-filtered subset — so they reflect the full
    // workload even when the filter is active; the focus count uses the
    // focus-filtered/ordered `statsOrdered`.
    let statsBase = statsSource?.actionableTasks.filter { $0.status.isActionable } ?? renderActionable
    let statsFiltered = focusFilteredTasks(
      from: statsBase, currentFocus: currentFocus, focusFilter: focusFilter)
    let statsOrdered = focusOrderedTasks(
      from: statsFiltered, currentFocus: currentFocus, expandBeyondFocus: expandBeyondFocus)
    // Completed-today is counted off the canonical recently-completed set (the
    // dashboard pool is actionable-only, so it never contains a completed task).
    let completedBase = statsSource?.completedTodayTasks ?? today.tasks
    let productCalendar = Self.calendar(
      timezoneName: timezone ?? currentFocus?.timezone,
      fallback: calendar)

    let nowDate = now()
    let focusTasks = orderedTasks.prefix(maxFocusTasks).map { task in
      WidgetSnapshot.FocusTask(
        id: task.id,
        title: hideTitles
          ? String(
            localized: "widget.task.private", defaultValue: "Private task",
            table: "Localizable", bundle: WidgetSupportL10n.bundle)
          : task.title,
        status: task.status.rawValue,
        dueDate: task.dueDate.map(Self.dateOnlyString),
        priority: task.priority.tier,
        listID: task.listID,
        estimatedMinutes: task.estimatedMinutes
      )
    }

    // `task.dueDate` is a UTC-midnight Date — the `planned_date` `YYYY-MM-DD` is
    // parsed in UTC (see `SwiftLorvexTaskDeserializers.plannedDate`), so its
    // canonical wall-calendar day must be read back in UTC, exactly as the
    // surfaced `dueDate` string is. "Today" is the user's perceived local day,
    // read via `calendar`. Comparing the two as `YYYY-MM-DD` strings keeps the
    // due-today/overdue counts consistent with the displayed date and correct
    // across time zones — a plain `calendar.isDate(_:inSameDayAs:)` against the
    // local calendar would shift a UTC-anchored due date by a day for any user
    // not on UTC.
    let todayYmd = logicalDay ?? Self.localDateOnlyString(from: nowDate, calendar: productCalendar)
    let dueTodayPredicate: (LorvexTask) -> Bool = { task in
      guard let dueDate = task.dueDate else { return false }
      return Self.dateOnlyString(from: dueDate) == todayYmd
    }
    let overduePredicate: (LorvexTask) -> Bool = { task in
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
        .filter { !$0.archived }
        .map { habit in
          WidgetSnapshot.HabitSummary(
            id: habit.id,
            name: habit.name,
            icon: habit.icon,
            completedToday: habit.completionsToday,
            target: habit.targetCount
          )
        } ?? []

    let todayTaskList: [WidgetSnapshot.TodayTask] = orderedTasks
      .map { task in
        WidgetSnapshot.TodayTask(
          id: task.id,
        title: hideTitles
          ? String(
            localized: "widget.task.private", defaultValue: "Private task",
            table: "Localizable", bundle: WidgetSupportL10n.bundle)
          : task.title,
        dueDate: task.dueDate.map(Self.dateOnlyString),
        priority: task.priority.tier,
        estimatedMinutes: task.estimatedMinutes,
        listID: task.listID
      )
    }

    let listStats: [WidgetSnapshot.ListStats] = listCatalog?.lists.map { list in
      let openInList = statsBase.filter { $0.listID == list.id }
      let focusInList = statsOrdered.filter { $0.listID == list.id }
      return WidgetSnapshot.ListStats(
        id: list.id,
        stats: .init(
          focusCount: focusInList.count,
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
      timezone: timezone ?? currentFocus?.timezone,
      logicalDay: todayYmd,
      stats: .init(
        focusCount: statsOrdered.count,
        overdueCount: overdueCount,
        dueTodayCount: dueTodayCount,
        completedTodayCount: completedTodayCount
      ),
      briefing: hideTitles ? nil : currentFocus?.briefing,
      focusTasks: Array(focusTasks),
      habits: habitSummaries,
      todayTasks: todayTaskList,
      lists: listCatalog?.lists.map {
        WidgetSnapshot.ListSummary(id: $0.id, name: $0.name, icon: $0.icon)
      } ?? [],
      listStats: listStats
    )
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
