import GRDB
import LorvexDomain
import LorvexStore

extension CloudTraversalWitness {
  /// Highest CloudKit generation authority this physical database lineage has
  /// ever observed or successfully claimed for one account.
  ///
  /// `nil` is deliberately distinct from generation zero: it means a fresh
  /// account binding has not yet seen any remote authority and may safely resume
  /// an interrupted first bootstrap. Once present, the witness is monotonic and
  /// survives account switches and physical-database lineage rotation. A
  /// rotation that occurs in the binding-before-first-authority window creates
  /// a generation-zero sentinel so the clone can never again look genuinely
  /// fresh to a missing remote control record.
  public static func observedGenerationAuthorityFloor(
    _ db: Database, accountIdentifier: String
  ) throws -> Int? {
    try validateAccountIdentifier(accountIdentifier)
    try requireActiveAccount(db, accountIdentifier: accountIdentifier)
    guard
      let row = try Row.fetchOne(
        db,
        sql: """
          SELECT maximum_observed_generation, database_instance_id, observed_at
          FROM sync_cloudkit_authority_witness
          WHERE account_identifier = ?
          """,
        arguments: [accountIdentifier])
    else { return nil }

    let generation: Int = row["maximum_observed_generation"]
    let databaseInstanceIdentifier: String = row["database_instance_id"]
    let observedAt: String = row["observed_at"]
    guard generation >= 0, generation <= CloudTraversalBoundary.maxGeneration else {
      throw CloudTraversalStateError.malformedStoredState
    }
    try validateDatabaseInstanceIdentifier(databaseInstanceIdentifier)
    try validateTimestamp(observedAt)
    try requireCurrentDatabase(db, storedIdentifier: databaseInstanceIdentifier)
    return generation
  }

  /// Durably observe a generation authority before consuming it. Re-observing
  /// the same/newer generation is idempotent/monotonic; a lower generation is a
  /// rollback and fails closed.
  @discardableResult
  public static func recordObservedGenerationAuthority(
    _ db: Database, accountIdentifier: String, generation: Int,
    observedAt: String = SyncTimestampFormat.syncTimestampNow()
  ) throws -> Int {
    try requireTransaction(db)
    try validateAccountIdentifier(accountIdentifier)
    try requireActiveAccount(db, accountIdentifier: accountIdentifier)
    guard generation >= 0, generation <= CloudTraversalBoundary.maxGeneration else {
      throw CloudTraversalStateError.invalidGeneration
    }
    try validateTimestamp(observedAt)
    let databaseInstanceIdentifier = try currentDatabaseIdentifier(db)

    if let current = try observedGenerationAuthorityFloor(
      db, accountIdentifier: accountIdentifier)
    {
      guard generation >= current else {
        throw CloudTraversalStateError.staleGeneration(
          current: current, attempted: generation)
      }
      if generation == current { return current }
      try db.execute(
        sql: """
          UPDATE sync_cloudkit_authority_witness
          SET maximum_observed_generation = ?, observed_at = ?
          WHERE account_identifier = ? AND database_instance_id = ?
          """,
        arguments: [generation, observedAt, accountIdentifier, databaseInstanceIdentifier])
      guard db.changesCount == 1 else {
        throw CloudTraversalStateError.databaseInstanceMismatch
      }
      return generation
    }

    try db.execute(
      sql: """
        INSERT INTO sync_cloudkit_authority_witness (
          account_identifier, maximum_observed_generation,
          database_instance_id, observed_at
        ) VALUES (?, ?, ?, ?)
        """,
      arguments: [accountIdentifier, generation, databaseInstanceIdentifier, observedAt])
    return generation
  }
}
