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
    /// Earliest CloudKit server-assigned modification time that confirmed this
    /// exact delete version. `nil` is deliberately conservative and never
    /// authorizes compaction.
    public var cloudConfirmedAt: String?
  }

  /// Server-authenticated receipt for one exact tombstone identity/version.
  /// The timestamp must be CloudKit's `CKRecord.modificationDate`, canonicalized
  /// at the transport boundary; caller wall clocks are never accepted here.
  public struct CloudConfirmation: Sendable, Equatable, Hashable {
    public var entityType: String
    public var entityId: String
    public var version: String
    public var confirmedAt: String

    public init(
      entityType: String, entityId: String, version: String, confirmedAt: String
    ) {
      self.entityType = entityType
      self.entityId = entityId
      self.version = version
      self.confirmedAt = confirmedAt
    }
  }

  // MARK: - Read

  /// Look up a tombstone for an entity. Returns `nil` if not tombstoned.
  public static func getTombstone(
    _ db: Database, entityType: String, entityId: String
  ) throws -> Record? {
    try Row.fetchOne(
      db,
      sql: """
        SELECT entity_type, entity_id, version, deleted_at, cloud_confirmed_at
        FROM sync_tombstones
        WHERE entity_type = ? AND entity_id = ?
        """,
      arguments: [entityType, entityId]
    ).map {
      Record(
        entityType: $0["entity_type"],
        entityId: $0["entity_id"],
        version: $0["version"],
        deletedAt: $0["deleted_at"],
        cloudConfirmedAt: $0["cloud_confirmed_at"])
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
              deleted_at = ?,
              cloud_confirmed_at = NULL
           WHERE entity_type = ? AND entity_id = ?
          """,
        arguments: [version, deletedAt, entityType, entityId])
    } else {
      try db.execute(
        sql: """
          INSERT INTO sync_tombstones
              (entity_type, entity_id, version, deleted_at, cloud_confirmed_at)
           VALUES (?, ?, ?, ?, NULL)
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

  /// Record CloudKit confirmation for an exact tombstone. A stale receipt for a
  /// coalesced/newer delete updates nothing. Repeated receipts keep the earliest
  /// server time, which is the strongest evidence for the recovery horizon.
  @discardableResult
  public static func confirmCloudPresence(
    _ db: Database, confirmation: CloudConfirmation
  ) throws -> Bool {
    guard let timestamp = SyncTimestamp.parse(confirmation.confirmedAt),
      timestamp.asString == confirmation.confirmedAt,
      let version = try? Hlc.parseCanonical(confirmation.version),
      version.description == confirmation.version
    else { throw TombstoneConfirmationError.invalidReceipt }
    try db.execute(
      sql: """
        UPDATE sync_tombstones
        SET cloud_confirmed_at = CASE
          WHEN cloud_confirmed_at IS NULL OR ? < cloud_confirmed_at THEN ?
          ELSE cloud_confirmed_at
        END
        WHERE entity_type = ? AND entity_id = ? AND version = ?
        """,
      arguments: [
        confirmation.confirmedAt, confirmation.confirmedAt,
        confirmation.entityType, confirmation.entityId, confirmation.version,
      ])
    return db.changesCount == 1
  }

  /// Exact trusted compaction used only after a ready-generation baseline has
  /// completed. `cutoff` must derive from a server-assigned control-record time.
  /// Unconfirmed, within-window, and permanent-redirect-target tombstones are
  /// always retained.
  @discardableResult
  public static func compactCloudConfirmed(
    _ db: Database, through cutoff: String
  ) throws -> UInt64 {
    guard let timestamp = SyncTimestamp.parse(cutoff), timestamp.asString == cutoff else {
      throw TombstoneConfirmationError.invalidCutoff
    }
    // Remove the exact stale delete intent first. Otherwise local compaction
    // followed by the ordinary ready-zone drain would immediately re-create the
    // remote tombstone this generation intentionally omitted.
    try db.execute(
      sql: """
        DELETE FROM sync_outbox
        WHERE operation = 'delete'
          AND EXISTS (
            SELECT 1 FROM sync_tombstones AS tombstone
            WHERE tombstone.entity_type = sync_outbox.entity_type
              AND tombstone.entity_id = sync_outbox.entity_id
              AND tombstone.version = sync_outbox.version
              AND tombstone.cloud_confirmed_at IS NOT NULL
              AND tombstone.cloud_confirmed_at <= ?
              AND NOT (\(TombstoneCompactionPolicy.isPermanentRedirectTargetSQL))
          )
        """,
      arguments: [cutoff])
    try db.execute(
      sql: """
        DELETE FROM sync_tombstones AS tombstone
        WHERE tombstone.cloud_confirmed_at IS NOT NULL
          AND tombstone.cloud_confirmed_at <= ?
          AND NOT (\(TombstoneCompactionPolicy.isPermanentRedirectTargetSQL))
        """,
      arguments: [cutoff])
    return UInt64(db.changesCount)
  }

  /// Advance the account's trusted CloudKit clock from a server receipt. The
  /// account/database binding is part of the update predicate so a stale
  /// callback after account adoption cannot seed a different account's clock.
  public static func observeTrustedServerTime(
    _ db: Database, accountIdentifier: String, serverTime: String
  ) throws {
    guard let timestamp = SyncTimestamp.parse(serverTime), timestamp.asString == serverTime else {
      throw TombstoneConfirmationError.invalidReceipt
    }
    try db.execute(
      sql: """
        UPDATE sync_cloudkit_account_binding
        SET trusted_server_time = CASE
          WHEN trusted_server_time IS NULL OR trusted_server_time < ? THEN ?
          ELSE trusted_server_time
        END
        WHERE singleton = 1 AND account_identifier = ?
        """,
      arguments: [serverTime, serverTime, accountIdentifier])
    guard db.changesCount == 1 else {
      throw TombstoneConfirmationError.accountBoundaryMismatch
    }
  }

  /// Return a server-clock-derived cutoff only when at least one exact
  /// CloudKit-confirmed tombstone is eligible and is not permanent-alias
  /// closure state. This is the active ready-zone rotation trigger; no
  /// collectable activity means the ledger does not need a rotation.
  public static func trustedCompactionCutoff(
    _ db: Database, accountIdentifier: String, recoveryDays: UInt32
  ) throws -> String? {
    guard let raw = try String.fetchOne(
      db,
      sql: """
        SELECT trusted_server_time FROM sync_cloudkit_account_binding
        WHERE singleton = 1 AND account_identifier = ?
        """,
      arguments: [accountIdentifier]),
      let serverTime = SyncTimestamp.parse(raw), serverTime.asString == raw
    else { return nil }
    let cutoff = SyncTimestampFormat.formatSyncTimestamp(
      serverTime.date.addingTimeInterval(-Double(recoveryDays) * 24 * 60 * 60))
    let eligible = try Int.fetchOne(
      db,
      sql: """
        SELECT 1 FROM sync_tombstones AS tombstone
        WHERE tombstone.cloud_confirmed_at IS NOT NULL
          AND tombstone.cloud_confirmed_at <= ?
          AND NOT (\(TombstoneCompactionPolicy.isPermanentRedirectTargetSQL))
        LIMIT 1
        """,
      arguments: [cutoff]) == 1
    return eligible ? cutoff : nil
  }

  /// Whether this physical database completed a traversal whose exact
  /// CloudKit-owned witness time is strictly later than a generation's
  /// published compaction cutoff. Equality cannot prove ordering between two
  /// events represented in the same millisecond. Merely observing a server
  /// receipt is insufficient: the terminal
  /// watermark advances only in `CloudTraversalWitness.commitPage` after every
  /// page effect and cursor transition commit atomically.
  public static func trustedTerminalServerTimeCovers(
    _ db: Database, accountIdentifier: String, cutoff: String
  ) throws -> Bool {
    guard let timestamp = SyncTimestamp.parse(cutoff), timestamp.asString == cutoff else {
      throw TombstoneConfirmationError.invalidCutoff
    }
    guard let raw = try String.fetchOne(
      db,
      sql: """
        SELECT trusted_terminal_server_time FROM sync_cloudkit_account_binding
        WHERE singleton = 1 AND account_identifier = ?
        """,
      arguments: [accountIdentifier]),
      let terminal = SyncTimestamp.parse(raw), terminal.asString == raw
    else { return false }
    return terminal.date > timestamp.date
  }

  // MARK: - GC

  /// Ordinary time-based maintenance remains a no-op. Tombstones are reclaimed
  /// only by trusted CloudKit confirmation through a published generation or a
  /// completed ready-generation baseline; local wall clock is never authority.
  ///
  /// The explicit 365-day recovery contract retains every unconfirmed or recent
  /// delete. A peer older than that contract adopts the current generation as
  /// authoritative before any compacted death marker can matter.
  ///
  /// Returns 0 and deletes nothing; kept as a call site so the retention-sweep
  /// order in ``SyncRetention/runPostApplyGC(_:syncedAt:emit:)`` is unchanged.
  @discardableResult
  public static func gcTombstonesWatermark(_ db: Database) throws -> UInt64 {
    0
  }
}

public enum TombstoneConfirmationError: Error, Sendable, Equatable {
  case invalidReceipt
  case invalidCutoff
  case accountBoundaryMismatch
}
