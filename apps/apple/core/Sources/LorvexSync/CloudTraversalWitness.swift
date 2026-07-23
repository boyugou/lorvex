import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Typed storage for the durable CloudKit traversal proof.
///
/// Every mutating method operates on the caller's `Database`, so a service can
/// place the page's domain apply or authoritative reconciliation, zone-epoch
/// enrollment, and traversal transition in the same SQLite transaction.
public enum CloudTraversalWitness {
  static let maxDatabaseInstanceIdentifierBytes = 128
  static let maxTraversalIdentifierBytes = 128

  public static func state(
    _ db: Database, accountIdentifier: String, zoneIdentifier: String
  ) throws -> CloudTraversalState {
    try validateAccountIdentifier(accountIdentifier)
    try validateZoneIdentifier(zoneIdentifier)
    try requireActiveAccount(db, accountIdentifier: accountIdentifier)
    return CloudTraversalState(
      progress: try progress(
        db, accountIdentifier: accountIdentifier, zoneIdentifier: zoneIdentifier),
      baselineWitness: try completion(
        db, accountIdentifier: accountIdentifier, zoneIdentifier: zoneIdentifier),
      incrementalCursor: try incrementalCursor(
        db, accountIdentifier: accountIdentifier, zoneIdentifier: zoneIdentifier))
  }

  /// Validates page identity and sequence before any page effects run. The
  /// caller must perform this preflight and the later `commitPage` in the same
  /// transaction. `new` authorizes effects; every `already...` result requires
  /// returning without replaying them.
  public static func preflightPage(
    _ db: Database, boundary: CloudTraversalBoundary, traversalIdentifier: String,
    page: CloudTraversalPageCommit
  ) throws -> CloudTraversalPageDisposition {
    try requireTransaction(db)
    try validateTraversalIdentifier(traversalIdentifier)
    try requireActiveAccount(db, accountIdentifier: boundary.accountIdentifier)
    try validateGenerationFence(db, boundary: boundary)
    let databaseInstanceIdentifier = try currentDatabaseIdentifier(db)
    try requireRecordedGenerationDescriptor(
      db, boundary: boundary,
      databaseInstanceIdentifier: databaseInstanceIdentifier)
    let pageObservation = try validate(
      page.observation, boundary: boundary, traversalIdentifier: traversalIdentifier)

    guard let current = try progress(db, boundary: boundary) else {
      if !page.moreComing,
        let completed = try completion(
          db, accountIdentifier: boundary.accountIdentifier,
          zoneIdentifier: boundary.zoneIdentifier),
        completed.boundary == boundary,
        completed.traversalIdentifier == traversalIdentifier,
        completed.completedPageCount == page.pageIndex + 1,
        completed.finalChangeToken == page.continuationToken
      {
        return .alreadyBaselineCompleted(completed)
      }
      if !page.moreComing,
        let cursor = try incrementalCursor(
          db, accountIdentifier: boundary.accountIdentifier,
          zoneIdentifier: boundary.zoneIdentifier),
        cursor.boundary == boundary,
        cursor.traversalIdentifier == traversalIdentifier,
        cursor.completedPageCount == page.pageIndex + 1,
        cursor.changeToken == page.continuationToken
      {
        return .alreadyIncrementalCompleted(cursor)
      }
      throw CloudTraversalStateError.noActiveTraversal
    }
    guard current.boundary == boundary,
      current.traversalIdentifier == traversalIdentifier
    else { throw CloudTraversalStateError.traversalBoundaryMismatch }

    if page.pageIndex == current.nextPageIndex - 1 {
      guard page.moreComing, page.continuationToken == current.continuationToken else {
        throw CloudTraversalStateError.continuationMismatch
      }
      guard !pageObservation.generationRoot || current.observedGenerationRoot,
        !pageObservation.readyWitness || current.observedReadyWitness,
        !pageObservation.traversalWitness || current.observedTraversalWitness,
        pageObservation.traversalWitnessServerTime == nil
          || pageObservation.traversalWitnessServerTime
            == current.observedTraversalWitnessServerTime
      else { throw CloudTraversalStateError.continuationMismatch }
      return .alreadyRecorded
    }
    guard page.pageIndex == current.nextPageIndex else {
      throw CloudTraversalStateError.pageSequenceMismatch(
        expected: current.nextPageIndex, actual: page.pageIndex)
    }
    return .new
  }

  /// Records a page after its local effects have succeeded. Call this inside the
  /// same transaction as `preflightPage` and those effects. The method repeats
  /// preflight as a final CAS guard. Nonterminal pages advance the only permitted
  /// continuation; a terminal page replaces the completed witness and deletes
  /// progress atomically.
  @discardableResult
  public static func commitPage(
    _ db: Database, boundary: CloudTraversalBoundary, traversalIdentifier: String,
    page: CloudTraversalPageCommit,
    completedAt: String = SyncTimestampFormat.syncTimestampNow()
  ) throws -> CloudTraversalCommitResult {
    try requireTransaction(db)
    return try StoreTransactions.withSavepoint(db, "cloud_traversal_commit_page") { db in
      switch try preflightPage(
        db, boundary: boundary, traversalIdentifier: traversalIdentifier, page: page)
      {
      case .new:
        break
      case .alreadyRecorded:
        return .alreadyRecorded
      case .alreadyBaselineCompleted(let completion):
        return .alreadyBaselineCompleted(completion)
      case .alreadyIncrementalCompleted(let cursor):
        return .alreadyIncrementalCompleted(cursor)
      }
      if !page.moreComing { try validateTimestamp(completedAt) }
      guard let current = try progress(db, boundary: boundary) else {
        throw CloudTraversalStateError.noActiveTraversal
      }
      guard current.boundary == boundary,
        current.traversalIdentifier == traversalIdentifier,
        current.nextPageIndex == page.pageIndex
      else { throw CloudTraversalStateError.traversalBoundaryMismatch }
      let pageObservation = try validate(
        page.observation, boundary: boundary, traversalIdentifier: traversalIdentifier)

      if page.moreComing {
        let updatedAt = SyncTimestampFormat.syncTimestampNow()
        try validateTimestamp(updatedAt)
        let observedGenerationRoot =
          current.observedGenerationRoot || pageObservation.generationRoot
        let observedReadyWitness = current.observedReadyWitness || pageObservation.readyWitness
        let observedTraversalWitness =
          current.observedTraversalWitness || pageObservation.traversalWitness
        let observedTraversalWitnessServerTime =
          current.observedTraversalWitnessServerTime
          ?? pageObservation.traversalWitnessServerTime
        try db.execute(
          sql: """
            UPDATE sync_cloudkit_traversal_progress
            SET observed_generation_root = ?, observed_ready_witness = ?,
                observed_traversal_witness = ?, observed_traversal_server_time = ?,
                next_page_index = ?,
                continuation_token = ?, updated_at = ?
            WHERE account_identifier = ? AND zone_identifier = ?
              AND database_instance_id = ? AND generation = ?
              AND generation_identifier = ? AND ready_witness = ?
              AND traversal_identifier = ? AND next_page_index = ?
            """,
          arguments: [
            observedGenerationRoot ? boundary.generationIdentifier : nil,
            observedReadyWitness ? boundary.readyWitness : nil,
            observedTraversalWitness ? traversalIdentifier : nil,
            observedTraversalWitnessServerTime,
            page.pageIndex + 1, page.continuationToken, updatedAt,
            boundary.accountIdentifier, boundary.zoneIdentifier,
            current.databaseInstanceIdentifier, boundary.generation,
            boundary.generationIdentifier, boundary.readyWitness,
            traversalIdentifier, page.pageIndex,
          ])
        guard db.changesCount == 1 else {
          throw CloudTraversalStateError.traversalBoundaryMismatch
        }
        let updated = CloudTraversalProgress(
          boundary: current.boundary,
          databaseInstanceIdentifier: current.databaseInstanceIdentifier,
          traversalIdentifier: current.traversalIdentifier, mode: current.mode,
          startingChangeToken: current.startingChangeToken,
          observedGenerationRoot: observedGenerationRoot,
          observedReadyWitness: observedReadyWitness,
          observedTraversalWitness: observedTraversalWitness,
          observedTraversalWitnessServerTime: observedTraversalWitnessServerTime,
          nextPageIndex: page.pageIndex + 1,
          continuationToken: page.continuationToken,
          startedAt: current.startedAt, updatedAt: updatedAt)
        return .continuationRecorded(updated)
      }

      let result: CloudTraversalCommitResult
      switch current.mode {
      case .baseline:
        guard current.observedGenerationRoot || pageObservation.generationRoot,
          current.observedReadyWitness || pageObservation.readyWitness,
          current.observedTraversalWitness || pageObservation.traversalWitness
        else { throw CloudTraversalStateError.baselineProofIncomplete }
        try db.execute(
          sql: """
            INSERT INTO sync_cloudkit_traversal_witness
                (account_identifier, zone_identifier, database_instance_id, generation,
                 generation_identifier, ready_witness, traversal_identifier,
                 traversal_mode, observed_generation_root, observed_ready_witness,
                 observed_traversal_witness, completed_page_count,
                 final_change_token, completed_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, 'baseline', ?, ?, ?, ?, ?, ?)
            ON CONFLICT(account_identifier) DO UPDATE SET
              zone_identifier = excluded.zone_identifier,
              database_instance_id = excluded.database_instance_id,
              generation = excluded.generation,
              generation_identifier = excluded.generation_identifier,
              ready_witness = excluded.ready_witness,
              traversal_identifier = excluded.traversal_identifier,
              traversal_mode = excluded.traversal_mode,
              observed_generation_root = excluded.observed_generation_root,
              observed_ready_witness = excluded.observed_ready_witness,
              observed_traversal_witness = excluded.observed_traversal_witness,
              completed_page_count = excluded.completed_page_count,
              final_change_token = excluded.final_change_token,
              completed_at = excluded.completed_at
            """,
          arguments: [
            boundary.accountIdentifier, boundary.zoneIdentifier,
            current.databaseInstanceIdentifier, boundary.generation,
            boundary.generationIdentifier, boundary.readyWitness, traversalIdentifier,
            boundary.generationIdentifier, boundary.readyWitness, traversalIdentifier,
            page.pageIndex + 1, page.continuationToken, completedAt,
          ])
        try db.execute(
          sql: "DELETE FROM sync_cloudkit_incremental_cursor WHERE account_identifier = ?",
          arguments: [boundary.accountIdentifier])
        let completed = CloudTraversalCompletion(
          boundary: boundary, databaseInstanceIdentifier: current.databaseInstanceIdentifier,
          traversalIdentifier: traversalIdentifier, completedPageCount: page.pageIndex + 1,
          finalChangeToken: page.continuationToken, completedAt: completedAt)
        result = .baselineCompleted(completed)
      case .incremental:
        guard let finalToken = page.continuationToken else {
          throw CloudTraversalStateError.invalidContinuationToken
        }
        try db.execute(
          sql: """
            INSERT INTO sync_cloudkit_incremental_cursor
                (account_identifier, zone_identifier, database_instance_id, generation,
                 generation_identifier, ready_witness, traversal_identifier,
                 completed_page_count, change_token, completed_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(account_identifier) DO UPDATE SET
              zone_identifier = excluded.zone_identifier,
              database_instance_id = excluded.database_instance_id,
              generation = excluded.generation,
              generation_identifier = excluded.generation_identifier,
              ready_witness = excluded.ready_witness,
              traversal_identifier = excluded.traversal_identifier,
              completed_page_count = excluded.completed_page_count,
              change_token = excluded.change_token,
              completed_at = excluded.completed_at
            """,
          arguments: [
            boundary.accountIdentifier, boundary.zoneIdentifier,
            current.databaseInstanceIdentifier, boundary.generation,
            boundary.generationIdentifier, boundary.readyWitness, traversalIdentifier,
            page.pageIndex + 1, finalToken, completedAt,
          ])
        let cursor = CloudTraversalIncrementalCursor(
          boundary: boundary, databaseInstanceIdentifier: current.databaseInstanceIdentifier,
          traversalIdentifier: traversalIdentifier, completedPageCount: page.pageIndex + 1,
          changeToken: finalToken, completedAt: completedAt)
        result = .incrementalCompleted(cursor)
      }
      let terminalServerTime = current.observedTraversalWitnessServerTime
        ?? pageObservation.traversalWitnessServerTime
      if let terminalServerTime {
        try db.execute(
          sql: """
            UPDATE sync_cloudkit_account_binding
            SET trusted_terminal_server_time = CASE
              WHEN trusted_terminal_server_time IS NULL
                OR trusted_terminal_server_time < ? THEN ?
              ELSE trusted_terminal_server_time
            END
            WHERE singleton = 1 AND account_identifier = ?
              AND database_instance_id = ?
            """,
          arguments: [
            terminalServerTime, terminalServerTime,
            boundary.accountIdentifier, current.databaseInstanceIdentifier,
          ])
        guard db.changesCount == 1 else {
          throw CloudTraversalStateError.accountBindingCompareAndSwapFailed
        }
      }
      try db.execute(
        sql: """
          DELETE FROM sync_cloudkit_traversal_progress
          WHERE account_identifier = ? AND zone_identifier = ?
            AND database_instance_id = ? AND generation = ?
            AND generation_identifier = ? AND ready_witness = ?
            AND traversal_identifier = ?
          """,
        arguments: [
          boundary.accountIdentifier, boundary.zoneIdentifier,
          current.databaseInstanceIdentifier, boundary.generation,
          boundary.generationIdentifier, boundary.readyWitness, traversalIdentifier,
        ])
      guard db.changesCount == 1 else {
        throw CloudTraversalStateError.traversalBoundaryMismatch
      }
      return result
    }
  }

  public static func cancel(
    _ db: Database, boundary: CloudTraversalBoundary, traversalIdentifier: String
  ) throws {
    try requireTransaction(db)
    try validateTraversalIdentifier(traversalIdentifier)
    try requireActiveAccount(db, accountIdentifier: boundary.accountIdentifier)
    try db.execute(
      sql: """
        DELETE FROM sync_cloudkit_traversal_progress
        WHERE account_identifier = ? AND zone_identifier = ?
          AND generation = ? AND generation_identifier = ?
          AND ready_witness = ? AND traversal_identifier = ?
        """,
      arguments: [
        boundary.accountIdentifier, boundary.zoneIdentifier,
        boundary.generation, boundary.generationIdentifier,
        boundary.readyWitness, traversalIdentifier,
      ])
  }

  // MARK: - Row decoding and fail-closed validation

  private static func progress(
    _ db: Database, boundary: CloudTraversalBoundary
  ) throws -> CloudTraversalProgress? {
    try progress(
      db, accountIdentifier: boundary.accountIdentifier,
      zoneIdentifier: boundary.zoneIdentifier)
  }

  private static func progress(
    _ db: Database, accountIdentifier: String, zoneIdentifier: String
  ) throws -> CloudTraversalProgress? {
    guard let progress = try progressForAccount(db, accountIdentifier: accountIdentifier),
      progress.boundary.zoneIdentifier == zoneIdentifier
    else { return nil }
    return progress
  }

  static func progressForAccount(
    _ db: Database, accountIdentifier: String
  ) throws -> CloudTraversalProgress? {
    guard
      let row = try Row.fetchOne(
        db,
        sql: """
          SELECT account_identifier, zone_identifier, database_instance_id, generation,
                 generation_identifier, ready_witness, traversal_identifier,
                 traversal_mode, starting_change_token,
                 observed_generation_root, observed_ready_witness,
                 observed_traversal_witness, observed_traversal_server_time,
                 next_page_index, continuation_token,
                 started_at, updated_at,
                 (SELECT descriptor.tombstone_compaction_cutoff
                  FROM sync_cloudkit_generation_descriptor descriptor
                  WHERE descriptor.account_identifier = progress.account_identifier
                    AND descriptor.generation = progress.generation)
                   AS tombstone_compaction_cutoff
          FROM sync_cloudkit_traversal_progress progress
          WHERE account_identifier = ?
          """,
        arguments: [accountIdentifier])
    else { return nil }
    do {
      let boundary = try CloudTraversalBoundary(
        accountIdentifier: row["account_identifier"], zoneIdentifier: row["zone_identifier"],
        generation: row["generation"], generationIdentifier: row["generation_identifier"],
        readyWitness: row["ready_witness"],
        tombstoneCompactionCutoff: row["tombstone_compaction_cutoff"])
      let databaseInstanceIdentifier: String = row["database_instance_id"]
      let traversalIdentifier: String = row["traversal_identifier"]
      let modeValue: String = row["traversal_mode"]
      let startingChangeToken: Data? = row["starting_change_token"]
      let observedGenerationRoot: String? = row["observed_generation_root"]
      let observedReadyWitness: String? = row["observed_ready_witness"]
      let observedTraversalWitness: String? = row["observed_traversal_witness"]
      let observedTraversalWitnessServerTime: String? =
        row["observed_traversal_server_time"]
      let nextPageIndex: Int = row["next_page_index"]
      let continuationToken: Data? = row["continuation_token"]
      let startedAt: String = row["started_at"]
      let updatedAt: String = row["updated_at"]
      try validateDatabaseInstanceIdentifier(databaseInstanceIdentifier)
      try validateTraversalIdentifier(traversalIdentifier)
      guard let mode = CloudTraversalMode(rawValue: modeValue) else {
        throw CloudTraversalStateError.malformedStoredState
      }
      guard nextPageIndex >= 0, nextPageIndex <= CloudTraversalPageCommit.maxPageIndex + 1 else {
        throw CloudTraversalStateError.malformedStoredState
      }
      switch mode {
      case .baseline:
        guard startingChangeToken == nil else {
          throw CloudTraversalStateError.malformedStoredState
        }
      case .incremental:
        guard let startingChangeToken else {
          throw CloudTraversalStateError.malformedStoredState
        }
        try validateContinuationToken(startingChangeToken)
      }
      if let continuationToken {
        try validateContinuationToken(continuationToken)
      } else if nextPageIndex != 0 || mode != .baseline {
        throw CloudTraversalStateError.malformedStoredState
      }
      if nextPageIndex == 0, continuationToken != startingChangeToken {
        throw CloudTraversalStateError.malformedStoredState
      }
      guard
        observedGenerationRoot == nil
          || observedGenerationRoot == boundary.generationIdentifier,
        observedReadyWitness == nil || observedReadyWitness == boundary.readyWitness,
        observedTraversalWitness == nil || observedTraversalWitness == traversalIdentifier
      else { throw CloudTraversalStateError.malformedStoredState }
      if let observedTraversalWitnessServerTime {
        guard observedTraversalWitness != nil else {
          throw CloudTraversalStateError.malformedStoredState
        }
        try validateTimestamp(observedTraversalWitnessServerTime)
      }
      try validateTimestamp(startedAt)
      try validateTimestamp(updatedAt)
      try requireCurrentDatabase(db, storedIdentifier: databaseInstanceIdentifier)
      try requireRecordedGenerationDescriptor(
        db, boundary: boundary,
        databaseInstanceIdentifier: databaseInstanceIdentifier)
      return CloudTraversalProgress(
        boundary: boundary, databaseInstanceIdentifier: databaseInstanceIdentifier,
        traversalIdentifier: traversalIdentifier, mode: mode,
        startingChangeToken: startingChangeToken,
        observedGenerationRoot: observedGenerationRoot != nil,
        observedReadyWitness: observedReadyWitness != nil,
        observedTraversalWitness: observedTraversalWitness != nil,
        observedTraversalWitnessServerTime: observedTraversalWitnessServerTime,
        nextPageIndex: nextPageIndex,
        continuationToken: continuationToken, startedAt: startedAt, updatedAt: updatedAt)
    } catch let error as CloudTraversalStateError {
      throw error
    } catch {
      throw CloudTraversalStateError.malformedStoredState
    }
  }

  private static func completion(
    _ db: Database, accountIdentifier: String, zoneIdentifier: String
  ) throws -> CloudTraversalCompletion? {
    guard let completion = try completionForAccount(db, accountIdentifier: accountIdentifier),
      completion.boundary.zoneIdentifier == zoneIdentifier
    else { return nil }
    return completion
  }

  private static func completionForAccount(
    _ db: Database, accountIdentifier: String
  ) throws -> CloudTraversalCompletion? {
    guard
      let row = try Row.fetchOne(
        db,
        sql: """
          SELECT account_identifier, zone_identifier, database_instance_id, generation,
                 generation_identifier, ready_witness, traversal_identifier,
                 traversal_mode, observed_generation_root, observed_ready_witness,
                 observed_traversal_witness, completed_page_count,
                 final_change_token, completed_at,
                 (SELECT descriptor.tombstone_compaction_cutoff
                  FROM sync_cloudkit_generation_descriptor descriptor
                  WHERE descriptor.account_identifier = witness.account_identifier
                    AND descriptor.generation = witness.generation)
                   AS tombstone_compaction_cutoff
          FROM sync_cloudkit_traversal_witness witness
          WHERE account_identifier = ?
          """,
        arguments: [accountIdentifier])
    else { return nil }
    do {
      let boundary = try CloudTraversalBoundary(
        accountIdentifier: row["account_identifier"], zoneIdentifier: row["zone_identifier"],
        generation: row["generation"], generationIdentifier: row["generation_identifier"],
        readyWitness: row["ready_witness"],
        tombstoneCompactionCutoff: row["tombstone_compaction_cutoff"])
      let databaseInstanceIdentifier: String = row["database_instance_id"]
      let traversalIdentifier: String = row["traversal_identifier"]
      let traversalMode: String = row["traversal_mode"]
      let observedGenerationRoot: String = row["observed_generation_root"]
      let observedReadyWitness: String = row["observed_ready_witness"]
      let observedTraversalWitness: String = row["observed_traversal_witness"]
      let completedPageCount: Int = row["completed_page_count"]
      let finalChangeToken: Data? = row["final_change_token"]
      let completedAt: String = row["completed_at"]
      try validateDatabaseInstanceIdentifier(databaseInstanceIdentifier)
      try validateTraversalIdentifier(traversalIdentifier)
      guard traversalMode == CloudTraversalMode.baseline.rawValue else {
        throw CloudTraversalStateError.malformedStoredState
      }
      guard observedGenerationRoot == boundary.generationIdentifier,
        observedReadyWitness == boundary.readyWitness,
        observedTraversalWitness == traversalIdentifier
      else { throw CloudTraversalStateError.malformedStoredState }
      guard completedPageCount > 0,
        completedPageCount <= CloudTraversalPageCommit.maxPageIndex + 1
      else { throw CloudTraversalStateError.malformedStoredState }
      if let finalChangeToken { try validateContinuationToken(finalChangeToken) }
      try validateTimestamp(completedAt)
      try requireCurrentDatabase(db, storedIdentifier: databaseInstanceIdentifier)
      try requireRecordedGenerationDescriptor(
        db, boundary: boundary,
        databaseInstanceIdentifier: databaseInstanceIdentifier)
      return CloudTraversalCompletion(
        boundary: boundary, databaseInstanceIdentifier: databaseInstanceIdentifier,
        traversalIdentifier: traversalIdentifier, completedPageCount: completedPageCount,
        finalChangeToken: finalChangeToken, completedAt: completedAt)
    } catch let error as CloudTraversalStateError {
      throw error
    } catch {
      throw CloudTraversalStateError.malformedStoredState
    }
  }

  private static func incrementalCursor(
    _ db: Database, accountIdentifier: String, zoneIdentifier: String
  ) throws -> CloudTraversalIncrementalCursor? {
    guard
      let cursor = try incrementalCursorForAccount(db, accountIdentifier: accountIdentifier),
      cursor.boundary.zoneIdentifier == zoneIdentifier
    else { return nil }
    return cursor
  }

  private static func incrementalCursorForAccount(
    _ db: Database, accountIdentifier: String
  ) throws -> CloudTraversalIncrementalCursor? {
    guard
      let row = try Row.fetchOne(
        db,
        sql: """
          SELECT account_identifier, zone_identifier, database_instance_id, generation,
                 generation_identifier, ready_witness, traversal_identifier,
                 completed_page_count, change_token, completed_at,
                 (SELECT descriptor.tombstone_compaction_cutoff
                  FROM sync_cloudkit_generation_descriptor descriptor
                  WHERE descriptor.account_identifier = cursor.account_identifier
                    AND descriptor.generation = cursor.generation)
                   AS tombstone_compaction_cutoff
          FROM sync_cloudkit_incremental_cursor cursor
          WHERE account_identifier = ?
          """,
        arguments: [accountIdentifier])
    else { return nil }
    do {
      let boundary = try CloudTraversalBoundary(
        accountIdentifier: row["account_identifier"], zoneIdentifier: row["zone_identifier"],
        generation: row["generation"], generationIdentifier: row["generation_identifier"],
        readyWitness: row["ready_witness"],
        tombstoneCompactionCutoff: row["tombstone_compaction_cutoff"])
      let databaseInstanceIdentifier: String = row["database_instance_id"]
      let traversalIdentifier: String = row["traversal_identifier"]
      let completedPageCount: Int = row["completed_page_count"]
      let changeToken: Data = row["change_token"]
      let completedAt: String = row["completed_at"]
      try validateDatabaseInstanceIdentifier(databaseInstanceIdentifier)
      try validateTraversalIdentifier(traversalIdentifier)
      guard completedPageCount > 0,
        completedPageCount <= CloudTraversalPageCommit.maxPageIndex + 1
      else { throw CloudTraversalStateError.malformedStoredState }
      try validateContinuationToken(changeToken)
      try validateTimestamp(completedAt)
      try requireCurrentDatabase(db, storedIdentifier: databaseInstanceIdentifier)
      try requireRecordedGenerationDescriptor(
        db, boundary: boundary,
        databaseInstanceIdentifier: databaseInstanceIdentifier)
      return CloudTraversalIncrementalCursor(
        boundary: boundary, databaseInstanceIdentifier: databaseInstanceIdentifier,
        traversalIdentifier: traversalIdentifier, completedPageCount: completedPageCount,
        changeToken: changeToken, completedAt: completedAt)
    } catch let error as CloudTraversalStateError {
      throw error
    } catch {
      throw CloudTraversalStateError.malformedStoredState
    }
  }

  private static func validate(
    _ observation: CloudTraversalPageObservation, boundary: CloudTraversalBoundary,
    traversalIdentifier: String
  ) throws -> (
    generationRoot: Bool, readyWitness: Bool, traversalWitness: Bool,
    traversalWitnessServerTime: String?
  ) {
    if let observed = observation.generationRootIdentifier,
      observed != boundary.generationIdentifier
    {
      throw CloudTraversalStateError.generationRootMismatch
    }
    if let observed = observation.readyWitness, observed != boundary.readyWitness {
      throw CloudTraversalStateError.readyWitnessMismatch
    }
    if let observed = observation.traversalWitnessIdentifier,
      observed != traversalIdentifier
    {
      throw CloudTraversalStateError.traversalWitnessMismatch
    }
    return (
      observation.generationRootIdentifier != nil,
      observation.readyWitness != nil,
      observation.traversalWitnessIdentifier != nil,
      observation.traversalWitnessServerTime
    )
  }

  static func validateIncrementalStart(
    _ db: Database, boundary: CloudTraversalBoundary, start: CloudTraversalStart
  ) throws {
    guard start.mode == .incremental, let requestedToken = start.changeToken else {
      throw CloudTraversalStateError.traversalModeMismatch
    }
    guard
      let baseline = try completionForAccount(
        db, accountIdentifier: boundary.accountIdentifier),
      baseline.boundary == boundary
    else { throw CloudTraversalStateError.baselineWitnessRequired }

    let cursor = try incrementalCursorForAccount(
      db, accountIdentifier: boundary.accountIdentifier)
    let durableToken: Data?
    if let cursor {
      guard cursor.boundary == boundary else {
        throw CloudTraversalStateError.baselineWitnessRequired
      }
      durableToken = cursor.changeToken
    } else {
      durableToken = baseline.finalChangeToken
    }
    guard let durableToken else {
      throw CloudTraversalStateError.noDurableIncrementalCursor
    }
    guard durableToken == requestedToken else {
      throw CloudTraversalStateError.continuationMismatch
    }
  }

}
