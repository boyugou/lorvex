public struct TodaySnapshot: Equatable, Sendable {
  public var summary: String
  /// The day's pool — `overdue ∪ today_pool ∪ in_progress`, uncapped and in
  /// Today's order: started tasks first, then canonical order. This is what the
  /// day owns, so an undated backlog item is absent and a future-dated one is
  /// too, unless it was started. Overdue work is folded in rather than split
  /// out, since a missed day still belongs to today.
  ///
  /// Not a general "top tasks" handle: it will not contain a task that has no
  /// claim on today, so it must not be used to witness that a task exists or
  /// changed. Read ``LorvexTaskServicing/loadTask(id:)`` for that, and
  /// ``LorvexSystemServicing/loadOverviewTaskList()`` for a workspace-wide slice.
  public var tasks: [LorvexTask]
  /// The assistant's briefing for ``logicalDay``: its short note on what matters
  /// that day and why. Every surface shows it read-only; nil when the day has
  /// none.
  public var briefing: String?
  /// Every started (`in_progress`) task, uncapped and in canonical order. Started
  /// work is also in ``tasks`` via its own arm of the pool; this stays separate
  /// because `in_progress` is an orthogonal marker, not a scheduling decision — a
  /// task can stay started across several days — so surfaces that want "what is
  /// underway" read it directly instead of re-deriving it.
  public var inProgressTasks: [LorvexTask]
  /// Ids within ``tasks`` that cannot be started because a task they depend on is
  /// still active. Day surfaces keep these visible — they were planned for today,
  /// so dropping them reads as data loss — and mark them, since they are the rows
  /// that cannot be picked up.
  public var blockedTaskIDs: Set<String>
  /// Stable identity of the physical database that produced this snapshot.
  /// Production loads always set it; value-only previews may leave it nil.
  public var workspaceInstanceID: String?
  /// Exact configured-timezone calendar day used by every day-sensitive query
  /// that produced this snapshot. Production loads always set it; previews may
  /// omit it and let their host choose a display-only fallback.
  public var logicalDay: String?
  /// IANA timezone that owns ``logicalDay``. Kept beside the materialized day so
  /// app, widget, Watch, and intent surfaces never recompute the same state in a
  /// different device-local calendar.
  public var timezone: String?
  public var localChangeSequence: Int

  public static let empty = TodaySnapshot(
    summary: "All clear.",
    tasks: [],
    workspaceInstanceID: nil,
    logicalDay: nil,
    timezone: nil,
    localChangeSequence: 0
  )

  public init(
    summary: String,
    tasks: [LorvexTask],
    briefing: String? = nil,
    inProgressTasks: [LorvexTask] = [],
    blockedTaskIDs: Set<String> = [],
    workspaceInstanceID: String? = nil,
    logicalDay: String? = nil,
    timezone: String? = nil,
    localChangeSequence: Int
  ) {
    self.summary = summary
    self.tasks = tasks
    self.briefing = briefing
    self.inProgressTasks = inProgressTasks
    self.blockedTaskIDs = blockedTaskIDs
    self.workspaceInstanceID = workspaceInstanceID
    self.logicalDay = logicalDay
    self.timezone = timezone
    self.localChangeSequence = localChangeSequence
  }
}
