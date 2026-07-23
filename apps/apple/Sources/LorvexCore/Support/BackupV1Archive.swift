import Foundation

/// Closed, ordered public-v1 ZIP inventory. The same registry drives archive
/// production, archive decoding, and member-set tests.
enum BackupV1ZipMember: String, CaseIterable, Sendable {
  case tasks = "tasks.json"
  case nativeTaskGraph = "native_task_graph.json"
  case lists = "lists.json"
  case tags = "tags.json"
  case habits = "habits.json"
  case calendarSeriesCutovers = "calendar_series_cutovers.json"
  case calendarEvents = "calendar_events.json"
  case dailyReviews = "daily_reviews.json"
  case currentFocus = "current_focus.json"
  case focusSchedules = "focus_schedules.json"
  case taskCalendarEventLinks = "task_calendar_event_links.json"
  case memory = "memory.json"
  case preferences = "preferences.json"

  static let manifestPath = "manifest.json"

  var baseName: String { String(rawValue.dropLast(".json".count)) }

  var singleFileKey: String {
    switch self {
    case .tasks: return "tasks"
    case .nativeTaskGraph: return "nativeTaskGraph"
    case .lists: return "lists"
    case .tags: return "tags"
    case .habits: return "habits"
    case .calendarSeriesCutovers: return "calendarSeriesCutovers"
    case .calendarEvents: return "calendarEvents"
    case .dailyReviews: return "dailyReviews"
    case .currentFocus: return "currentFocus"
    case .focusSchedules: return "focusSchedules"
    case .taskCalendarEventLinks: return "taskCalendarEventLinks"
    case .memory: return "memory"
    case .preferences: return "preferences"
    }
  }

  static var allowedPaths: Set<String> {
    Set(allCases.map(\.rawValue)).union([manifestPath])
  }

  init?(path: String) {
    self.init(rawValue: path)
  }

  func encoded(from payload: BackupV1Payload, using encoder: JSONEncoder) throws
    -> BackupV1EncodedZipMember?
  {
    switch self {
    case .tasks:
      return try Self.encode(payload.tasks, member: self, count: payload.tasks?.count ?? 0, encoder)
    case .nativeTaskGraph:
      return try Self.encode(
        payload.nativeTaskGraph, member: self,
        count: payload.nativeTaskGraph == nil ? 0 : 1, encoder)
    case .lists:
      return try Self.encode(payload.lists, member: self, count: payload.lists?.count ?? 0, encoder)
    case .tags:
      return try Self.encode(payload.tags, member: self, count: payload.tags?.count ?? 0, encoder)
    case .habits:
      return try Self.encode(payload.habits, member: self, count: payload.habits?.count ?? 0, encoder)
    case .calendarSeriesCutovers:
      return try Self.encode(
        payload.calendarSeriesCutovers, member: self,
        count: payload.calendarSeriesCutovers?.count ?? 0, encoder)
    case .calendarEvents:
      return try Self.encode(
        payload.calendarEvents, member: self,
        count: payload.calendarEvents?.count ?? 0, encoder)
    case .dailyReviews:
      return try Self.encode(
        payload.dailyReviews, member: self,
        count: payload.dailyReviews?.count ?? 0, encoder)
    case .currentFocus:
      return try Self.encode(
        payload.currentFocus, member: self,
        count: payload.currentFocus?.count ?? 0, encoder)
    case .focusSchedules:
      return try Self.encode(
        payload.focusSchedules, member: self,
        count: payload.focusSchedules?.count ?? 0, encoder)
    case .taskCalendarEventLinks:
      return try Self.encode(
        payload.taskCalendarEventLinks, member: self,
        count: payload.taskCalendarEventLinks?.count ?? 0, encoder)
    case .memory:
      return try Self.encode(
        payload.memory, member: self, count: payload.memory?.count ?? 0, encoder)
    case .preferences:
      return try Self.encode(
        payload.preferences, member: self,
        count: payload.preferences?.count ?? 0, encoder)
    }
  }

  private static func encode<Value: Encodable>(
    _ value: Value?, member: BackupV1ZipMember, count: Int, _ encoder: JSONEncoder
  ) throws -> BackupV1EncodedZipMember? {
    guard let value else { return nil }
    return BackupV1EncodedZipMember(
      member: member, count: count, data: try encoder.encode(value))
  }
}

struct BackupV1EncodedZipMember: Sendable {
  var member: BackupV1ZipMember
  var count: Int
  var data: Data
}

/// The only production encoder for public-v1 JSON and ZIP artifacts.
enum BackupV1Archive {
  static func decodeJSON(_ data: Data) throws -> LorvexDataExportPayload {
    try JSONDecoder().decode(BackupV1Payload.self, from: data).current()
  }

  static func decodeZip(
    entries: [LorvexZipArchive.Entry], manifestData: Data
  ) throws -> LorvexDataExportPayload {
    do {
      let manifest = try decodeZipValue(
        BackupV1ZipManifest.self, manifestData, path: BackupV1ZipMember.manifestPath)
      guard manifest.schemaVersion == BackupV1Contract.zipSchemaVersion else {
        throw LorvexDataImporter.ImportError.incompatibleManifest(
          found: manifest.schemaVersion, supported: BackupV1Contract.zipSchemaVersion)
      }

      var payload = LorvexDataExportPayload()
      var observedCounts: [String: Int] = [:]
      for entry in entries {
        if entry.path == BackupV1ZipMember.manifestPath { continue }
        guard let member = BackupV1ZipMember(path: entry.path) else {
          throw LorvexDataImporter.ImportError.unexpectedArchiveEntry(entry.path)
        }
        switch member {
        case .tasks:
          let rows = try decodeZipValue([BackupV1Task].self, entry.data, path: entry.path)
          payload.tasks = try rows.map { try $0.current() }
          observedCounts[member.baseName] = rows.count
        case .nativeTaskGraph:
          let snapshot = try decodeZipValue(
            BackupV1NativeTaskGraph.self, entry.data, path: entry.path)
          guard snapshot.schemaVersion == BackupV1Contract.nativeTaskGraphSchemaVersion else {
            throw LorvexDataImporter.ImportError.incompatibleNativeTaskGraph(
              found: snapshot.schemaVersion,
              supported: BackupV1Contract.nativeTaskGraphSchemaVersion)
          }
          payload.nativeTaskGraph = try snapshot.current()
          observedCounts[member.baseName] = 1
        case .lists:
          let rows = try decodeZipValue([BackupV1List].self, entry.data, path: entry.path)
          payload.lists = rows.map(\.current)
          observedCounts[member.baseName] = rows.count
        case .tags:
          let rows = try decodeZipValue([BackupV1Tag].self, entry.data, path: entry.path)
          payload.tags = rows.map(\.current)
          observedCounts[member.baseName] = rows.count
        case .habits:
          let rows = try decodeZipValue([BackupV1Habit].self, entry.data, path: entry.path)
          payload.habits = rows.map(\.current)
          observedCounts[member.baseName] = rows.count
        case .calendarSeriesCutovers:
          let rows = try decodeZipValue(
            [BackupV1CalendarSeriesCutover].self, entry.data, path: entry.path)
          payload.calendarSeriesCutovers = rows.map(\.current)
          observedCounts[member.baseName] = rows.count
        case .calendarEvents:
          let rows = try decodeZipValue(
            [BackupV1CalendarEvent].self, entry.data, path: entry.path)
          payload.calendarEvents = rows.map(\.current)
          observedCounts[member.baseName] = rows.count
        case .dailyReviews:
          let rows = try decodeZipValue(
            [BackupV1DailyReview].self, entry.data, path: entry.path)
          payload.dailyReviews = rows.map(\.current)
          observedCounts[member.baseName] = rows.count
        case .currentFocus:
          let rows = try decodeZipValue(
            [BackupV1CurrentFocus].self, entry.data, path: entry.path)
          payload.currentFocus = rows.map(\.current)
          observedCounts[member.baseName] = rows.count
        case .focusSchedules:
          let rows = try decodeZipValue(
            [BackupV1FocusSchedule].self, entry.data, path: entry.path)
          payload.focusSchedules = try rows.map { try $0.current() }
          observedCounts[member.baseName] = rows.count
        case .taskCalendarEventLinks:
          let rows = try decodeZipValue(
            [BackupV1TaskCalendarEventLink].self, entry.data, path: entry.path)
          payload.taskCalendarEventLinks = rows.map(\.current)
          observedCounts[member.baseName] = rows.count
        case .memory:
          let rows = try decodeZipValue(
            [BackupV1MemoryEntry].self, entry.data, path: entry.path)
          payload.memory = try rows.map { try $0.current() }
          observedCounts[member.baseName] = rows.count
        case .preferences:
          let rows = try decodeZipValue(
            [BackupV1Preference].self, entry.data, path: entry.path)
          payload.preferences = rows.map(\.current)
          observedCounts[member.baseName] = rows.count
        }
      }
      try validateManifestInventory(manifest: manifest, observed: observedCounts)
      try BackupV1PayloadPreflight.validateParentMemberRelationships(payload)
      return payload
    } catch let importError as LorvexDataImporter.ImportError {
      throw importError
    } catch {
      throw LorvexDataImporter.ImportError.malformedZip(error.localizedDescription)
    }
  }

  static func renderJSON(_ payload: LorvexDataExportPayload) throws -> Data {
    // Never mint a public-v1 artifact that this same build would reject. This
    // catches native/portable graph drift and orphaned aggregate members at the
    // producer boundary instead of discovering them only during disaster restore.
    try BackupV1PayloadPreflight.validate(payload)
    return try encoder().encode(BackupV1Payload(current: payload))
  }

  static func renderZip(
    _ payload: LorvexDataExportPayload,
    generatedAt: String?,
    appVersion: String?
  ) throws -> Data {
    try BackupV1PayloadPreflight.validate(payload)
    let encoder = encoder()
    let wire = try BackupV1Payload(current: payload)
    var archiveEntries: [LorvexZipArchive.Entry] = []
    var counts: [String: Int] = [:]

    for member in BackupV1ZipMember.allCases {
      guard let encoded = try member.encoded(from: wire, using: encoder) else { continue }
      archiveEntries.append(
        LorvexZipArchive.Entry(path: member.rawValue, data: encoded.data))
      counts[member.baseName] = encoded.count
    }

    let manifest = BackupV1ZipManifest(
      generatedAt: generatedAt, appVersion: appVersion, fileCounts: counts)
    archiveEntries.insert(
      LorvexZipArchive.Entry(
        path: BackupV1ZipMember.manifestPath,
        data: try encoder.encode(manifest)),
      at: 0)
    return try LorvexZipArchive.archive(entries: archiveEntries)
  }

  private static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }

  private static func decodeZipValue<Value: Decodable>(
    _ type: Value.Type, _ data: Data, path: String
  ) throws -> Value {
    do {
      return try JSONDecoder().decode(Value.self, from: data)
    } catch let error as DecodingError {
      throw LorvexDataImporter.ImportError.malformedZip(
        "\(path): \(describe(error))")
    }
  }

  private static func validateManifestInventory(
    manifest: BackupV1ZipManifest, observed: [String: Int]
  ) throws {
    let manifestKeys = Set(manifest.fileCounts.keys)
    let observedKeys = Set(observed.keys)
    guard manifestKeys == observedKeys else {
      let missing = manifestKeys.subtracting(observedKeys).sorted()
      let extra = observedKeys.subtracting(manifestKeys).sorted()
      var parts: [String] = []
      if !missing.isEmpty {
        parts.append("manifest lists \(missing.joined(separator: ", ")) not present in the archive")
      }
      if !extra.isEmpty {
        parts.append("archive contains \(extra.joined(separator: ", ")) not listed in the manifest")
      }
      throw LorvexDataImporter.ImportError.manifestCountMismatch(
        parts.joined(separator: "; "))
    }
    for (name, count) in observed.sorted(by: { $0.key < $1.key })
    where manifest.fileCounts[name] != count {
      let declared = manifest.fileCounts[name].map(String.init) ?? "none"
      throw LorvexDataImporter.ImportError.manifestCountMismatch(
        "\(name) holds \(count) records but the manifest declares \(declared)")
    }
  }

  private static func describe(_ error: DecodingError) -> String {
    switch error {
    case .dataCorrupted(let context):
      return context.debugDescription
    case .keyNotFound(let key, _):
      return "missing key \"\(key.stringValue)\""
    case .typeMismatch(_, let context), .valueNotFound(_, let context):
      return context.debugDescription
    @unknown default:
      return "unrecognized JSON shape"
    }
  }
}
