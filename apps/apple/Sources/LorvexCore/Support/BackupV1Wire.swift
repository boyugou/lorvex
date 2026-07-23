import Foundation
import LorvexDomain

/// Errors raised while adapting the immutable public-v1 wire model to or from
/// the app's current in-memory export model.
enum BackupV1WireError: LocalizedError, Equatable {
  case incompatibleFormatVersion(String?)
  case invalidIdentity(field: String, value: String?)
  case invalidHLC(field: String, value: String)
  case invalidEntityKind(String)
  case invalidFocusEventSource(String)

  var errorDescription: String? {
    switch self {
    case .incompatibleFormatVersion(let value):
      return "public-v1 encoding requires formatVersion 1, found \(value ?? "nil")"
    case .invalidIdentity(let field, let value):
      return "\(field) must be a canonical hyphenated lowercase UUID, found \(value ?? "nil")"
    case .invalidHLC(let field, let value):
      return "\(field) is not a canonical HLC: \(value)"
    case .invalidEntityKind(let value):
      return "unknown native task entity type: \(value)"
    case .invalidFocusEventSource(let value):
      return "unknown focus schedule event source: \(value)"
    }
  }
}

enum BackupV1WireValidation {
  static func canonicalIdentity(_ value: String?, field: String) throws -> String {
    guard let value, SyncEntityId.isCanonicalUuid(value) else {
      throw BackupV1WireError.invalidIdentity(field: field, value: value)
    }
    return value
  }

  static func hlc(_ value: String, field: String) throws -> Hlc {
    do {
      return try Hlc.parseCanonical(value)
    } catch {
      throw BackupV1WireError.invalidHLC(field: field, value: value)
    }
  }
}

struct BackupV1Source: Codable, Sendable, Equatable {
  var platform: String
  var appVersion: String?
  var deviceID: String?

  init(current: ExportSource) {
    platform = current.platform
    appVersion = current.appVersion
    deviceID = current.deviceID
  }

  var current: ExportSource {
    ExportSource(platform: platform, appVersion: appVersion, deviceID: deviceID)
  }
}

struct BackupV1PayloadManifest: Codable, Sendable, Equatable {
  var formatVersion: String
  var schemaVersion: String
  var generatedAt: String?
  var source: BackupV1Source
  var entityCounts: [String: Int]

  init(current: ExportPayloadManifest) {
    formatVersion = current.formatVersion
    schemaVersion = current.schemaVersion
    generatedAt = current.generatedAt
    source = BackupV1Source(current: current.source)
    entityCounts = current.entityCounts
  }

  var current: ExportPayloadManifest {
    ExportPayloadManifest(
      formatVersion: formatVersion, schemaVersion: schemaVersion,
      generatedAt: generatedAt, source: source.current, entityCounts: entityCounts)
  }
}

/// Immutable top-level public-v1 document. Every nested value is another v1
/// wire DTO whose stored properties are JSON primitives, arrays, dictionaries,
/// or other frozen v1 DTOs. It never aliases the app's mutable export models.
struct BackupV1Payload: Codable, Sendable {
  var formatVersion: String
  var manifest: BackupV1PayloadManifest?
  var tasks: [BackupV1Task]?
  var nativeTaskGraph: BackupV1NativeTaskGraph?
  var lists: [BackupV1List]?
  var tags: [BackupV1Tag]?
  var habits: [BackupV1Habit]?
  var calendarSeriesCutovers: [BackupV1CalendarSeriesCutover]?
  var calendarEvents: [BackupV1CalendarEvent]?
  var dailyReviews: [BackupV1DailyReview]?
  var currentFocus: [BackupV1CurrentFocus]?
  var focusSchedules: [BackupV1FocusSchedule]?
  var taskCalendarEventLinks: [BackupV1TaskCalendarEventLink]?
  var memory: [BackupV1MemoryEntry]?
  var preferences: [BackupV1Preference]?

  init(current: LorvexDataExportPayload) throws {
    guard current.formatVersion == BackupV1Contract.formatVersion else {
      throw BackupV1WireError.incompatibleFormatVersion(current.formatVersion)
    }
    formatVersion = BackupV1Contract.formatVersion
    manifest = current.manifest.map(BackupV1PayloadManifest.init(current:))
    tasks = try current.tasks?.map(BackupV1Task.init(current:))
    nativeTaskGraph = current.nativeTaskGraph.map(BackupV1NativeTaskGraph.init(current:))
    lists = current.lists?.map(BackupV1List.init(current:))
    tags = current.tags?.map(BackupV1Tag.init(current:))
    habits = current.habits?.map(BackupV1Habit.init(current:))
    calendarSeriesCutovers = current.calendarSeriesCutovers?.map(
      BackupV1CalendarSeriesCutover.init(current:))
    calendarEvents = current.calendarEvents?.map(BackupV1CalendarEvent.init(current:))
    dailyReviews = current.dailyReviews?.map(BackupV1DailyReview.init(current:))
    currentFocus = current.currentFocus?.map(BackupV1CurrentFocus.init(current:))
    focusSchedules = current.focusSchedules?.map(BackupV1FocusSchedule.init(current:))
    taskCalendarEventLinks = current.taskCalendarEventLinks?.map(
      BackupV1TaskCalendarEventLink.init(current:))
    memory = try current.memory?.map(BackupV1MemoryEntry.init(current:))
    preferences = current.preferences?.map(BackupV1Preference.init(current:))
  }

  func current() throws -> LorvexDataExportPayload {
    LorvexDataExportPayload(
      formatVersion: formatVersion, manifest: manifest?.current,
      tasks: try tasks?.map { try $0.current() },
      nativeTaskGraph: try nativeTaskGraph?.current(),
      lists: lists?.map(\.current), tags: tags?.map(\.current),
      habits: habits?.map(\.current),
      calendarSeriesCutovers: calendarSeriesCutovers?.map(\.current),
      calendarEvents: calendarEvents?.map(\.current),
      dailyReviews: dailyReviews?.map(\.current),
      currentFocus: currentFocus?.map(\.current),
      focusSchedules: try focusSchedules?.map { try $0.current() },
      taskCalendarEventLinks: taskCalendarEventLinks?.map(\.current),
      memory: try memory?.map { try $0.current() },
      preferences: preferences?.map(\.current))
  }
}

/// Immutable public-v1 ZIP manifest.
struct BackupV1ZipManifest: Codable, Sendable, Equatable {
  var schemaVersion: String
  var generatedAt: String?
  var appVersion: String?
  var fileCounts: [String: Int]

  init(generatedAt: String?, appVersion: String?, fileCounts: [String: Int]) {
    schemaVersion = BackupV1Contract.zipSchemaVersion
    self.generatedAt = generatedAt
    self.appVersion = appVersion
    self.fileCounts = fileCounts
  }
}
