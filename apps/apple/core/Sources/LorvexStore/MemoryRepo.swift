import Foundation
import GRDB
import LorvexDomain

/// One row from the `memories` table.
///
/// `updatedAt` is a parsed ``SyncTimestamp`` rather than a bare string so
/// row comparisons / orderings flow through the parsed millisecond instant
/// rather than lex-compared strings — fractional-digit drift between
/// 3-digit and 6-digit emitters would otherwise silently misorder rows.
public struct MemoryEntry: Sendable, Equatable {
  public let key: String
  public let content: String
  public let version: String
  public let updatedAt: SyncTimestamp

  public init(key: String, content: String, version: String, updatedAt: SyncTimestamp) {
    self.key = key
    self.content = content
    self.version = version
    self.updatedAt = updatedAt
  }
}

/// `memories`-table read operations.
public enum MemoryRepo {
  /// Look up one memory by key. Returns `nil` if no row matches.
  public static func getMemoryEntry(_ db: Database, key: String) throws -> MemoryEntry? {
    let row = try Row.fetchOne(
      db,
      sql: "SELECT key, content, version, updated_at FROM memories WHERE key = ?",
      arguments: [key])
    guard let row else { return nil }
    return try rowToMemoryEntry(row)
  }

  /// Map a GRDB row (columns ordered `key, content, version, updated_at`) to
  /// a typed ``MemoryEntry``. Centralizes the ``SyncTimestamp/parse(_:)``
  /// gate so non-canonical timestamps surface as a typed error rather than
  /// silently mis-ordering downstream.
  public static func rowToMemoryEntry(_ row: Row) throws -> MemoryEntry {
    let key: String = row[0]
    let content: String = row[1]
    let version: String = row[2]
    let rawUpdated: String = row[3]
    guard let updatedAt = SyncTimestamp.parse(rawUpdated) else {
      throw DatabaseError(
        resultCode: .SQLITE_MISMATCH,
        message:
          "memories.updated_at is not a canonical sync timestamp: \(rawUpdated)")
    }
    return MemoryEntry(
      key: key, content: content, version: version, updatedAt: updatedAt)
  }
}
