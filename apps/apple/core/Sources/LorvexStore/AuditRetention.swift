import Foundation
import GRDB
import LorvexDomain

/// Retention of this device's `ai_changelog` audit trail.
///
/// The audit trail never leaves the device, so its retention is device-local:
/// the user's ``ChangelogRetentionPolicy`` is stored as its wire value in
/// `device_state` under ``PreferenceKeys/prefAiChangelogRetentionPolicy``, and
/// pruning is a plain local delete (entity links cascade). An absent or
/// malformed stored value reads as ``ChangelogRetentionPolicy/maximum``, so
/// corruption never causes a purge.
public enum AuditRetention {
  /// The stored policy, or `maximum` when none is stored or it is malformed.
  public static func policy(_ db: Database) -> ChangelogRetentionPolicy {
    let raw = try? String.fetchOne(
      db, sql: "SELECT value FROM device_state WHERE key = ?",
      arguments: [PreferenceKeys.prefAiChangelogRetentionPolicy])
    return ChangelogRetentionPolicy.parse(raw ?? nil)
  }

  /// Store `policy`. Storing `maximum` removes the row, since an absent row
  /// already reads as `maximum`.
  public static func setPolicy(_ db: Database, _ policy: ChangelogRetentionPolicy) throws {
    if policy == .maximum {
      try db.execute(
        sql: "DELETE FROM device_state WHERE key = ?",
        arguments: [PreferenceKeys.prefAiChangelogRetentionPolicy])
    } else {
      try db.execute(
        sql: """
          INSERT INTO device_state (key, value) VALUES (?, ?)
          ON CONFLICT(key) DO UPDATE SET value = excluded.value
          """,
        arguments: [PreferenceKeys.prefAiChangelogRetentionPolicy, policy.wireValue])
    }
  }

  /// Whether a new audit row may be recorded: false only under `off`.
  public static func recordsAudit(_ db: Database) -> Bool {
    policy(db) != .off
  }

  /// Apply the stored policy, then keep at most
  /// ``SyncNaming/auditMaxEntriesSafeguard`` rows (the newest). Returns how many
  /// rows were removed.
  ///
  /// `off` removes every row; `days(N)` removes rows strictly older than `N`
  /// days before now; `maximum` applies only the row cap.
  @discardableResult
  public static func gcChangelog(_ db: Database) throws -> UInt64 {
    var removed = 0
    switch policy(db) {
    case .off:
      try db.execute(sql: "DELETE FROM ai_changelog")
      removed += db.changesCount
    case .days(let days):
      try db.execute(
        sql: """
          DELETE FROM ai_changelog
          WHERE timestamp < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?)
          """,
        arguments: ["-\(days) days"])
      removed += db.changesCount
    case .maximum:
      break
    }
    try db.execute(
      sql: """
        DELETE FROM ai_changelog WHERE id IN (
          SELECT id FROM ai_changelog
          ORDER BY timestamp DESC, id DESC
          LIMIT -1 OFFSET ?
        )
        """,
      arguments: [Int(SyncNaming.auditMaxEntriesSafeguard)])
    removed += db.changesCount
    return UInt64(removed)
  }
}

extension ChangelogRetentionPolicy {
  /// The stored policy (``AuditRetention/policy(_:)``). Safe to call inside a
  /// mutation transaction.
  public static func read(_ db: Database) -> ChangelogRetentionPolicy {
    AuditRetention.policy(db)
  }
}
