import Foundation

/// A small diagnostics file beside the database, for failures the database
/// itself cannot record.
///
/// The app's diagnostics live in the `error_logs` table, so when the store is
/// the thing failing (it cannot be opened, or every write fails) the failure
/// that explains the problem is lost with it. Callers append here when the
/// failure they are logging is a storage failure, or when writing it to
/// `error_logs` threw; the diagnostics screen merges these entries into its
/// list.
///
/// The file is a JSON array in the app's own Application Support directory
/// (never the shared App Group container, which holds the store being
/// diagnosed), trimmed to the newest ``maximumEntries``. Every operation is
/// best-effort: a failure to read or write the file is ignored, since there is
/// nowhere further to report it. Not thread-safe; callers serialize access on
/// one actor.
public struct DiagnosticFallbackLog: Sendable {
  public static let maximumEntries = 100

  private struct Entry: Codable {
    var timestamp: String
    var source: String
    var message: String
    var details: String?
  }

  public let fileURL: URL?

  public init(fileURL: URL?) {
    self.fileURL = fileURL
  }

  /// The app's own `Application Support/Lorvex/diagnostics-fallback.json`.
  public static var live: DiagnosticFallbackLog {
    let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first?
      .appendingPathComponent("Lorvex", isDirectory: true)
    return DiagnosticFallbackLog(
      fileURL: directory?.appendingPathComponent("diagnostics-fallback.json", isDirectory: false))
  }

  public func append(source: String, message: String, details: String?, at date: Date = Date()) {
    guard let fileURL else { return }
    var entries = load()
    entries.append(
      Entry(
        timestamp: LorvexDateFormatters.iso8601Fractional.string(from: date),
        source: source, message: message, details: details))
    if entries.count > Self.maximumEntries {
      entries.removeFirst(entries.count - Self.maximumEntries)
    }
    guard let data = try? JSONEncoder().encode(entries) else { return }
    try? FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: fileURL, options: .atomic)
  }

  /// The recorded failures as diagnostics rows, newest first. Each row is an
  /// `error`-level `error_log` row whose origin is the failure's source.
  public func recentEntries() -> [RecentLogEntry] {
    load().enumerated().reversed().map { index, entry in
      RecentLogEntry(
        id: "fallback-\(index)-\(entry.timestamp)", timestamp: entry.timestamp, source: "error_log",
        level: .error, summary: entry.message, details: entry.details, origin: entry.source)
    }
  }

  private func load() -> [Entry] {
    guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return [] }
    return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
  }
}
