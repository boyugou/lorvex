import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore

extension SwiftLorvexCoreService {
  /// Resolve this open's device id, reconciling the in-database `device_id`
  /// against the backup-excluded install marker (``ManagedInstallIdentity``) so a
  /// restored or cloned database rotates to a fresh identity instead of sharing
  /// the origin install's — which would collapse two live devices onto one HLC
  /// clock suffix and silently drop LWW writes. Returns the resolved id plus any
  /// retired ids the HLC clock must also seed across.
  ///
  /// Only the managed store carries a marker; an in-memory / dev-override store
  /// (`managedPath == nil`) falls back to the plain get-or-create with no
  /// retirement, exactly as before.
  ///
  /// Rotation keys off genuine marker ABSENCE (a restore does not carry the
  /// backup-excluded marker forward), so the marker read is a tri-state
  /// (``ManagedInstallIdentity/MarkerRead``): a marker that exists but could not
  /// be read this open (transient I/O, a permissions blip, corrupt bytes) is
  /// `unreadable`, NOT absent, and never rotates a healthy install's identity — a
  /// transient read misclassified as absent would spuriously churn the device id,
  /// force a reseed, and re-pull the zone.
  ///
  /// | in-DB id | marker      | meaning                                  | action        |
  /// |----------|-------------|------------------------------------------|---------------|
  /// | nil      | absent      | first-ever open                          | mint + marker |
  /// | nil      | unreadable  | identity-less DB, marker unreadable      | mint + marker |
  /// | nil      | M           | fresh DB, same install (torn reset)      | adopt M       |
  /// | X        | X           | ordinary reopen (incl. MCP helper)       | no-op         |
  /// | X        | absent      | restored/cloned DB (marker not restored) | rotate        |
  /// | X        | Z≠X         | DB swapped under this install            | rotate        |
  /// | X        | unreadable  | transient read failure — keep identity   | no-op         |
  func resolveInstallIdentity(managedPath: String?) throws
    -> (deviceId: String, retiredDeviceIds: [String])
  {
    guard let managedPath else {
      let id = try write { db in try DeviceIdentity.getOrCreateDeviceId(db) }
      return (id, [])
    }
    // Hold the EXCLUSIVE cross-process mint lock across the whole read-marker →
    // mint/rotate → write-marker sequence. The marker read and write bracket the
    // DB write transaction, so the transaction's SQLite serialization alone does
    // not make the decision atomic across processes: two first-opens (app + MCP
    // helper over one managed path) could both read the absent marker, and the
    // loser — seeing the winner's now-stamped in-DB id against a marker it read
    // as absent — would spuriously rotate, churning the device identity. Under
    // the lock the loser blocks until the winner publishes the marker, then reads
    // it and takes the ordinary-reopen no-op path below.
    return try ManagedInstallIdentity.withMintLock(forDatabase: managedPath) {
      // Lock order is deliberately mint lock OUTERMOST, shared cutover lease
      // INNERMOST. Keep the lease through marker publication: if reset could
      // delete the freshly-stamped DB after the transaction but before this
      // write, the old identity marker would be republished beside the erased
      // generation and adopted by its next first write.
      try withStoreCutoverLease { store in
        let marker = ManagedInstallIdentity.readMarkerState(forDatabase: managedPath)
        let (deviceId, retired, markerToWrite) = try store.writer.write {
          db -> (String, [String], String?) in
          let dbId = try SyncCheckpoints.get(db, key: SyncCheckpoints.keyDeviceId)
          let resolved: String
          var markerToWrite: String?
          if let dbId {
            switch marker {
            case .present(let markerId) where markerId == dbId:
              // Ordinary reopen — including a second process (the MCP helper) sharing
              // this managed path, which reads the same marker. No rotation.
              resolved = dbId
            case .present, .absent:
              // The marker holds a DIFFERENT id (the DB was swapped under this install)
              // or is genuinely absent (a restore dropped the backup-excluded file).
              // Either way the database arrived from elsewhere — rotate to a fresh
              // identity so two installs never share one.
              resolved = try Self.rotateInstallIdentity(db, oldDeviceId: dbId)
              markerToWrite = resolved
            case .unreadable:
              // The marker exists but could not be read this open (a transient I/O or
              // permissions failure, or corrupt bytes). We cannot confirm it differs
              // from the in-DB id, and a genuine restore would have DROPPED the
              // backup-excluded marker rather than left an unreadable one — so keep the
              // identity rather than rotate on incomplete information. Leave the marker
              // untouched (do not clobber a possibly-valid one).
              resolved = dbId
            }
          } else {
            switch marker {
            case .present(let markerId):
              // A fresh (identity-less) DB under an install that already has a marker (a
              // torn factory reset that recreated the DB but not the marker): adopt the
              // marker's id rather than mint a fresh one.
              try SyncCheckpoints.set(db, key: SyncCheckpoints.keyDeviceId, value: markerId)
              resolved = markerId
            case .absent, .unreadable:
              // First-ever open, or a fresh/identity-less DB whose marker cannot be read.
              // The DB carries no identity to preserve, so mint one and (re)record the
              // marker; an unreadable marker here is safe to overwrite.
              resolved = try DeviceIdentity.getOrCreateDeviceId(db)
              markerToWrite = resolved
            }
          }
          return (resolved, Self.readRetiredDeviceIds(db), markerToWrite)
        }
        if let markerToWrite {
          try ManagedInstallIdentity.write(forDatabase: managedPath, deviceId: markerToWrite)
        }
        return (deviceId, retired)
      }
    }
  }

  /// Rotate to a fresh `device_id`, retiring the old one so the HLC clock still
  /// seeds past this device's pre-rotation history (authored under the old
  /// suffix), rotating the per-database instance id, and forcing a reseed so the
  /// rotated device re-publishes its outbox under the new id and re-pulls the
  /// zone. Runs inside the caller's write transaction.
  static func rotateInstallIdentity(_ db: Database, oldDeviceId: String) throws -> String {
    let newId = EntityID.newEntityIDString()
    var retired = readRetiredDeviceIds(db)
    if !retired.contains(oldDeviceId) { retired.append(oldDeviceId) }
    try SyncCheckpoints.set(
      db, key: SyncCheckpoints.keyRetiredDeviceIds, value: retired.joined(separator: ","))
    try SyncCheckpoints.set(db, key: SyncCheckpoints.keyDeviceId, value: newId)
    try SyncCheckpoints.set(
      db, key: SyncCheckpoints.keyDatabaseInstanceId, value: UUID().uuidString)
    try SyncCheckpoints.set(db, key: SyncCheckpoints.keyReseedRequired, value: "true")
    return newId
  }

  /// The retired device ids recorded for this database, in retirement order.
  static func readRetiredDeviceIds(_ db: Database) -> [String] {
    let raw = (try? SyncCheckpoints.get(db, key: SyncCheckpoints.keyRetiredDeviceIds)) ?? nil
    guard let value = raw, !value.isEmpty else { return [] }
    return value.split(separator: ",").map(String.init)
  }
}
