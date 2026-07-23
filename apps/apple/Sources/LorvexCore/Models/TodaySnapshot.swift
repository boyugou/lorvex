public struct TodaySnapshot: Equatable, Sendable {
  public var focusTitle: String
  public var summary: String
  public var tasks: [LorvexTask]
  /// Every started (`in_progress`) task, uncapped and in canonical order — the
  /// source for Today's "In Progress" section on macOS and iPhone. Kept separate
  /// from ``tasks`` (the priority-capped top-N overview pool) so a started task
  /// ranked below the cap still appears; the section reads all started work, not
  /// a slice of the overview.
  public var inProgressTasks: [LorvexTask]
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
    focusTitle: "Today",
    summary: "No active plan yet.",
    tasks: [],
    workspaceInstanceID: nil,
    logicalDay: nil,
    timezone: nil,
    localChangeSequence: 0
  )

  public init(
    focusTitle: String,
    summary: String,
    tasks: [LorvexTask],
    inProgressTasks: [LorvexTask] = [],
    workspaceInstanceID: String? = nil,
    logicalDay: String? = nil,
    timezone: String? = nil,
    localChangeSequence: Int
  ) {
    self.focusTitle = focusTitle
    self.summary = summary
    self.tasks = tasks
    self.inProgressTasks = inProgressTasks
    self.workspaceInstanceID = workspaceInstanceID
    self.logicalDay = logicalDay
    self.timezone = timezone
    self.localChangeSequence = localChangeSequence
  }
}
