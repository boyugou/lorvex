import Foundation

public protocol LorvexDataExportServicing: LorvexCalendarServicing,
  LorvexHabitServicing, LorvexListTagServicing, LorvexMemoryServicing,
  LorvexReviewServicing, LorvexSystemServicing, LorvexTaskServicing
{
  /// Serializes the requested data categories to JSON or CSV.
  ///
  /// `entities` is a list of canonical category names — the raw values of
  /// `LorvexDataExportCategory` (`"tasks"`, `"lists"`, `"tags"`, `"habits"`,
  /// `"calendar_events"`, `"daily_reviews"`, `"daily_briefings"`,
  /// `"task_calendar_event_links"`, `"memory"`, `"preferences"`). An empty
  /// array or
  /// `["all"]` includes every category. `format` is `"json"` or `"csv"`
  /// (default: `"json"`).
  ///
  /// Reads are full-table, not view-scoped: each category is drawn from its
  /// `load*ForDataExport` requirement below or an equivalent complete-catalog
  /// read, so tasks include Trash rows and calendar events span the store's full
  /// history. Review history is drawn with a large explicit limit, since that
  /// read requires a bound.
  /// Returns the rendered string (JSON or multi-section CSV).
  func exportData(entities: [String], format: String) async throws -> String

  /// Serializes data for an AI-facing caller: the portable migration document,
  /// without the exact Apple task graph a user's JSON backup carries, since an
  /// assistant reads and re-creates records rather than restoring rows.
  func exportDataForAI(
    entities: [String], format: String, appVersion: String?, generatedAt: String?
  ) async throws -> String

  /// Captures every selected export category as one logical store snapshot.
  /// Storage-backed conformers implement this requirement with a single database
  /// read transaction; the protocol default rejects export so a new backend
  /// cannot accidentally assemble a backup from unrelated point reads.
  /// `includeNativeTaskGraph` keeps the exact Apple task graph out of AI/CSV
  /// migration documents.
  func loadSnapshotForDataExport(
    entities: [String], includeNativeTaskGraph: Bool
  ) async throws -> LorvexDataExportSnapshot

  // MARK: - Full-table export reads
  //
  // These complete-catalog projections remain useful to individual callers and
  // tests, but they are NOT composed by the export default: separate calls do
  // not share a snapshot. A storage conformer implements
  // `loadSnapshotForDataExport` and reuses the equivalent database-level helpers
  // inside one transaction.

  /// Every task, including archived/Trash rows, for a full data export —
  /// unlike `listTasks`, which is view-scoped and excludes archived tasks.
  func loadTasksForDataExport() async throws -> [ExportTask]

  /// The portable task projection plus the exact Apple-native task graph,
  /// captured and validated under one SQLite read transaction. Human JSON/ZIP
  /// backups use this bundle; AI and CSV migration exports use the portable
  /// projection above and never expose/freeze the native row contract.
  func loadTaskExportBundleForDataExport() async throws -> TaskDataExportBundle

  /// Every tag for a full data export.
  func loadTagsForDataExport() async throws -> [ExportTag]

  /// Every calendar event across the store's full history for a full data
  /// export — unlike `loadCalendarTimeline`, which is bounded to a requested
  /// window.
  func loadCalendarEventsForDataExport() async throws -> [ExportCalendarEvent]

  /// Every canonical calendar event plus its durable recurring-lineage
  /// boundaries, captured from one SQLite read snapshot. Export assembly uses
  /// this bundle instead of independent reads that could straddle a split.
  func loadCalendarBundleForDataExport() async throws -> ExportCalendarBundle

  /// Every day's briefing, in date order, for a full data export.
  func loadDailyBriefingsForDataExport() async throws -> [ExportDailyBriefing]

  /// Every task-to-calendar-event link for a full data export.
  func loadTaskCalendarEventLinksForDataExport() async throws -> [ExportTaskCalendarEventLink]

  /// Every memory entry (id + latest content + timestamp) for a full data
  /// export.
  func loadMemoryForDataExport() async throws -> [ExportMemoryEntry]
}
