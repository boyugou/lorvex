import GRDB
import LorvexDomain
import enum LorvexStore.SyncCheckpoints

/// `sync_checkpoints` runtime surface.
///
/// `sync_checkpoints` is a local-only key-value table storing per-device sync
/// runtime state. The CRUD primitives (`get`/`set`/`setIfAbsent`/`getOrCreateDeviceId`)
/// are authoritatively implemented in `LorvexStore.SyncCheckpoints`; the runtime
/// re-exports that enum and extends it with the remaining well-known keys and
/// the typed `clear` accessor. Reimplementing the upsert
/// SQL here would duplicate a path the store already owns and tests.
public typealias SyncCheckpoints = LorvexStore.SyncCheckpoints

extension SyncCheckpoints {
  /// Comma-separated device ids this database has authored under before an
  /// install-identity rotation retired them (a restored/cloned DB rotating to a
  /// fresh `device_id`). The HLC clock seeds its monotonicity scan across the
  /// current suffix AND every retired suffix, so a rotated device still observes
  /// its own pre-rotation history and never mints an HLC below it (which would
  /// lose the device's own edits under LWW). Absent until the first rotation.
  public static var keyRetiredDeviceIds: String { "retired_device_ids" }

  /// Wall-clock timestamp of the last *successful* sync round-trip.
  public static var keyLastSuccessAt: String { "last_success_at" }

  /// Most recent sync error message, with a `[timestamp]` prefix. Deleted on
  /// the next successful sync so the UI surfaces a cleared error rather than a
  /// stale one.
  public static var keyLastError: String { "last_error" }

  /// Set to `"true"` when the horizon GC hard-deleted an expired pending-inbox
  /// row, meaning this device is more than the full-resync horizon behind and
  /// lost records it can only recover by reseeding from a full resync. Written by
  /// the retention sweep (`SyncRetention`) alongside a `reseed_required`
  /// conflict-log row. The sync transport observes it at cycle start and runs
  /// the recovery (atomic SQLite traversal reset + full-resync backfill +
  /// nil-token baseline); a COMPLETE backfill pass clears it. The host surfaces
  /// it while set.
  public static var keyReseedRequired: String { SyncNaming.reseedRequiredCheckpointKey }

  /// Delete a checkpoint key. Returns `true` if a row was deleted, `false` if
  /// the key was already absent.
  @discardableResult
  public static func clear(_ db: Database, key: String) throws -> Bool {
    try db.execute(sql: "DELETE FROM sync_checkpoints WHERE key = ?1", arguments: [key])
    return db.changesCount > 0
  }
}
