import Foundation
import GRDB
import LorvexDomain

/// One MCP client that has used this device's helper: the identity it sent in
/// its `initialize` request and when it was last active.
public struct AssistantSessionRow: Codable, Equatable, Sendable {
  /// `clientInfo.name`, the client's stable identifier, such as `claude-code`.
  public var name: String
  /// `clientInfo.title`, the client's display name when it sends one.
  public var title: String?
  /// `clientInfo.version`.
  public var version: String?
  /// When the client last started a session or called a tool, as a canonical
  /// sync timestamp (`YYYY-MM-DDTHH:MM:SS.mmmZ`).
  public var lastActiveAt: String

  enum CodingKeys: String, CodingKey {
    case name, title, version
    case lastActiveAt = "last_active_at"
  }

  public init(name: String, title: String?, version: String?, lastActiveAt: String) {
    self.name = name
    self.title = title
    self.version = version
    self.lastActiveAt = lastActiveAt
  }
}

/// The device-local record of which MCP clients have used this device's
/// helper: one JSON array under the `device_state` key
/// ``PreferenceKeys/devMcpClientSessions``, most recently active first, at most
/// ``maxClients`` entries.
///
/// It is bookkeeping for the Settings panel. It is never synced or exported,
/// and nothing depends on it, so a malformed value reads as empty and the next
/// write replaces it instead of failing the caller.
public enum AssistantSessionsRepo {
  /// The most clients the record keeps; the least recently active drop off.
  public static let maxClients = 8
  /// The longest name, title, or version kept, in characters.
  static let maxFieldLength = 100

  /// The recorded clients, most recently active first.
  public static func read(_ db: Database) throws -> [AssistantSessionRow] {
    guard
      let raw = try String.fetchOne(
        db, sql: "SELECT value FROM device_state WHERE key = ?1",
        arguments: [PreferenceKeys.devMcpClientSessions]),
      let rows = try? JSONDecoder().decode([AssistantSessionRow].self, from: Data(raw.utf8))
    else { return [] }
    return rows
  }

  /// Records that the client identified by `name` was active at `at`: its entry
  /// takes the given title and version and moves to the front. Every field is
  /// trimmed and bounded, and a blank name records nothing, so a client cannot
  /// grow the record without limit.
  public static func recordActivity(
    _ db: Database, name: String, title: String?, version: String?, at: String
  ) throws {
    guard let name = bounded(name) else { return }
    var rows = try read(db).filter { $0.name != name }
    rows.insert(
      AssistantSessionRow(
        name: name, title: bounded(title), version: bounded(version), lastActiveAt: at),
      at: 0)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let value = String(decoding: try encoder.encode(Array(rows.prefix(maxClients))), as: UTF8.self)
    try db.execute(
      sql: """
        INSERT INTO device_state (key, value) VALUES (?1, ?2) \
        ON CONFLICT(key) DO UPDATE SET value = excluded.value
        """,
      arguments: [PreferenceKeys.devMcpClientSessions, value])
  }

  static func bounded(_ raw: String?) -> String? {
    guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
    else { return nil }
    return String(trimmed.prefix(maxFieldLength))
  }
}
