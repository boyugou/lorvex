import GRDB
import LorvexStore
import LorvexSync

extension SwiftLorvexCoreService {
  /// Turn a relational-root physical deletion into durable complete-inventory
  /// debt only after the page cursor has committed. Starting earlier would cancel
  /// the traversal whose page is still being applied and roll back the exact
  /// deletion observation. Existing outbox rows remain active so the snapshot
  /// preserves unrelated local intent; only the exact `remoteAuthoritative`
  /// future-record fence was discarded by the reconciliation above.
  static func beginInventorySnapshotAfterPhysicalDeletion(
    _ db: Database, boundary: CloudTraversalBoundary
  ) throws {
    let traversal = try CloudTraversalWitness.state(
      db, accountIdentifier: boundary.accountIdentifier,
      zoneIdentifier: boundary.zoneIdentifier)
    if let progress = traversal.progress {
      try CloudTraversalWitness.cancel(
        db, boundary: progress.boundary,
        traversalIdentifier: progress.traversalIdentifier)
    }
    let databaseInstanceId = try SyncCheckpoints.getOrCreateDatabaseInstanceId(db)
    let session = try AuthoritativeSnapshot.begin(
      db, boundary: boundary, databaseInstanceId: databaseInstanceId,
      preserveExistingLocalIntents: true)
    _ = try CloudTraversalWitness.begin(
      db, boundary: boundary, traversalIdentifier: session.sessionToken,
      start: .baseline)
    ErrorLog.appendBestEffort(
      db, source: "sync.cloudkit.physical_delete_inventory_required",
      message:
        "deferred relational-root physical deletion until a complete CloudKit inventory",
      details: "account=\(boundary.accountIdentifier), zone=\(boundary.zoneIdentifier)",
      level: "warn")
  }
}
