import Foundation

/// Converts a `LorvexDataExportPayload` to either a JSON string or a multi-section CSV string.
///
/// JSON uses standard `JSONEncoder` with `.prettyPrinted` and `.sortedKeys`. CSV
/// follows RFC 4180: fields that contain a comma, double-quote, or newline are
/// enclosed in double-quotes; embedded double-quotes are escaped by doubling.
/// Each entity type is preceded by a `## <EntityName>` comment line and a header
/// row; absent entities are omitted entirely.
/// A data export failed to serialize. Surfaced (rather than swallowed) so a
/// failed export never masquerades as a partial archive or an empty `{}` string.
public enum LorvexDataExportError: Error, Sendable {
  /// `JSONEncoder.encode` produced bytes that are not valid UTF-8 (not
  /// reachable for the current DTOs, but propagated rather than silently
  /// returning `{}`).
  case utf8DecodeFailed
  /// A v1 JSON artifact would exceed the portable iPhone-safe wire limit.
  case outputTooLarge(size: Int, limit: Int)
  /// A bounded in-memory v1 category cannot be exported without truncation.
  case categoryRowLimitExceeded(category: String, count: Int, limit: Int)
}

public enum LorvexDataExporter: Sendable {
  public static func render(payload: LorvexDataExportPayload, format: LorvexDataExportFormat) throws
    -> String
  {
    switch format {
    case .json:
      return try renderJSON(payload)
    case .csv:
      return renderCSV(payload)
    }
  }

  /// Packages the payload as a `.zip` archive: one pretty-printed JSON file per
  /// included category (`tasks.json`, `lists.json`, `calendar_events.json`, …)
  /// plus a top-level `manifest.json`.
  ///
  /// File names use the `LorvexDataExportCategory` raw values; each is an array.
  /// The manifest records a fixed
  /// `schemaVersion`, the caller-supplied
  /// `generatedAt`/`appVersion` (each omitted when nil), and a per-file entry
  /// count. Entries are emitted in a stable order so the archive is deterministic
  /// for identical input.
  public static func renderZip(
    payload: LorvexDataExportPayload,
    generatedAt: String?,
    appVersion: String?
  ) throws -> Data {
    try BackupV1Archive.renderZip(
      payload, generatedAt: generatedAt, appVersion: appVersion)
  }

  private static func renderJSON(_ payload: LorvexDataExportPayload) throws -> String {
    let data = try BackupV1Archive.renderJSON(payload)
    try BackupV1Contract.assertPortableOutputSize(data.count)
    guard let string = String(data: data, encoding: .utf8) else {
      throw LorvexDataExportError.utf8DecodeFailed
    }
    return string
  }

  private static func renderCSV(_ payload: LorvexDataExportPayload) -> String {
    var sections: [String] = []

    if let tasks = payload.tasks {
      sections.append(
        csvSection(header: "tasks", columns: ExportTask.columns, rows: tasks.map(\.csvRow)))
    }
    if let lists = payload.lists {
      sections.append(
        csvSection(header: "lists", columns: ExportList.columns, rows: lists.map(\.csvRow)))
    }
    if let tags = payload.tags {
      sections.append(
        csvSection(header: "tags", columns: ExportTag.columns, rows: tags.map(\.csvRow)))
    }
    if let habits = payload.habits {
      sections.append(
        csvSection(header: "habits", columns: ExportHabit.columns, rows: habits.map(\.csvRow)))
    }
    if let cutovers = payload.calendarSeriesCutovers {
      sections.append(
        csvSection(
          header: "calendar_series_cutovers",
          columns: ExportCalendarSeriesCutover.columns,
          rows: cutovers.map(\.csvRow)))
    }
    if let events = payload.calendarEvents {
      sections.append(
        csvSection(
          header: "calendar_events", columns: ExportCalendarEvent.columns,
          rows: events.map(\.csvRow)))
    }
    if let reviews = payload.dailyReviews {
      sections.append(
        csvSection(
          header: "daily_reviews", columns: ExportDailyReview.columns, rows: reviews.map(\.csvRow)))
    }
    if let focus = payload.currentFocus {
      sections.append(
        csvSection(
          header: "current_focus", columns: ExportCurrentFocus.columns, rows: focus.map(\.csvRow)))
    }
    if let schedules = payload.focusSchedules {
      sections.append(
        csvSection(
          header: "focus_schedules", columns: ExportFocusSchedule.columns,
          rows: schedules.map(\.csvRow)))
    }
    if let links = payload.taskCalendarEventLinks {
      sections.append(
        csvSection(
          header: "task_calendar_event_links",
          columns: ExportTaskCalendarEventLink.columns,
          rows: links.map(\.csvRow)))
    }
    if let memory = payload.memory {
      sections.append(
        csvSection(header: "memory", columns: ExportMemoryEntry.columns, rows: memory.map(\.csvRow))
      )
    }
    if let preferences = payload.preferences {
      sections.append(
        csvSection(
          header: "preferences", columns: ExportPreference.columns, rows: preferences.map(\.csvRow))
      )
    }

    return sections.joined(separator: "\n")
  }
}
