import Foundation
import GRDB
import LorvexDomain

/// Best-effort diagnostic writes to the `error_logs` table.
///
/// Redact-then-truncate contract: every column value is run through
/// `LorvexDomain.Diagnostics.redactDiagnosticText` before it lands in SQLite,
/// and the result is truncated to the column budget on UTF-8 byte boundaries.
/// Failures are swallowed so a broken diagnostic ring cannot eclipse the
/// primary failure the caller is logging.
public enum ErrorLog {
  private static let maxMessageBytes = 2048
  private static let maxDetailBytes = 8192

  /// Best-effort append. Never throws; a failed write is dropped silently.
  public static func appendBestEffort(
    _ db: Database, source: String, message: String, details: String?, level: String?
  ) {
    try? append(db, source: source, message: message, details: details, level: level)
  }

  /// Bound the diagnostics ring: delete rows older than `retentionDays`, then cap
  /// the table at the `maxRows` most-recent rows. A persistent failure writes a
  /// breadcrumb on every retention sweep, so without this the table grows
  /// unbounded. Returns the number of rows deleted.
  @discardableResult
  public static func gc(_ db: Database, retentionDays: UInt32, maxRows: Int) throws -> Int {
    try db.execute(
      sql: "DELETE FROM error_logs WHERE created_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?)",
      arguments: ["-\(retentionDays) days"])
    var deleted = db.changesCount
    try db.execute(
      sql: """
        DELETE FROM error_logs WHERE id NOT IN (
          SELECT id FROM error_logs ORDER BY created_at DESC, id DESC LIMIT ?
        )
        """,
      arguments: [maxRows])
    deleted += db.changesCount
    return deleted
  }

  private static func append(
    _ db: Database, source: String, message: String, details: String?, level: String?
  ) throws {
    let srcTrimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !srcTrimmed.isEmpty else { return }
    let preTruncatedSrc = truncateUTF8(srcTrimmed, maxBytes: maxMessageBytes)
    let redactedSrc = Diagnostics.redactDiagnosticText(preTruncatedSrc)
    let src = truncateUTF8(redactedSrc, maxBytes: maxMessageBytes)
    guard !src.isEmpty else { return }

    let msgTrimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !msgTrimmed.isEmpty else { return }
    let preTruncatedMsg = truncateUTF8(msgTrimmed, maxBytes: maxMessageBytes)
    let redactedMsg = Diagnostics.redactDiagnosticText(preTruncatedMsg)
    let finalMsg = truncateUTF8(redactedMsg, maxBytes: maxMessageBytes)
    guard !finalMsg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

    let finalDetails: String?
    if let raw = details {
      let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty {
        finalDetails = nil
      } else {
        let preTruncated = truncateUTF8(trimmed, maxBytes: maxDetailBytes)
        let redacted = Diagnostics.redactDiagnosticText(preTruncated)
        finalDetails = truncateUTF8(redacted, maxBytes: maxDetailBytes)
      }
    } else {
      finalDetails = nil
    }

    let id = EntityID.newEntityIDString()
    let now = SyncTimestampFormat.syncTimestampNow()
    try db.execute(
      sql: """
        INSERT INTO error_logs (id, source, level, message, details, created_at) \
        VALUES (?, ?, ?, ?, ?, ?)
        """,
      arguments: [id, src, normalizeLevel(level), finalMsg, finalDetails, now])
  }

  private static func normalizeLevel(_ level: String?) -> String {
    let parsed = level.flatMap { DiagnosticLogLevel(lenient: $0) } ?? .error
    return parsed.rawValue
  }

  /// Truncate to at most `maxBytes` UTF-8 bytes, never splitting a scalar.
  private static func truncateUTF8(_ value: String, maxBytes: Int) -> String {
    if value.utf8.count <= maxBytes { return value }
    var end = maxBytes
    let bytes = Array(value.utf8)
    // Back up to a UTF-8 leading byte (continuation bytes are 10xxxxxx).
    while end > 0 && (bytes[end] & 0xC0) == 0x80 {
      end -= 1
    }
    return String(decoding: bytes[0..<end], as: UTF8.self)
  }
}
