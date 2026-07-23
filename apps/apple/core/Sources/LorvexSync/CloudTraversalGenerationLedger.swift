import GRDB
import LorvexDomain
import LorvexStore

extension CloudTraversalWitness {
  private struct StoredGenerationDescriptor {
    let boundary: CloudTraversalBoundary
    let databaseInstanceIdentifier: String
  }

  /// Rejects descriptor rollback and reuse against the append-only lineage
  /// ledger. This remains effective after an unfinished traversal is canceled.
  static func validateGenerationFence(
    _ db: Database, boundary: CloudTraversalBoundary
  ) throws {
    let descriptors = try storedGenerationDescriptors(
      db, accountIdentifier: boundary.accountIdentifier)
    if let current = descriptors.map(\.boundary.generation).max(),
      boundary.generation < current
    {
      throw CloudTraversalStateError.staleGeneration(
        current: current, attempted: boundary.generation)
    }
    if descriptors.contains(where: {
      $0.boundary.generation == boundary.generation && $0.boundary != boundary
    }) {
      throw CloudTraversalStateError.generationDescriptorConflict(
        generation: boundary.generation)
    }
    if descriptors.contains(where: {
      $0.boundary.generation != boundary.generation
        && ($0.boundary.zoneIdentifier == boundary.zoneIdentifier
          || $0.boundary.generationIdentifier == boundary.generationIdentifier
          || $0.boundary.readyWitness == boundary.readyWitness)
    }) {
      throw CloudTraversalStateError.generationZoneReuse
    }
  }

  /// Records the descriptor before traversal progress is created. The row is
  /// never removed by traversal cancellation or account switching; only an
  /// explicit physical-database lineage change clears the ledger.
  static func recordGenerationDescriptor(
    _ db: Database, boundary: CloudTraversalBoundary,
    databaseInstanceIdentifier: String,
    observedAt: String = SyncTimestampFormat.syncTimestampNow()
  ) throws {
    try requireTransaction(db)
    try validateDatabaseInstanceIdentifier(databaseInstanceIdentifier)
    try validateTimestamp(observedAt)
    try validateGenerationFence(db, boundary: boundary)
    if let existing = try storedGenerationDescriptor(
      db, accountIdentifier: boundary.accountIdentifier,
      generation: boundary.generation)
    {
      guard existing.boundary == boundary,
        existing.databaseInstanceIdentifier == databaseInstanceIdentifier
      else {
        throw CloudTraversalStateError.generationDescriptorConflict(
          generation: boundary.generation)
      }
      return
    }
    try db.execute(
      sql: """
        INSERT INTO sync_cloudkit_generation_descriptor
            (account_identifier, generation, zone_identifier,
             generation_identifier, ready_witness, tombstone_compaction_cutoff,
             database_instance_id, observed_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
      arguments: [
        boundary.accountIdentifier, boundary.generation,
        boundary.zoneIdentifier, boundary.generationIdentifier,
        boundary.readyWitness, boundary.tombstoneCompactionCutoff,
        databaseInstanceIdentifier, observedAt,
      ])
  }

  static func requireRecordedGenerationDescriptor(
    _ db: Database, boundary: CloudTraversalBoundary,
    databaseInstanceIdentifier: String
  ) throws {
    guard
      let stored = try storedGenerationDescriptor(
        db, accountIdentifier: boundary.accountIdentifier,
        generation: boundary.generation),
      stored.boundary == boundary,
      stored.databaseInstanceIdentifier == databaseInstanceIdentifier
    else { throw CloudTraversalStateError.malformedStoredState }
  }

  private static func storedGenerationDescriptor(
    _ db: Database, accountIdentifier: String, generation: Int
  ) throws -> StoredGenerationDescriptor? {
    guard
      let row = try Row.fetchOne(
        db,
        sql: """
          SELECT account_identifier, generation, zone_identifier,
                 generation_identifier, ready_witness, tombstone_compaction_cutoff,
                 database_instance_id, observed_at
          FROM sync_cloudkit_generation_descriptor
          WHERE account_identifier = ? AND generation = ?
          """,
        arguments: [accountIdentifier, generation])
    else { return nil }
    return try decodeGenerationDescriptor(db, row: row)
  }

  private static func storedGenerationDescriptors(
    _ db: Database, accountIdentifier: String
  ) throws -> [StoredGenerationDescriptor] {
    try Row.fetchAll(
      db,
      sql: """
        SELECT account_identifier, generation, zone_identifier,
               generation_identifier, ready_witness, tombstone_compaction_cutoff,
               database_instance_id, observed_at
        FROM sync_cloudkit_generation_descriptor
        WHERE account_identifier = ?
        ORDER BY generation ASC
        """,
      arguments: [accountIdentifier]
    ).map { try decodeGenerationDescriptor(db, row: $0) }
  }

  private static func decodeGenerationDescriptor(
    _ db: Database, row: Row
  ) throws -> StoredGenerationDescriptor {
    do {
      let boundary = try CloudTraversalBoundary(
        accountIdentifier: row["account_identifier"],
        zoneIdentifier: row["zone_identifier"], generation: row["generation"],
        generationIdentifier: row["generation_identifier"],
        readyWitness: row["ready_witness"],
        tombstoneCompactionCutoff: row["tombstone_compaction_cutoff"])
      let databaseInstanceIdentifier: String = row["database_instance_id"]
      let observedAt: String = row["observed_at"]
      try validateDatabaseInstanceIdentifier(databaseInstanceIdentifier)
      try validateTimestamp(observedAt)
      try requireCurrentDatabase(db, storedIdentifier: databaseInstanceIdentifier)
      return StoredGenerationDescriptor(
        boundary: boundary,
        databaseInstanceIdentifier: databaseInstanceIdentifier)
    } catch let error as CloudTraversalStateError {
      throw error
    } catch {
      throw CloudTraversalStateError.malformedStoredState
    }
  }
}
