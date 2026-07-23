import LorvexCore

/// Section discriminator for the macOS Tasks workspace. Sections mostly map to
/// a task status, but two lanes are not statuses: `deferred` (deferral pushes
/// `planned_date` and leaves the task `open`) is the defer_count-based
/// `get_deferred_tasks` lane, and `scheduled` is the defer-until lane of open
/// tasks currently hidden by a future `available_from` (fed by
/// `getHiddenScheduledTasks`). Keeping this enum distinct from
/// `LorvexTask.Status` lets the workspace carry both derived lanes without
/// re-introducing statuses for them.
enum TaskWorkspaceSection: Sendable, Equatable, CaseIterable {
  case open
  case deferred
  case scheduled
  case completed
  case cancelled
  case someday

  /// The `LorvexTask.Status` whose tasks fill this section, or `nil` for the
  /// date-derived `deferred` / `scheduled` lanes (fed by `get_deferred_tasks` /
  /// `getHiddenScheduledTasks`, not a status query).
  var taskStatus: LorvexTask.Status? {
    switch self {
    case .open: .open
    case .deferred: nil
    case .scheduled: nil
    case .completed: .completed
    case .cancelled: .cancelled
    case .someday: .someday
    }
  }

  /// Status string for `list_tasks` / `search_tasks`. The Open lane queries the
  /// `actionable` working set so a started (in_progress) task shows there
  /// instead of vanishing. The deferred / scheduled lanes read across open
  /// tasks, then narrow via their dedicated reads.
  var coreStatusRawValue: String {
    switch self {
    case .open:
      return LorvexTask.Status.actionableFilter
    case .deferred, .scheduled, .completed, .cancelled, .someday:
      return LorvexTask.Status.coreQueryString(for: taskStatus)
    }
  }
}

struct AppStoreTaskWorkspaceStorage {
  var openTasks: [LorvexTask] = []
  var deferredTasks: [LorvexTask] = []
  var scheduledTasks: [LorvexTask] = []
  var completedTasks: [LorvexTask] = []
  var cancelledTasks: [LorvexTask] = []
  var somedayTasks: [LorvexTask] = []
  var visibleOrderedTaskIDs: [LorvexTask.ID]?
  var selectedTaskIDs = Set<LorvexTask.ID>()
  var listScopeID: LorvexList.ID?
  var hasLoaded = false
  var openNextOffset: Int?
  var deferredNextOffset: Int?
  var scheduledNextOffset: Int?
  var completedNextOffset: Int?
  var cancelledNextOffset: Int?
  var somedayNextOffset: Int?
  var loadingMoreStatus: TaskWorkspaceSection?
  var isLoading = false
  /// Monotonic stamp bumped whenever a full load replaces the bucket arrays. An
  /// in-flight page append captures it and discards itself if a reload happened
  /// meanwhile, so a pre-mutation page can't be appended onto post-mutation
  /// arrays (which would duplicate rows and SwiftUI identities).
  var loadGeneration = 0
  /// Monotonic stamp bumped at the START of every full load. Each load captures
  /// it and, before replacing the buckets, discards itself if a newer load has
  /// since begun — so a slower earlier read (e.g. a background republish /
  /// CloudSync-triggered reload landing late under heavy load) cannot overwrite
  /// a newer load's snapshot with pre-mutation rows. The later-started load
  /// always observes equal-or-fresher committed state, so last-started-wins can
  /// never drop a real update.
  var loadRequestGeneration = 0
  /// The in-flight full reload, if any. `loadTaskWorkspace` single-flights through
  /// this: a reload requested while one runs coalesces into a trailing re-run (see
  /// `reloadPending`) rather than racing it. Two genuinely concurrent reloads —
  /// a mutation's awaited reload against a background republish/CloudSync reload —
  /// otherwise let a later-*started* load whose reads predate the write win the
  /// last-started-wins guard and revert the buckets to a pre-mutation snapshot.
  var reloadTask: Task<Void, any Error>?
  /// Set when a reload is requested while `reloadTask` is in flight; the running
  /// task drains it with one more read+apply, so the latest requester observes the
  /// freshest committed state instead of an already-superseded snapshot.
  var reloadPending = false
}
