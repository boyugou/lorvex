import GRDB

extension PendingInboxDrain {
  /// Number of exhausted inbound envelope identities still awaiting a valid
  /// same-slot replacement or an authoritative snapshot. These rows are
  /// durable unmaterialized inbound debt even after the retrying inbox row has
  /// been removed.
  public static func quarantinedRecordCount(_ db: Database) throws -> Int {
    try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_quarantine_blocklist") ?? 0
  }

  /// Whether `(entity_type, entity_id, version)` is on the poison-envelope
  /// blocklist.
  static func isQuarantined(
    _ db: Database, entityType: String, entityID: String, version: String
  ) throws -> Bool {
    try Int64.fetchOne(
      db,
      sql: """
        SELECT 1 FROM sync_quarantine_blocklist
        WHERE entity_type = ? AND entity_id = ? AND version = ?
        LIMIT 1
        """,
      arguments: [entityType, entityID, version]) != nil
  }

  /// Record `(entity_type, entity_id, version)` on the poison-envelope
  /// blocklist. First write wins (`ON CONFLICT DO NOTHING`) so the original
  /// `quarantined_at` is preserved under a redelivery storm. The per-cause
  /// diagnostic string lives in the sibling `sync_conflict_log` row each
  /// caller writes alongside this blocklist entry.
  static func recordQuarantine(
    _ db: Database, entityType: String, entityID: String, version: String
  ) throws {
    try db.execute(
      sql: """
        INSERT INTO sync_quarantine_blocklist
            (entity_type, entity_id, version, quarantined_at)
         VALUES (?, ?, ?, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
         ON CONFLICT(entity_type, entity_id, version) DO NOTHING
        """,
      arguments: [entityType, entityID, version])
  }

  /// A valid terminal envelope for the same CloudKit record slot proves every
  /// quarantined predecessor at or below its HLC is obsolete. Keep any strictly
  /// newer quarantined version: an out-of-order stale envelope must not erase
  /// evidence for state it does not dominate.
  public static func clearQuarantineThroughResolvedEnvelope(
    _ db: Database, entityType: String, entityID: String, version: String
  ) throws {
    try db.execute(
      sql: """
        DELETE FROM sync_quarantine_blocklist
        WHERE entity_type = ? AND entity_id = ? AND version <= ?
        """,
      arguments: [entityType, entityID, version])
  }
}
