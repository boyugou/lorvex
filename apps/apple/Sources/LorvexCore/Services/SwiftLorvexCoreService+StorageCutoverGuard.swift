import GRDB
import LorvexStore

/// Storage-cutover guard for the write funnels: a commit-time identity check
/// that closes the factory-reset cross-process race.
///
/// Both mutation funnels (`withWrite`, `applyInbound`) resolve the device
/// identity in `writeState()` and then re-resolve the store handle in a
/// separate `store()` call. A cross-process factory reset landing between those
/// two steps deletes and recreates the managed database, so the second step can
/// reopen the *fresh* database while the write is still stamped with the
/// *erased* database's device identity — leaving the fresh store with a phantom
/// identity that was never persisted to its own `sync_checkpoints.device_id`.
///
/// The fix verifies, inside the committing transaction, that the database being
/// committed into is the one whose identity was resolved, and retries the whole
/// operation (re-resolving identity) when it is not. See
/// ``SwiftLorvexCoreService/assertCommittingDatabaseIdentity(_:expected:)`` and
/// ``SwiftLorvexCoreService/withStorageCutoverRetry(_:)``.

/// Thrown from a write transaction when the database it is committing into is
/// not the one whose device identity `writeState()` resolved — a cross-process
/// factory reset replaced the managed store between identity resolution and this
/// transaction. Signals the write funnel to re-resolve identity and retry.
struct StorageCutoverDuringWrite: Error {
  /// The device id `writeState()` resolved (against the pre-reset database).
  let resolvedDeviceId: String
  /// The committing database's own `sync_checkpoints.device_id` — `nil` when the
  /// fresh post-reset database has not yet had an identity minted into it.
  let committingDeviceId: String?
}

extension SwiftLorvexCoreService {
  /// Fail the transaction unless the committing database's own
  /// `sync_checkpoints.device_id` matches the identity `writeState()` resolved.
  ///
  /// Read inside the caller's transaction so the check is bound (by SQLite
  /// isolation, on the connection's fixed inode) to the exact database the write
  /// lands in: if a cross-process factory reset redirected the store handle onto
  /// a fresh database after identity resolution, the committing `device_id`
  /// differs (or is absent) and the write aborts *before* any HLC is minted or
  /// any row is mutated.
  ///
  /// Gated to managed storage only — an in-memory / dev-injected store is never
  /// factory-reset, and skipping the check there also avoids a spurious abort on
  /// the very first write, before any device id has been minted.
  func assertCommittingDatabaseIdentity(_ db: Database, expected deviceId: String) throws {
    guard openedManagedDatabasePathSnapshot() != nil else { return }
    let committed = try SyncCheckpoints.get(db, key: SyncCheckpoints.keyDeviceId)
    guard committed == deviceId else {
      throw StorageCutoverDuringWrite(resolvedDeviceId: deviceId, committingDeviceId: committed)
    }
  }

  /// Run `attempt`, retrying the whole operation when a mid-write factory reset
  /// is detected (``StorageCutoverDuringWrite``). Identity is re-resolved on each
  /// attempt because `attempt` re-runs `writeState()`, which observes the bumped
  /// storage epoch and resolves against the fresh database. Bounded by
  /// ``maxStorageCutoverRetries`` so a genuine repeated reset or a persistent
  /// anomaly surfaces the sentinel rather than spinning forever.
  func withStorageCutoverRetry<T>(_ attempt: () throws -> T) throws -> T {
    var remaining = Self.maxStorageCutoverRetries
    while true {
      do {
        return try attempt()
      } catch let error as StorageCutoverDuringWrite {
        guard remaining > 0 else { throw error }
        remaining -= 1
      }
    }
  }

  /// Whole-operation retries granted to ``withStorageCutoverRetry(_:)`` after a
  /// detected cross-process reset. Two is ample: a single reset is absorbed by
  /// the first retry, and more than two back-to-back resets across one write is
  /// an anomaly that should surface, not be masked.
  static let maxStorageCutoverRetries = 2
}
