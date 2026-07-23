import Foundation
import GRDB
import LorvexDomain
import LorvexStore

extension CloudTraversalWitness {
  private static var bindingSingleton: Int64 { 1 }

  public static func accountBinding(_ db: Database) throws -> CloudTraversalAccountBinding? {
    guard let binding = try storedAccountBinding(db) else { return nil }
    try requireCurrentDatabase(db, storedIdentifier: binding.databaseInstanceIdentifier)
    return binding
  }

  /// Read-only source boundary for preparing an explicit adoption capability.
  /// Unlike ``accountBinding(_:)`` this deliberately returns the stored physical
  /// identifier after a restore/clone rotated the current database identity;
  /// the caller may compare it but must use ``prepareAccountAdoption`` to mutate
  /// or trust it on the new lineage.
  public static func accountBindingForAdoption(
    _ db: Database
  ) throws -> CloudTraversalAccountBinding? {
    try storedAccountBinding(db)
  }

  private static func storedAccountBinding(_ db: Database) throws -> CloudTraversalAccountBinding? {
    guard
      let row = try Row.fetchOne(
        db,
        sql: """
          SELECT account_identifier, database_instance_id, bound_at
          FROM sync_cloudkit_account_binding
          WHERE singleton = ?
          """,
        arguments: [bindingSingleton])
    else { return nil }
    let binding = CloudTraversalAccountBinding(
      accountIdentifier: row["account_identifier"],
      databaseInstanceIdentifier: row["database_instance_id"], boundAt: row["bound_at"])
    try validate(binding)
    return binding
  }

  /// Atomically claims an unbound database for one account. Repeating the same
  /// claim is idempotent; crossing accounts requires the explicit CAS adoption
  /// API below.
  @discardableResult
  public static func claimAccount(
    _ db: Database, accountIdentifier: String,
    boundAt: String = SyncTimestampFormat.syncTimestampNow()
  ) throws -> CloudTraversalAccountBinding {
    try requireTransaction(db)
    try validateAccountIdentifier(accountIdentifier)
    try validateTimestamp(boundAt)
    if let existing = try accountBinding(db) {
      guard existing.accountIdentifier == accountIdentifier else {
        throw CloudTraversalStateError.accountBoundaryMismatch(
          expected: existing.accountIdentifier, actual: accountIdentifier)
      }
      return existing
    }
    try requireNoOrphanedTraversalState(db)
    let databaseInstanceIdentifier = try currentDatabaseIdentifier(db)
    try db.execute(
      sql: """
        INSERT INTO sync_cloudkit_account_binding
            (singleton, account_identifier, database_instance_id, bound_at)
        VALUES (?, ?, ?, ?)
        """,
      arguments: [bindingSingleton, accountIdentifier, databaseInstanceIdentifier, boundAt])
    return CloudTraversalAccountBinding(
      accountIdentifier: accountIdentifier,
      databaseInstanceIdentifier: databaseInstanceIdentifier, boundAt: boundAt)
  }

  /// Explicit account-switch boundary. The expected current account is a CAS
  /// precondition. Every progress row and completion is discarded in the same
  /// transaction: after A -> B -> A, the database may have changed under B, so
  /// A's old terminal witness is no longer proof of the current local contents.
  @discardableResult
  public static func adoptAccount(
    _ db: Database, expectedCurrentAccountIdentifier: String,
    newAccountIdentifier: String, boundAt: String = SyncTimestampFormat.syncTimestampNow()
  ) throws -> CloudTraversalAccountBinding {
    try requireTransaction(db)
    try validateAccountIdentifier(expectedCurrentAccountIdentifier)
    try validateAccountIdentifier(newAccountIdentifier)
    try validateTimestamp(boundAt)
    guard let current = try accountBinding(db),
      current.accountIdentifier == expectedCurrentAccountIdentifier
    else {
      throw CloudTraversalStateError.accountBindingCompareAndSwapFailed
    }
    if expectedCurrentAccountIdentifier == newAccountIdentifier { return current }
    let databaseInstanceIdentifier = try currentDatabaseIdentifier(db)
    try resetTransportLineageForExplicitReupload(db)
    try db.execute(
      sql: """
        UPDATE sync_cloudkit_account_binding
        SET account_identifier = ?, database_instance_id = ?, bound_at = ?,
            trusted_server_time = NULL, trusted_terminal_server_time = NULL
        WHERE singleton = ? AND account_identifier = ?
        """,
      arguments: [
        newAccountIdentifier, databaseInstanceIdentifier, boundAt, bindingSingleton,
        expectedCurrentAccountIdentifier,
      ])
    guard db.changesCount == 1 else {
      throw CloudTraversalStateError.accountBindingCompareAndSwapFailed
    }
    return CloudTraversalAccountBinding(
      accountIdentifier: newAccountIdentifier,
      databaseInstanceIdentifier: databaseInstanceIdentifier, boundAt: boundAt)
  }

  /// Prepare a database for an explicitly authorized account in one SQLite
  /// transaction. A restored/cloned database may need its physical lineage
  /// rebound before its old account can be adopted; exposing those as two host
  /// calls creates a permanent recovery deadlock because the normal sync path is
  /// paused while adoption is pending. This operation discovers the stored
  /// account inside the transaction, repairs a rotated database identity when
  /// necessary, then adopts the requested account with no externally supplied
  /// stale-account guess.
  @discardableResult
  public static func prepareAccountAdoption(
    _ db: Database, newAccountIdentifier: String,
    resetSameAccountDeletedZoneLineage: Bool = false,
    boundAt: String = SyncTimestampFormat.syncTimestampNow()
  ) throws -> CloudTraversalAccountAdoption {
    try requireTransaction(db)
    try validateAccountIdentifier(newAccountIdentifier)
    try validateTimestamp(boundAt)

    guard let stored = try storedAccountBinding(db) else {
      let claimed = try claimAccount(
        db, accountIdentifier: newAccountIdentifier, boundAt: boundAt)
      return CloudTraversalAccountAdoption(
        previousAccountIdentifier: nil, binding: claimed)
    }

    var current = stored
    let databaseInstanceIdentifier = try currentDatabaseIdentifier(db)
    if current.databaseInstanceIdentifier != databaseInstanceIdentifier {
      current = try rebindAfterDatabaseInstanceRotation(
        db, expectedAccountIdentifier: current.accountIdentifier,
        reboundAt: boundAt)
    }
    if current.accountIdentifier != newAccountIdentifier {
      current = try adoptAccount(
        db, expectedCurrentAccountIdentifier: current.accountIdentifier,
        newAccountIdentifier: newAccountIdentifier, boundAt: boundAt)
    } else if resetSameAccountDeletedZoneLineage {
      // This branch is authorized only while the remote control record is still
      // the exact `.deleted` generation captured by the host request. Once a
      // rebuild starts, retries use the ordinary same-account path above and
      // preserve every newly observed debt row and cursor.
      try resetTransportLineageForExplicitReupload(db)
    }
    return CloudTraversalAccountAdoption(
      previousAccountIdentifier: stored.accountIdentifier, binding: current)
  }

  /// Drop transport-only evidence from a CloudKit lineage the user explicitly
  /// authorized us to replace while preserving every canonical row and
  /// tombstone. A future-record hold is an old-lineage transport slot, not proof
  /// that the canonical fallback should be deleted from the new account. Remove
  /// the held slot; candidate capture enumerates canonical state independently.
  ///
  /// Traversal proof is reset in the same transaction. This makes A -> B a
  /// one-shot consequence of the binding CAS and makes same-account deleted-zone
  /// re-enable crash-safe: a retry while the remote state is still `.deleted` is
  /// idempotent, while a retry after rebuilding began preserves its new debt.
  private static func resetTransportLineageForExplicitReupload(
    _ db: Database
  ) throws {
    try db.execute(
      sql: """
        DELETE FROM sync_outbox
        WHERE synced_at IS NULL AND disposition = ?
        """,
      arguments: [Outbox.Disposition.futureRecordHold.rawValue])
    try db.execute(sql: "DELETE FROM sync_pending_inbox")
    try db.execute(sql: "DELETE FROM sync_quarantine_blocklist")
    // These claims describe convergence work already performed against the old
    // account/zone lineage. Carrying them across an explicit lineage replacement
    // could suppress the first repair required by the new remote history.
    try db.execute(sql: "DELETE FROM sync_list_fallback_reemit_claims")
    try db.execute(sql: "DELETE FROM sync_cloudkit_corrupt_record_fences")
    try db.execute(sql: "DELETE FROM sync_cloudkit_traversal_progress")
    try db.execute(sql: "DELETE FROM sync_cloudkit_traversal_witness")
    try db.execute(sql: "DELETE FROM sync_cloudkit_incremental_cursor")
    try db.execute(sql: "DELETE FROM sync_generation_snapshot_staging")
  }

  /// Explicit restore/clone boundary after the owning service has rotated the
  /// physical database instance identifier. Instance-local traversal state is
  /// deleted, never transplanted to the new lineage. Account-scoped generation
  /// authority and descriptor history are anti-rollback facts, so they are
  /// retained and rebound. Normal claim/adoption deliberately remain fail-closed
  /// while a mismatch exists.
  @discardableResult
  public static func rebindAfterDatabaseInstanceRotation(
    _ db: Database, expectedAccountIdentifier: String,
    reboundAt: String = SyncTimestampFormat.syncTimestampNow()
  ) throws -> CloudTraversalAccountBinding {
    try requireTransaction(db)
    try validateAccountIdentifier(expectedAccountIdentifier)
    try validateTimestamp(reboundAt)
    guard let stored = try storedAccountBinding(db) else {
      throw CloudTraversalStateError.noAccountBinding
    }
    guard stored.accountIdentifier == expectedAccountIdentifier else {
      throw CloudTraversalStateError.accountBindingCompareAndSwapFailed
    }
    let currentDatabaseIdentifier = try currentDatabaseIdentifier(db)
    guard currentDatabaseIdentifier != stored.databaseInstanceIdentifier else {
      throw CloudTraversalStateError.databaseInstanceRotationNotDetected
    }

    return try StoreTransactions.withSavepoint(db, "cloud_traversal_rebind") { db in
      // Progress/cursors prove what THIS physical instance applied, so a clone or
      // restore must traverse again. Generation authority and descriptor ledgers,
      // however, are account-scoped anti-rollback facts copied with the database:
      // deleting them would let a restored database treat a missing/lower default-
      // zone control record as first bootstrap and republish stale contents. Keep
      // those historical facts and bind them to the fresh local lineage instead.
      try db.execute(sql: "DELETE FROM sync_cloudkit_traversal_progress")
      try db.execute(sql: "DELETE FROM sync_cloudkit_traversal_witness")
      try db.execute(sql: "DELETE FROM sync_cloudkit_incremental_cursor")
      try db.execute(sql: "DELETE FROM sync_generation_snapshot_staging")

      // A backup may have been captured after the account binding committed but
      // before first bootstrap observed/published generation authority. On the
      // original physical lineage, an absent witness correctly means that
      // interrupted bootstrap may resume. After an explicit lineage rotation,
      // however, preserving `nil` would let a restored clone masquerade as a
      // genuinely fresh database if the remote control record were missing.
      // Generation zero is the non-nil sentinel: it forbids nil-control
      // bootstrap while remaining strictly below every real generation.
      let activeAuthorityCount = try Int.fetchOne(
        db,
        sql: """
          SELECT COUNT(*) FROM sync_cloudkit_authority_witness
          WHERE account_identifier = ?
          """,
        arguments: [expectedAccountIdentifier]) ?? 0
      if activeAuthorityCount == 0 {
        try db.execute(
          sql: """
            INSERT INTO sync_cloudkit_authority_witness (
              account_identifier, maximum_observed_generation,
              database_instance_id, observed_at
            ) VALUES (?, 0, ?, ?)
            """,
          arguments: [
            expectedAccountIdentifier, stored.databaseInstanceIdentifier, reboundAt,
          ])
      }

      let mismatchedAuthorityRows = try Int.fetchOne(
        db,
        sql: """
          SELECT COUNT(*) FROM sync_cloudkit_authority_witness
          WHERE database_instance_id <> ?
          """,
        arguments: [stored.databaseInstanceIdentifier]) ?? 0
      let mismatchedDescriptorRows = try Int.fetchOne(
        db,
        sql: """
          SELECT COUNT(*) FROM sync_cloudkit_generation_descriptor
          WHERE database_instance_id <> ?
          """,
        arguments: [stored.databaseInstanceIdentifier]) ?? 0
      guard mismatchedAuthorityRows == 0, mismatchedDescriptorRows == 0 else {
        throw CloudTraversalStateError.databaseInstanceMismatch
      }
      try db.execute(
        sql: """
          UPDATE sync_cloudkit_authority_witness
          SET database_instance_id = ?
          WHERE database_instance_id = ?
          """,
        arguments: [currentDatabaseIdentifier, stored.databaseInstanceIdentifier])
      try db.execute(
        sql: """
          UPDATE sync_cloudkit_generation_descriptor
          SET database_instance_id = ?
          WHERE database_instance_id = ?
          """,
        arguments: [currentDatabaseIdentifier, stored.databaseInstanceIdentifier])
      try db.execute(
        sql: """
          UPDATE sync_cloudkit_account_binding
          SET database_instance_id = ?, bound_at = ?,
              trusted_server_time = NULL,
              trusted_terminal_server_time = NULL
          WHERE singleton = ? AND account_identifier = ? AND database_instance_id = ?
          """,
        arguments: [
          currentDatabaseIdentifier, reboundAt, bindingSingleton,
          expectedAccountIdentifier, stored.databaseInstanceIdentifier,
        ])
      guard db.changesCount == 1 else {
        throw CloudTraversalStateError.accountBindingCompareAndSwapFailed
      }
      return CloudTraversalAccountBinding(
        accountIdentifier: expectedAccountIdentifier,
        databaseInstanceIdentifier: currentDatabaseIdentifier, boundAt: reboundAt)
    }
  }
}
