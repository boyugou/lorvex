import Foundation

/// The serialization format for a data export.
public enum LorvexDataExportFormat: String, Sendable {
  case json
  case csv
}

/// One transactionally captured export document plus the producing store's
/// device identity from that same SQLite snapshot. Keeping provenance beside
/// the payload prevents a concurrent storage reset from labeling old data with
/// the replacement store's identity.
public struct LorvexDataExportSnapshot: Sendable {
  public var payload: LorvexDataExportPayload
  public var sourceDeviceID: String?

  public init(payload: LorvexDataExportPayload, sourceDeviceID: String?) {
    self.payload = payload
    self.sourceDeviceID = sourceDeviceID
  }
}

/// Top-level `manifest.json` for a ZIP package export.
///
/// `fileCounts` maps each emitted JSON file's base name (without `.json`) to its
/// record count. `generatedAt` and `appVersion` are stamped by the caller and
/// omitted from the JSON when nil.
public struct ExportManifest: Codable, Sendable {
  /// The backup-container version designated for the first public
  /// compatibility contract. Keep its decoder forever once that build ships.
  public static let firstPublicSchemaVersion = BackupV1Contract.zipSchemaVersion
  public static let currentSchemaVersion = firstPublicSchemaVersion
  /// Versions with an explicit ZIP decoder in this build, oldest first.
  public static let supportedSchemaVersions = [firstPublicSchemaVersion]
  public static var supportedSchemaVersionsDescription: String {
    supportedSchemaVersions.joined(separator: ", ")
  }

  public var schemaVersion: String
  public var generatedAt: String?
  public var appVersion: String?
  public var fileCounts: [String: Int]

  public init(
    schemaVersion: String,
    generatedAt: String?,
    appVersion: String?,
    fileCounts: [String: Int]
  ) {
    self.schemaVersion = schemaVersion
    self.generatedAt = generatedAt
    self.appVersion = appVersion
    self.fileCounts = fileCounts
  }
}

/// Which app + device produced a single-file JSON export.
///
/// `platform` is always `"apple"` for this app; `appVersion` and `deviceID` are
/// best-effort (absent when the producing surface can't supply them). This is
/// provenance for an AI-driven migration, not a restore input — the importer
/// reads it for context and never applies it.
public struct ExportSource: Codable, Sendable {
  public static let applePlatform = "apple"

  public var platform: String
  public var appVersion: String?
  public var deviceID: String?

  public init(
    platform: String = ExportSource.applePlatform,
    appVersion: String? = nil,
    deviceID: String? = nil
  ) {
    self.platform = platform
    self.appVersion = appVersion
    self.deviceID = deviceID
  }
}

/// Provenance + inventory header carried inside a single-file JSON export — the
/// single-file analogue of the ZIP package's `ExportManifest`.
///
/// Carries the export `formatVersion` and `schemaVersion`, the producing
/// `source`, an optional wall-clock `generatedAt`, and a per-category
/// `entityCounts` map (keyed by `LorvexDataExportCategory` raw value). Public-v1
/// import treats the map as an exact inventory: every included selectable
/// category is declared once with its decoded record count, and no omitted
/// category may be declared. Internal task/calendar dependency members ride
/// with their parent category and are not counted separately.
public struct ExportPayloadManifest: Codable, Sendable {
  public var formatVersion: String
  public var schemaVersion: String
  public var generatedAt: String?
  public var source: ExportSource
  public var entityCounts: [String: Int]

  public init(
    formatVersion: String,
    schemaVersion: String,
    generatedAt: String? = nil,
    source: ExportSource,
    entityCounts: [String: Int]
  ) {
    self.formatVersion = formatVersion
    self.schemaVersion = schemaVersion
    self.generatedAt = generatedAt
    self.source = source
    self.entityCounts = entityCounts
  }
}

/// Container for all export entity collections. Nil means "not included in this export run."
///
/// `formatVersion` is the single-file-JSON export's version envelope (the ZIP
/// package carries its own version in `ExportManifest.schemaVersion`): the
/// exporter stamps `currentFormatVersion`, and the single-file-JSON importer is
/// fail-fast — it rejects a file whose version is absent (`nil` on decode) or one
/// it does not understand rather than mis-decoding it, since there are no released
/// users or legacy files to tolerate.
///
/// `manifest` carries the export's provenance (producing app/device) and the
/// exact per-category inventory for a single-file JSON export. Provenance is
/// never applied to the destination store, while the version and inventory are
/// verified before preview/apply.
public struct LorvexDataExportPayload: Codable, Sendable {
  /// The single-file backup version designated for the first public
  /// compatibility contract. Keep its decoder forever once that build ships.
  public static let firstPublicFormatVersion = BackupV1Contract.formatVersion
  public static let currentFormatVersion = firstPublicFormatVersion
  /// Versions with an explicit single-file decoder in this build, oldest first.
  public static let supportedFormatVersions = [firstPublicFormatVersion]
  public static var supportedFormatVersionsDescription: String {
    supportedFormatVersions.joined(separator: ", ")
  }

  public var formatVersion: String?
  public var manifest: ExportPayloadManifest?
  public var tasks: [ExportTask]?
  /// Exact Apple task-history materialization for fresh-store restore. The
  /// portable `tasks` array remains the semantic migration document and is the
  /// only task representation emitted to AI/CSV callers.
  public var nativeTaskGraph: NativeTaskGraphSnapshot?
  public var lists: [ExportList]?
  public var tags: [ExportTag]?
  public var habits: [ExportHabit]?
  public var calendarSeriesCutovers: [ExportCalendarSeriesCutover]?
  public var calendarEvents: [ExportCalendarEvent]?
  public var dailyReviews: [ExportDailyReview]?
  public var currentFocus: [ExportCurrentFocus]?
  public var focusSchedules: [ExportFocusSchedule]?
  public var taskCalendarEventLinks: [ExportTaskCalendarEventLink]?
  public var memory: [ExportMemoryEntry]?
  public var preferences: [ExportPreference]?

  public init(
    formatVersion: String? = currentFormatVersion,
    manifest: ExportPayloadManifest? = nil,
    tasks: [ExportTask]? = nil,
    nativeTaskGraph: NativeTaskGraphSnapshot? = nil,
    lists: [ExportList]? = nil,
    tags: [ExportTag]? = nil,
    habits: [ExportHabit]? = nil,
    calendarSeriesCutovers: [ExportCalendarSeriesCutover]? = nil,
    calendarEvents: [ExportCalendarEvent]? = nil,
    dailyReviews: [ExportDailyReview]? = nil,
    currentFocus: [ExportCurrentFocus]? = nil,
    focusSchedules: [ExportFocusSchedule]? = nil,
    taskCalendarEventLinks: [ExportTaskCalendarEventLink]? = nil,
    memory: [ExportMemoryEntry]? = nil,
    preferences: [ExportPreference]? = nil
  ) {
    self.formatVersion = formatVersion
    self.manifest = manifest
    self.tasks = tasks
    self.nativeTaskGraph = nativeTaskGraph
    self.lists = lists
    self.tags = tags
    self.habits = habits
    self.calendarSeriesCutovers = calendarSeriesCutovers
    self.calendarEvents = calendarEvents
    self.dailyReviews = dailyReviews
    self.currentFocus = currentFocus
    self.focusSchedules = focusSchedules
    self.taskCalendarEventLinks = taskCalendarEventLinks
    self.memory = memory
    self.preferences = preferences
  }
}
