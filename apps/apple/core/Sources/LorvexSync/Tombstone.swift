import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Tombstone operations — create, query, and garbage-collect delete markers.
///
/// The `sync_tombstones` table records that an entity has been deleted. The sync
/// pipeline uses it to prevent re-applying an upsert for a deleted entity
/// unless the upsert is strictly newer. Permanent identity aliases live in
/// `sync_entity_redirects`; delete state and redirect state never share a row.
///
/// Tombstones are kept indefinitely. Nothing proves that every device has seen
/// a delete, and a device that has not could otherwise re-upload the entity.
///
/// Static methods take a GRDB `Database`; HLC versions and timestamps are
/// supplied by the caller. Best-effort `error_logs` breadcrumbs are not written
/// here.
public enum Tombstone {

  /// A tombstone record for a deleted entity.
  public struct Record: Sendable, Equatable {
    /// Canonical entity type name.
    public var entityType: String
    /// Stable entity identity (UUIDv7 or natural key).
    public var entityId: String
    /// HLC version of the delete operation.
    public var version: String
    /// RFC 3339 timestamp of the delete.
    public var deletedAt: String
  }

  // MARK: - Read

  /// Look up a tombstone for an entity. Returns `nil` if not tombstoned.
  public static func getTombstone(
    _ db: Database, entityType: String, entityId: String
  ) throws -> Record? {
    try Row.fetchOne(
      db,
      sql: """
        SELECT entity_type, entity_id, version, deleted_at
        FROM sync_tombstones
        WHERE entity_type = ? AND entity_id = ?
        """,
      arguments: [entityType, entityId]
    ).map {
      Record(
        entityType: $0["entity_type"],
        entityId: $0["entity_id"],
        version: $0["version"],
        deletedAt: $0["deleted_at"])
    }
  }

  /// Lightweight existence check that avoids deserializing the full row.
  public static func isTombstoned(
    _ db: Database, entityType: String, entityId: String
  ) throws -> Bool {
    let count = try Int.fetchOne(
      db,
      sql: "SELECT COUNT(*) FROM sync_tombstones WHERE entity_type = ? AND entity_id = ?",
      arguments: [entityType, entityId]) ?? 0
    return count > 0
  }

  // MARK: - Write

  /// Create or update a tombstone with version monotonicity (newer wins, older
  /// silently ignored). Compares both sides via typed `Hlc` parse; falls back to
  /// byte-compare only when both fail to parse. A canonical incoming overwrites a
  /// tainted existing; a tainted incoming never overwrites a canonical existing.
  /// On a successful write the deleted entity's payload shadow is removed. When
  /// the version gate rejects the write, the shadow is left untouched.
  public static func createTombstone(
    _ db: Database,
    entityType: String,
    entityId: String,
    version: String,
    deletedAt: String
  ) throws {
    let existingVersion = try String.fetchOne(
      db,
      sql: "SELECT version FROM sync_tombstones WHERE entity_type = ? AND entity_id = ? LIMIT 1",
      arguments: [entityType, entityId])

    // Monotonicity gate: a newer version overwrites, an older/tainted-loser is
    // silently ignored. The canonical-preferring tiebreak (typed `Hlc` when both
    // parse; the canonical side when exactly one does; a raw UTF-8 byte compare
    // when neither does) lives in ``canonicalPreferringDominates(incoming:existing:)``.
    let shouldWrite =
      existingVersion.map { canonicalPreferringDominates(incoming: version, existing: $0) } ?? true

    guard shouldWrite else { return }

    if existingVersion != nil {
      try db.execute(
        sql: """
          UPDATE sync_tombstones SET
              version = ?,
              deleted_at = ?
           WHERE entity_type = ? AND entity_id = ?
          """,
        arguments: [version, deletedAt, entityType, entityId])
    } else {
      try db.execute(
        sql: """
          INSERT INTO sync_tombstones
              (entity_type, entity_id, version, deleted_at)
           VALUES (?, ?, ?, ?)
          """,
        arguments: [entityType, entityId, version, deletedAt])
    }

    // Reconcile the payload shadow on a successful write (reached only when
    // `shouldWrite` accepted the version, so the row was inserted or updated).
    try PayloadShadow.removeShadow(db, entityType: entityType, entityID: entityId)
  }

  /// Remove a specific tombstone by `(entity_type, entity_id)`. Returns `true`
  /// when a row was deleted.
  @discardableResult
  public static func removeTombstone(
    _ db: Database, entityType: String, entityId: String
  ) throws -> Bool {
    try db.execute(
      sql: "DELETE FROM sync_tombstones WHERE entity_type = ? AND entity_id = ?",
      arguments: [entityType, entityId])
    return db.changesCount > 0
  }
}
