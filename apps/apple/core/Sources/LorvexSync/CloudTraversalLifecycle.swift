import Foundation
import GRDB
import LorvexDomain
import LorvexStore

extension CloudTraversalWitness {
  /// Starts or resumes one generation-fixed traversal. A different traversal
  /// replaces unfinished work only inside the currently bound account; a
  /// durable newer generation, or the same generation bound to another zone,
  /// is rejected before any cursor is written.
  ///
  /// The internal savepoint makes generation-ledger reservation and progress
  /// creation one indivisible mutation even if a caller catches this method's
  /// error and commits its surrounding transaction.
  @discardableResult
  public static func begin(
    _ db: Database, boundary: CloudTraversalBoundary, traversalIdentifier: String,
    start: CloudTraversalStart,
    startedAt: String = SyncTimestampFormat.syncTimestampNow()
  ) throws -> CloudTraversalProgress {
    try requireTransaction(db)
    return try StoreTransactions.withSavepoint(db, "cloud_traversal_begin") { db in
      try validateTraversalIdentifier(traversalIdentifier)
      try validateTimestamp(startedAt)
      try requireActiveAccount(db, accountIdentifier: boundary.accountIdentifier)
      let databaseInstanceIdentifier = try currentDatabaseIdentifier(db)
      try validateGenerationFence(db, boundary: boundary)
      try recordGenerationDescriptor(
        db, boundary: boundary,
        databaseInstanceIdentifier: databaseInstanceIdentifier, observedAt: startedAt)

      if let active = try progressForAccount(
        db, accountIdentifier: boundary.accountIdentifier),
        active.boundary == boundary,
        active.traversalIdentifier == traversalIdentifier
      {
        guard active.mode == start.mode else {
          throw CloudTraversalStateError.traversalModeMismatch
        }
        guard active.startingChangeToken == start.changeToken else {
          throw CloudTraversalStateError.continuationMismatch
        }
        return active
      }
      if start.mode == .incremental {
        try validateIncrementalStart(db, boundary: boundary, start: start)
      }
      try db.execute(
        sql: "DELETE FROM sync_cloudkit_traversal_progress WHERE account_identifier = ?",
        arguments: [boundary.accountIdentifier])
      try db.execute(
        sql: """
          INSERT INTO sync_cloudkit_traversal_progress
              (account_identifier, zone_identifier, database_instance_id, generation,
               generation_identifier, ready_witness, traversal_identifier,
               traversal_mode, starting_change_token,
               observed_generation_root, observed_ready_witness,
               observed_traversal_witness,
               next_page_index, continuation_token,
               started_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL, 0, ?, ?, ?)
          """,
        arguments: [
          boundary.accountIdentifier, boundary.zoneIdentifier, databaseInstanceIdentifier,
          boundary.generation, boundary.generationIdentifier, boundary.readyWitness,
          traversalIdentifier, start.mode.rawValue, start.changeToken, start.changeToken,
          startedAt, startedAt,
        ])
      return CloudTraversalProgress(
        boundary: boundary, databaseInstanceIdentifier: databaseInstanceIdentifier,
        traversalIdentifier: traversalIdentifier, mode: start.mode,
        startingChangeToken: start.changeToken,
        observedGenerationRoot: false, observedReadyWitness: false,
        observedTraversalWitness: false,
        observedTraversalWitnessServerTime: nil, nextPageIndex: 0,
        continuationToken: start.changeToken, startedAt: startedAt, updatedAt: startedAt)
    }
  }
}
