import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync

extension SwiftLorvexCoreService {
  static func requireCanonicalImportedUUID(_ value: String, field: String) throws {
    guard SyncEntityId.isCanonicalUuid(value) else {
      throw LorvexCoreError.validation(
        field: field, message: "The backup contains a noncanonical \(field).")
    }
  }

  static func requireUniqueImportedValues(
    _ values: [String], field: String
  ) throws {
    guard Set(values).count == values.count else {
      throw LorvexCoreError.validation(
        field: field, message: "The backup repeats a \(field).")
    }
  }

  /// A synced child identity belongs to exactly one aggregate for its lifetime.
  /// Import may update a child already owned by that same parent, but it must
  /// never reparent another aggregate's row or resurrect identity metadata left
  /// by a delete/future payload.
  static func assertImportedChildIdentityCanWrite(
    _ db: Database, table: String, ownerColumn: String, expectedOwnerID: String,
    entityType: String, entityID: String, field: String
  ) throws {
    ValidationSQL.assertSafeSQLIdentifier(table)
    ValidationSQL.assertSafeSQLIdentifier(ownerColumn)
    if let existingOwner = try String.fetchOne(
      db,
      sql: "SELECT \(ownerColumn) FROM \(table) WHERE id = ?",
      arguments: [entityID])
    {
      guard existingOwner == expectedOwnerID else {
        throw LorvexCoreError.conflict(
          message: "The backup reuses a \(field) that belongs to another record.")
      }
      return
    }
    let tombstoned = try Tombstone.isTombstoned(
      db, entityType: entityType, entityId: entityID)
    let shadowed = try PayloadShadow.getShadow(
      db, entityType: entityType, entityID: entityID) != nil
    let pending = try Int.fetchOne(
      db,
      sql: """
        SELECT 1 FROM sync_outbox
        WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
        LIMIT 1
        """,
      arguments: [entityType, entityID]) != nil
    guard !tombstoned, !shadowed, !pending else {
      throw LorvexCoreError.conflict(
        message: "The backup reuses a deleted or unresolved \(field).")
    }
  }
}
