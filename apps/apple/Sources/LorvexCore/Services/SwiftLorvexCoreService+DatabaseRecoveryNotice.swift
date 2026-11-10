import Foundation
import GRDB
import LorvexStore

/// The notice that an unreadable database was set aside at open: this
/// process's own, and the one the fresh database remembers for whichever
/// process reads it next.
extension SwiftLorvexCoreService {
  /// The open-time quarantine mapped to the host-facing `DatabaseRecoveryNotice`,
  /// or `nil` on a clean open. `nil` until the store has been opened (the first
  /// read/write), since the quarantine is decided at open time.
  public var databaseRecoveryNotice: DatabaseRecoveryNotice? {
    guard let recovery = lastDatabaseRecovery else { return nil }
    return DatabaseRecoveryNotice(backupPath: recovery.backupURL.path, reason: recovery.reason)
  }

  /// `device_state` key under which the fresh database remembers that it
  /// replaced a set-aside one, until the user has seen the notice.
  static let databaseRecoveryNoticeKey = "database_recovery_notice"

  /// Writes the quarantine into the database that replaced the set-aside one.
  /// The process that met the unreadable file may be a helper (the MCP host, a
  /// widget intent) or may end before anyone reads its in-memory notice; the
  /// app would then open an empty database with nothing to explain it.
  /// Best-effort: the in-memory notice still serves this process.
  static func recordDatabaseRecovery(
    _ recovery: LorvexStore.DatabaseRecovery, in store: LorvexStore
  ) {
    let fields = ["backup_path": recovery.backupURL.path, "reason": recovery.reason]
    guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
      let value = String(data: data, encoding: .utf8)
    else { return }
    try? store.writer.write { db in
      try db.execute(
        sql: """
          INSERT INTO device_state (key, value) VALUES (?, ?)
          ON CONFLICT(key) DO UPDATE SET value = excluded.value
          """,
        arguments: [databaseRecoveryNoticeKey, value])
    }
  }

  /// See ``LorvexCoreServicing/pendingDatabaseRecoveryNotice()``: this
  /// process's own quarantine, or the one a fresh database still remembers.
  public func pendingDatabaseRecoveryNotice() async -> DatabaseRecoveryNotice? {
    let stored: String? = try? read { db in
      try String.fetchOne(
        db, sql: "SELECT value FROM device_state WHERE key = ?",
        arguments: [Self.databaseRecoveryNoticeKey])
    }
    // The read above opened the store, so a quarantine it performed is known.
    if let notice = databaseRecoveryNotice { return notice }
    guard let stored, let data = stored.data(using: .utf8),
      let fields = (try? JSONSerialization.jsonObject(with: data)) as? [String: String],
      let backupPath = fields["backup_path"], let reason = fields["reason"]
    else { return nil }
    return DatabaseRecoveryNotice(backupPath: backupPath, reason: reason)
  }

  /// See ``LorvexCoreServicing/acknowledgeDatabaseRecoveryNotice()``.
  public func acknowledgeDatabaseRecoveryNotice() async {
    forgetDatabaseRecovery()
    try? write { db in
      try db.execute(
        sql: "DELETE FROM device_state WHERE key = ?",
        arguments: [Self.databaseRecoveryNoticeKey])
    }
  }
}
