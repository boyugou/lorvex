/// Pure helpers for canonical SQLite schema semantics shared by store and sync.
public enum StorageSchema {
  /// Maximum allowed byte size for a sync envelope payload — both the
  /// canonicalized JSON over the wire and the field-level `raw_payload_json`
  /// rows that land in `sync_payload_shadow` / `sync_pending_inbox`. 256 KiB is
  /// well above legitimate task content plus metadata while staying far below
  /// DoS territory.
  public static let maxPayloadBytes: Int = 256 * 1024

  /// SQLite INTEGER columns whose values are semantically JSON booleans on
  /// external payload surfaces (sync envelopes, export archives).
  public static let sqliteBoolColumns: [(table: String, column: String)] = [
    ("habits", "archived"),
    ("calendar_events", "all_day"),
    ("habit_reminder_policies", "enabled"),
  ]

  public static func isSqliteBoolColumn(table: String, column: String) -> Bool {
    sqliteBoolColumns.contains { $0.table == table && $0.column == column }
  }

  /// Device-local routing columns excluded from generic sync/export payloads.
  /// Audit account identity must never cross the wire.
  public static func isDeviceLocalColumn(table: String, column: String) -> Bool {
    table == "ai_changelog" && column == "retention_account_identifier"
  }
}
