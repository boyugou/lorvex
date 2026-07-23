import Foundation
import GRDB
import LorvexDomain
import LorvexStore

extension CloudTraversalWitness {
  static func requireNoOrphanedTraversalState(_ db: Database) throws {
    let count =
      try Int.fetchOne(
        db,
        sql: """
          SELECT
            (SELECT COUNT(*) FROM sync_cloudkit_authority_witness)
            + (SELECT COUNT(*) FROM sync_cloudkit_generation_descriptor)
            + (SELECT COUNT(*) FROM sync_cloudkit_traversal_progress)
            + (SELECT COUNT(*) FROM sync_cloudkit_traversal_witness)
            + (SELECT COUNT(*) FROM sync_cloudkit_incremental_cursor)
            + (SELECT COUNT(*) FROM sync_authoritative_snapshot)
            + (SELECT COUNT(*) FROM sync_generation_snapshot_staging)
          """) ?? 0
    guard count == 0 else { throw CloudTraversalStateError.malformedStoredState }
  }

  static func requireActiveAccount(
    _ db: Database, accountIdentifier: String
  ) throws {
    guard let binding = try accountBinding(db) else {
      throw CloudTraversalStateError.noAccountBinding
    }
    guard binding.accountIdentifier == accountIdentifier else {
      throw CloudTraversalStateError.accountBoundaryMismatch(
        expected: binding.accountIdentifier, actual: accountIdentifier)
    }
  }

  static func currentDatabaseIdentifier(_ db: Database) throws -> String {
    let identifier = try SyncCheckpoints.getOrCreateDatabaseInstanceId(db)
    try validateDatabaseInstanceIdentifier(identifier)
    return identifier
  }

  static func requireTransaction(_ db: Database) throws {
    guard db.isInsideTransaction else {
      throw CloudTraversalStateError.transactionRequired
    }
  }

  static func requireCurrentDatabase(
    _ db: Database, storedIdentifier: String
  ) throws {
    guard
      let currentIdentifier = try SyncCheckpoints.get(
        db, key: SyncCheckpoints.keyDatabaseInstanceId)
    else { throw CloudTraversalStateError.invalidDatabaseInstanceIdentifier }
    try validateDatabaseInstanceIdentifier(currentIdentifier)
    guard currentIdentifier == storedIdentifier else {
      throw CloudTraversalStateError.databaseInstanceMismatch
    }
  }

  static func validate(_ binding: CloudTraversalAccountBinding) throws {
    try validateAccountIdentifier(binding.accountIdentifier)
    try validateDatabaseInstanceIdentifier(binding.databaseInstanceIdentifier)
    try validateTimestamp(binding.boundAt)
  }

  static func validateAccountIdentifier(_ value: String) throws {
    guard
      CloudTraversalBoundary.validBounded(
        value, maximumBytes: CloudTraversalBoundary.maxAccountIdentifierBytes)
    else { throw CloudTraversalStateError.invalidAccountIdentifier }
  }

  static func validateZoneIdentifier(_ value: String) throws {
    _ = try CloudTraversalBoundary(
      accountIdentifier: "validation", zoneIdentifier: value, generation: 0,
      generationIdentifier: "validation", readyWitness: "validation")
  }

  static func validateDatabaseInstanceIdentifier(_ value: String) throws {
    guard
      CloudTraversalBoundary.validBounded(
        value, maximumBytes: maxDatabaseInstanceIdentifierBytes)
    else { throw CloudTraversalStateError.invalidDatabaseInstanceIdentifier }
  }

  static func validateTraversalIdentifier(_ value: String) throws {
    guard
      CloudTraversalBoundary.validBounded(
        value, maximumBytes: maxTraversalIdentifierBytes)
    else { throw CloudTraversalStateError.invalidTraversalIdentifier }
  }

  static func validateContinuationToken(_ value: Data) throws {
    try CloudTraversalTokenBounds.validate(value)
  }

  static func validateTimestamp(_ value: String) throws {
    guard SyncTimestamp.parse(value)?.asString == value else {
      throw CloudTraversalStateError.invalidTimestamp
    }
  }
}
