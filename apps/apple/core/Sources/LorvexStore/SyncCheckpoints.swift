import Foundation
import GRDB
import LorvexDomain

/// Typed `sync_checkpoints` accessors. `sync_checkpoints` is a local-only
/// key-value table storing both per-device sync runtime state (`device_id`,
/// last error, last success, reseed flags) and the per-database instance
/// identity (`db_instance_id`).
public enum SyncCheckpoints {
  /// The per-install device identity. Seeded by ``getOrCreateDeviceId(_:)`` and
  /// stable across every ordinary reopen; HLC suffixes are derived from it. It is
  /// rewritten only by the controlled install-identity reconciliation on the open
  /// path when it detects a restored/cloned database (the in-DB id no longer
  /// matches the backup-excluded install marker), which rotates to a fresh id and
  /// records the retired one so the HLC clock stays self-monotonic.
  public static let keyDeviceId = "device_id"

  /// The stable, per-physical-database instance identity. Seeded by
  /// ``getOrCreateDatabaseInstanceId(_:)`` when a database is first used for
  /// sync and stable across ordinary reopens. A freshly created replacement
  /// database mints a distinct value; install-identity reconciliation also
  /// rotates it when a restored/cloned managed database is detected, so the
  /// clone can never resume the source install's CloudKit generation lease.
  /// Cloud traversal progress and its change token live in this same SQLite
  /// file and are bound to this identity. A new database therefore starts with
  /// no inherited cursor, while a restored/cloned database rotates its identity
  /// before it can claim generation or traversal authority.
  public static let keyDatabaseInstanceId = "db_instance_id"

  /// Account-scoped generation enrollment belongs at the storage layer because
  /// generation publication records it in the same SQLite savepoint as staging
  /// finalization. Keeping the key factory here lets that atomic transition use
  /// the canonical key without making LorvexSync depend on LorvexRuntime.
  public static func keyEnrolledZoneEpoch(accountIdentifier: String) -> String {
    "enrolled_zone_epoch.\(accountIdentifier)"
  }

  /// Read a checkpoint value. Returns `nil` for missing keys.
  public static func get(_ db: Database, key: String) throws -> String? {
    try String.fetchOne(
      db, sql: "SELECT value FROM sync_checkpoints WHERE key = ?", arguments: [key])
  }

  /// Upsert a checkpoint value (atomic insert-or-update).
  public static func set(_ db: Database, key: String, value: String) throws {
    try db.execute(
      sql: """
        INSERT INTO sync_checkpoints (key, value) VALUES (?, ?) \
        ON CONFLICT(key) DO UPDATE SET value = excluded.value
        """,
      arguments: [key, value])
  }

  /// Set only if the key is currently absent (atomic claim). Returns `true`
  /// when newly inserted, `false` when the key already existed.
  @discardableResult
  public static func setIfAbsent(_ db: Database, key: String, value: String) throws -> Bool {
    try db.execute(
      sql: "INSERT OR IGNORE INTO sync_checkpoints (key, value) VALUES (?, ?)",
      arguments: [key, value])
    return db.changesCount > 0
  }

  /// Read-or-generate-and-persist the stable device id from
  /// `sync_checkpoints[device_id]`: a single `INSERT OR IGNORE` claim followed
  /// by a readback so a concurrent writer's win is observed rather than
  /// surfaced as an error.
  public static func getOrCreateDeviceId(
    _ db: Database, generate: () -> String = { EntityID.newEntityIDString() }
  ) throws -> String {
    if let existing = try get(db, key: keyDeviceId) {
      return existing
    }
    let generated = generate()
    if try setIfAbsent(db, key: keyDeviceId, value: generated) {
      return generated
    }
    if let surviving = try get(db, key: keyDeviceId) {
      return surviving
    }
    throw DeviceIdentityError.unavailable
  }

  /// Read-or-generate-and-persist the per-database instance id from
  /// `sync_checkpoints[db_instance_id]`: a single `INSERT OR IGNORE` claim
  /// followed by a readback, mirroring ``getOrCreateDeviceId(_:)``. Stable
  /// across every open of the same physical database; a fresh database (created
  /// by a replacement path) mints a new value.
  public static func getOrCreateDatabaseInstanceId(
    _ db: Database, generate: () -> String = { UUID().uuidString }
  ) throws -> String {
    if let existing = try get(db, key: keyDatabaseInstanceId) {
      return existing
    }
    let generated = generate()
    if try setIfAbsent(db, key: keyDatabaseInstanceId, value: generated) {
      return generated
    }
    if let surviving = try get(db, key: keyDatabaseInstanceId) {
      return surviving
    }
    throw DeviceIdentityError.unavailable
  }
}
