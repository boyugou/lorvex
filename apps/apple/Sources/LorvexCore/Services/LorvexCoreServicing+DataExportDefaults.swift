import Foundation

extension LorvexDataExportServicing {
  /// Serializes the requested categories to JSON or CSV. The convenience entry
  /// point carries no caller source identity, so the JSON manifest records only
  /// `platform: "apple"` and the store's device id (no app version / generated-at).
  public func exportData(entities: [String], format: String) async throws -> String {
    try await exportData(entities: entities, format: format, appVersion: nil, generatedAt: nil)
  }

  /// Serializes the requested categories, stamping the single-file JSON export's
  /// provenance manifest from the caller-supplied `appVersion` / `generatedAt`
  /// plus the device id read from the store. CSV carries no manifest.
  public func exportData(
    entities: [String], format: String, appVersion: String?, generatedAt: String?
  ) async throws -> String {
    let exportFormat: LorvexDataExportFormat = format == "csv" ? .csv : .json
    let snapshot = try await loadSnapshotForDataExport(
      entities: entities, forAI: false,
      includeNativeTaskGraph: exportFormat == .json)
    var payload = snapshot.payload
    if exportFormat == .json {
      payload.manifest = makeExportManifest(
        for: payload, sourceDeviceID: snapshot.sourceDeviceID,
        appVersion: appVersion, generatedAt: generatedAt)
    }
    return try LorvexDataExporter.render(payload: payload, format: exportFormat)
  }

  /// AI-facing counterpart to ``exportData(entities:format:)``. Only the focus
  /// schedule loader differs: it applies the device's calendar AI-access tier,
  /// so `off` cannot be bypassed by asking MCP for a data export. Human-initiated
  /// Settings/App-Intent backups continue to use the complete export above.
  public func exportDataForAI(
    entities: [String], format: String, appVersion: String?, generatedAt: String?
  ) async throws -> String {
    let exportFormat: LorvexDataExportFormat = format == "csv" ? .csv : .json
    let snapshot = try await loadSnapshotForDataExport(
      entities: entities, forAI: true, includeNativeTaskGraph: false)
    var payload = snapshot.payload
    if exportFormat == .json {
      payload.manifest = makeExportManifest(
        for: payload, sourceDeviceID: snapshot.sourceDeviceID,
        appVersion: appVersion, generatedAt: generatedAt)
    }
    return try LorvexDataExporter.render(payload: payload, format: exportFormat)
  }

  /// Build the single-file JSON provenance manifest: the format/schema versions,
  /// the producing source (`platform: "apple"`, the caller `appVersion`, and the
  /// store's device id), an optional `generatedAt`, and a per-category record
  /// count drawn from the assembled payload.
  private func makeExportManifest(
    for payload: LorvexDataExportPayload, sourceDeviceID: String?,
    appVersion: String?, generatedAt: String?
  ) -> ExportPayloadManifest {
    var counts: [String: Int] = [:]
    func count(_ category: LorvexDataExportCategory, _ value: Int?) {
      if let value { counts[category.rawValue] = value }
    }
    count(.tasks, payload.tasks?.count)
    count(.lists, payload.lists?.count)
    count(.tags, payload.tags?.count)
    count(.habits, payload.habits?.count)
    if payload.calendarEvents != nil || payload.calendarSeriesCutovers != nil {
      count(.calendarEvents, payload.calendarEvents?.count ?? 0)
    }
    count(.dailyReviews, payload.dailyReviews?.count)
    count(.currentFocus, payload.currentFocus?.count)
    count(.focusSchedules, payload.focusSchedules?.count)
    count(.taskCalendarEventLinks, payload.taskCalendarEventLinks?.count)
    count(.memory, payload.memory?.count)
    count(.preferences, payload.preferences?.count)
    return ExportPayloadManifest(
      formatVersion: payload.formatVersion ?? LorvexDataExportPayload.currentFormatVersion,
      schemaVersion: ExportManifest.currentSchemaVersion,
      generatedAt: generatedAt,
      source: ExportSource(
        platform: ExportSource.applePlatform, appVersion: appVersion,
        deviceID: sourceDeviceID),
      entityCounts: counts)
  }

  /// Packages the requested categories as a `.zip` archive with one JSON file
  /// per included category plus a top-level `manifest.json`.
  ///
  /// `entities` follows the same selection rules as `exportData(entities:format:)`
  /// (empty or `["all"]` includes everything). `generatedAt` and `appVersion`
  /// are stamped into the manifest by the caller; the writer itself never reads
  /// the clock.
  ///
  public func exportDataZip(
    entities: [String],
    generatedAt: String?,
    appVersion: String?
  ) async throws -> Data {
    let snapshot = try await loadSnapshotForDataExport(
      entities: entities, forAI: false, includeNativeTaskGraph: true)

    return try LorvexDataExporter.renderZip(
      payload: snapshot.payload,
      generatedAt: generatedAt,
      appVersion: appVersion
    )
  }

  /// Non-storage conformers must opt into export explicitly. A sequence of
  /// independent protocol reads is not a backup snapshot and can duplicate,
  /// omit, or cross-wire aggregates while another process writes the store.
  public func loadSnapshotForDataExport(
    entities: [String], forAI: Bool, includeNativeTaskGraph: Bool
  ) async throws -> LorvexDataExportSnapshot {
    _ = (entities, forAI, includeNativeTaskGraph)
    throw LorvexCoreError.unsupportedOperation(
      "This core backend does not provide transactionally consistent data export.")
  }
}

/// Explicit in-memory v1 resource bounds. The exporter verifies the matching
/// table count inside the same read transaction and FAILS when a category is
/// larger, rather than silently truncating at these limits. The raw calendar
/// range covers the SQLite date domain in full (`loadCalendarEventsForDataExport`
/// pages through it), so a full export never misses an event outside some
/// narrower window.
enum LorvexDataExportWindow {
  static let taskPageSize = 500
  static let calendarPageSize: UInt32 = 500
  static let reviewHistoryLimit = 100_000
  static let habitCompletionLimit = 1_000_000
  static let rawCalendarFrom = "0001-01-01"
  static let rawCalendarTo = "9999-12-31"
}
