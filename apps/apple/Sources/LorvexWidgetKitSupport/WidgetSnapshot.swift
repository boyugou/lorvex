import Foundation
import LorvexCore

/// The App-Group snapshot the host app writes for widgets/complications to read.
///
/// Codable is synthesized and strict for the v3 fields: every field
/// except the nullable `timezone`, `logicalDay`, and `briefing` must be present,
/// so a snapshot must carry `version` and all
/// data arrays (empty arrays, never omitted). `WidgetSnapshotLoader` owns compat:
/// it gates on `version == supportedVersion` and turns any decode failure into a
/// graceful fallback, so a stale or foreign-shaped file degrades to a placeholder
/// rather than a partial decode.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
  public static let supportedVersion = 3
  public static let unscopedWorkspaceInstanceID = "00000000-0000-0000-0000-000000000000"

  public let version: Int
  public let generatedAt: String
  /// Durable physical-store generation of the managed store. Compared before
  /// workspace identity or local sequence so a delayed pre-reset or
  /// pre-quarantine writer cannot restore superseded content into the sidecar.
  public let storageGeneration: Int
  /// Monotonic revision of the local system Focus-filter configuration used to
  /// project this snapshot. It orders equal database revisions across app and
  /// App Intents extension processes.
  public let focusFilterRevision: Int
  /// Physical database whose state was projected. Within one storage
  /// generation, it scopes `localChangeSequence`; wall clock is
  /// display/freshness metadata and never decides which state is newer.
  public let workspaceInstanceID: String
  public let localChangeSequence: Int
  public let timezone: String?
  /// Calendar day for which Today/habit/progress fields were materialized.
  /// New producers always set this; it remains optional so an in-place app
  /// update can safely expire a previously written v2 snapshot by deriving the
  /// source day from `generatedAt` and `timezone`.
  public let logicalDay: String?
  public let stats: Stats
  public let briefing: String?
  public let focusTasks: [FocusTask]
  /// Today's habit statuses (empty when none).
  public let habits: [HabitSummary]
  /// Open tasks due today or overdue (empty when none).
  public let todayTasks: [TodayTask]
  /// Lists available for configurable widget filters (empty when none).
  public let lists: [ListSummary]
  /// Per-list stats for configurable widgets (empty when none).
  public let listStats: [ListStats]

  enum CodingKeys: String, CodingKey {
    case version
    case generatedAt = "generated_at"
    case storageGeneration = "storage_generation"
    case focusFilterRevision = "focus_filter_revision"
    case workspaceInstanceID = "workspace_instance_id"
    case localChangeSequence = "local_change_sequence"
    case timezone
    case logicalDay = "logical_day"
    case stats
    case briefing
    case focusTasks = "focus_tasks"
    case habits
    case todayTasks = "today_tasks"
    case lists
    case listStats = "list_stats"
  }

  public init(
    version: Int = WidgetSnapshot.supportedVersion,
    generatedAt: String,
    storageGeneration: Int = 0,
    focusFilterRevision: Int = 0,
    workspaceInstanceID: String = WidgetSnapshot.unscopedWorkspaceInstanceID,
    localChangeSequence: Int = 0,
    timezone: String?,
    logicalDay: String? = nil,
    stats: Stats,
    briefing: String?,
    focusTasks: [FocusTask],
    habits: [HabitSummary] = [],
    todayTasks: [TodayTask] = [],
    lists: [ListSummary] = [],
    listStats: [ListStats] = []
  ) {
    self.version = version
    self.generatedAt = generatedAt
    self.storageGeneration = max(0, storageGeneration)
    self.focusFilterRevision = max(0, focusFilterRevision)
    self.workspaceInstanceID = workspaceInstanceID
    self.localChangeSequence = localChangeSequence
    self.timezone = timezone
    self.logicalDay = logicalDay
    self.stats = stats
    self.briefing = briefing
    self.focusTasks = focusTasks
    self.habits = habits
    self.todayTasks = todayTasks
    self.lists = lists
    self.listStats = listStats
  }
}
