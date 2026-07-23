import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

/// Authoritative CloudKit traversal lifecycle and its durable recovery state.
extension SwiftLorvexCoreService {
  public func authoritativeSnapshotSession() throws -> AuthoritativeSnapshotSession? {
    try read { db in try AuthoritativeSnapshot.activeSession(db) }
  }

  public func beginAuthoritativeSnapshot(boundary: CloudTraversalBoundary) throws
    -> AuthoritativeSnapshotSession
  {
    try withCloudTraversalWrite { db in
      let databaseInstanceId = try SyncCheckpoints.getOrCreateDatabaseInstanceId(db)
      if let existing = try AuthoritativeSnapshot.activeSession(db),
        existing.boundary != boundary || existing.databaseInstanceId != databaseInstanceId
      {
        try CloudTraversalWitness.cancel(
          db, boundary: existing.boundary,
          traversalIdentifier: existing.sessionToken)
      }
      let session = try AuthoritativeSnapshot.begin(
        db, boundary: boundary, databaseInstanceId: databaseInstanceId)
      _ = try CloudTraversalWitness.begin(
        db, boundary: boundary, traversalIdentifier: session.sessionToken,
        start: .baseline)
      return session
    }
  }

  public func restartAuthoritativeSnapshot() throws -> AuthoritativeSnapshotSession {
    try withCloudTraversalWrite { db in
      guard let existing = try AuthoritativeSnapshot.activeSession(db) else {
        throw AuthoritativeSnapshotError.noActiveSession
      }
      try CloudTraversalWitness.cancel(
        db, boundary: existing.boundary,
        traversalIdentifier: existing.sessionToken)
      let databaseInstanceId = try SyncCheckpoints.getOrCreateDatabaseInstanceId(db)
      let session = try AuthoritativeSnapshot.restart(
        db, databaseInstanceId: databaseInstanceId)
      _ = try CloudTraversalWitness.begin(
        db, boundary: session.boundary, traversalIdentifier: session.sessionToken,
        start: .baseline)
      try SyncCheckpoints.clear(db, key: Self.remoteFetchFailureCheckpointKey)
      try SyncCheckpoints.clear(db, key: Self.remoteFetchFailureCountKey)
      return session
    }
  }

  public func markAuthoritativeSnapshotReady(sessionToken: String) throws {
    try withCloudTraversalWrite { db in
      try AuthoritativeSnapshot.markReady(db, sessionToken: sessionToken)
    }
  }

  public func stageAuthoritativeSnapshotPage(
    records: [AuthoritativeSnapshotRemoteRecord], deletedRecordNames: [String],
    sessionToken: String
  ) throws {
    try withCloudTraversalWrite { db in
      try AuthoritativeSnapshot.stagePage(
        db, records: records, deletedRecordNames: deletedRecordNames,
        sessionToken: sessionToken)
    }
  }

  public func finalizeAuthoritativeSnapshot(
    sessionToken: String, accountIdentifier: String, zoneName: String,
    enrolledZoneEpoch: Int?
  ) throws -> AuthoritativeSnapshotReport {
    try withWrite { db, hlc, deviceId in
      guard let session = try AuthoritativeSnapshot.activeSession(db),
        session.sessionToken == sessionToken,
        session.accountIdentifier == accountIdentifier, session.zoneName == zoneName
      else {
        throw AuthoritativeSnapshotError.sessionBoundaryMismatch
      }
      let databaseInstanceId = try SyncCheckpoints.getOrCreateDatabaseInstanceId(db)
      guard session.databaseInstanceId == databaseInstanceId else {
        throw AuthoritativeSnapshotError.databaseInstanceMismatch
      }
      // Core finalization performs the terminal quarantine + owned-fence release
      // in this same transaction after validating the complete staged snapshot.
      let report = try Self.finalizeAuthoritativeSnapshotAndReconcileDerivedState(
        db, service: self, hlc: hlc, deviceId: deviceId,
        sessionToken: sessionToken, databaseInstanceId: databaseInstanceId)
      if let epoch = enrolledZoneEpoch {
        guard epoch >= 0 else { throw ZoneEpochCheckpointStateError.invalidEpoch }
        try SyncCheckpoints.set(
          db, key: SyncCheckpoints.keyEnrolledZoneEpoch(accountIdentifier: accountIdentifier),
          value: String(epoch))
      }
      try SyncCheckpoints.clear(db, key: SyncCheckpoints.keyReseedRequired)
      try SyncCheckpoints.clear(db, key: Self.remoteFetchFailureCheckpointKey)
      try SyncCheckpoints.clear(db, key: Self.remoteFetchFailureCountKey)
      return report
    }
  }

  /// Finish a complete remote-authoritative snapshot, then restore invariants
  /// whose source rows travel as independent CloudKit records. Keep this in the
  /// same SQLite transaction as snapshot replay and cursor publication: record
  /// order must never leave an old-zone reminder behind after a newer product
  /// timezone becomes authoritative.
  static func finalizeAuthoritativeSnapshotAndReconcileDerivedState(
    _ db: Database, service: SwiftLorvexCoreService, hlc: HlcSession,
    deviceId: String, sessionToken: String, databaseInstanceId: String
  ) throws -> AuthoritativeSnapshotReport {
    var report = try AuthoritativeSnapshot.finalize(
      db, registry: Self.inboundRegistry, hlc: hlc, deviceId: deviceId,
      sessionToken: sessionToken, databaseInstanceId: databaseInstanceId)
    let timezoneReminderRepairs = try Self.reconcileTaskReminderTimezoneAnchorsAfterInbound(
      db, service: service, deviceId: deviceId, hlc: hlc)
    if timezoneReminderRepairs > 0 {
      report.changedEntityTypes.insert(.taskReminder)
    }
    return report
  }

  public func cancelAuthoritativeSnapshot() throws {
    try withCloudTraversalWrite { db in
      if let session = try AuthoritativeSnapshot.activeSession(db) {
        try CloudTraversalWitness.cancel(
          db, boundary: session.boundary,
          traversalIdentifier: session.sessionToken)
      }
      try AuthoritativeSnapshot.cancel(db)
    }
  }

  /// The per-physical-database instance id, get-or-created in
  /// `sync_checkpoints[db_instance_id]`. Stable across opens of the same
  /// on-disk database; a replacement database mints a new value, while a
  /// restored/cloned managed database rotates it before CloudKit traversal.
  /// Inbound rows and their successor cursor are committed in this same SQLite
  /// file, so no external token can outlive a replacement database.
  public func databaseInstanceIdentifier() throws -> String? {
    // CloudKit asks for this identity before its first traversal. Route that
    // read through the traversal write funnel so a restored/cloned managed DB
    // reconciles its backup-excluded install marker and rotates BOTH identities
    // before either one can become a generation lease owner. The funnel also
    // closes the factory-reset race with a commit-time database-identity check.
    try withCloudTraversalWrite { db in
      try SyncCheckpoints.getOrCreateDatabaseInstanceId(db)
    }
  }

  public func recordRemoteChangeFetchFailure(checkpointKey: String, threshold: Int) throws -> Bool {
    try write { db in
      let previousKey = try SyncCheckpoints.get(db, key: Self.remoteFetchFailureCheckpointKey)
      let previousCount =
        previousKey == checkpointKey
        ? Int(try SyncCheckpoints.get(db, key: Self.remoteFetchFailureCountKey) ?? "0") ?? 0
        : 0
      let nextCount = previousCount + 1
      try SyncCheckpoints.set(db, key: Self.remoteFetchFailureCheckpointKey, value: checkpointKey)
      try SyncCheckpoints.set(db, key: Self.remoteFetchFailureCountKey, value: "\(nextCount)")
      guard nextCount >= threshold else { return false }
      ErrorLog.appendBestEffort(
        db,
        source: "cloudsync.remote_change.per_record_failure",
        message:
          "CloudKit record fetch failed \(nextCount) consecutive time(s) at the same checkpoint; "
          + "that traversal must restart from the beginning.",
        details: nil,
        level: "error")
      return true
    }
  }
}
