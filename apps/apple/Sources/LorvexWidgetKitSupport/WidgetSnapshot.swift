import Foundation
import LorvexCore

/// The App-Group snapshot the host app writes for widgets/complications to read.
///
/// Codable is synthesized and strict for the v4 fields: every field
/// except the nullable `timezone`, `logicalDay`, and `briefing` must be present,
/// so a snapshot must carry `version` and all
/// data arrays (empty arrays, never omitted). `WidgetSnapshotLoader` owns compat:
/// it gates on `version == supportedVersion` and turns any decode failure into a
/// graceful fallback, so a stale or foreign-shaped file degrades to a placeholder
/// rather than a partial decode.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
  public static let supportedVersion = 4
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
  /// Producers set it; when it is absent, freshness derives the source day
  /// from `generatedAt` and `timezone`.
  public let logicalDay: String?
  public let stats: Stats
  /// The assistant's briefing for ``logicalDay``. Nil when the day has none,
  /// when titles are hidden, and while a system Focus filter narrows the list,
  /// since the briefing speaks about the whole day.
  public let briefing: String?
  /// Today's list in Today's order: started tasks first, then by priority and
  /// due date. Narrowed to the system Focus filter's lists while one is active.
  /// Every glance reads its lead task and its rows from here.
  public let tasks: [TodayTask]
  /// Today's habit statuses (empty when none).
  public let habits: [HabitSummary]
  /// Lists available for configurable widget filters (empty when none).
  public let lists: [ListSummary]
  /// Per-list stats for configurable widgets (empty when none).
  public let listStats: [ListStats]
  /// The list this snapshot was narrowed to by ``scoped(toList:)``, so a
  /// widget configured with a list can name it; nil for the whole day, and
  /// when the configured list is no longer in ``lists``. Not encoded: a
  /// widget narrows the shared snapshot as it reads it.
  public private(set) var scopeList: ListSummary? = nil

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
    case tasks
    case habits
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
    tasks: [TodayTask],
    habits: [HabitSummary] = [],
    lists: [ListSummary] = [],
    listStats: [ListStats] = [],
    scopeList: ListSummary? = nil
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
    self.tasks = tasks
    self.habits = habits
    self.lists = lists
    self.listStats = listStats
    self.scopeList = scopeList
  }

  /// The `version` of an encoded snapshot, read without decoding the rest. A
  /// snapshot of another version has another shape, so a reader checks this
  /// first and reports a version mismatch rather than a damaged file.
  public static func encodedVersion(of data: Data) throws -> Int {
    try JSONDecoder().decode(VersionProbe.self, from: data).version
  }

  private struct VersionProbe: Decodable {
    let version: Int
  }
}
