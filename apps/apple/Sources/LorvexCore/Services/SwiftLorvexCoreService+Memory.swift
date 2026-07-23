import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

/// Memory surface over the pure-Swift core.
///
/// Memory is a last-write-wins AI-managed key→value store. Mutations funnel
/// through `LorvexWorkflow.MemoryOps` (LWW-gated upsert / rename / delete); reads
/// go to `MemoryRepo`. Result mapping reuses `SwiftLorvexMemoryDeserializers`.
extension SwiftLorvexCoreService {

  // MARK: - Memory reads

  public func loadMemory() async throws -> MemorySnapshot {
    try read { db in
      let keys = try String.fetchAll(
        db, sql: "SELECT key FROM memories ORDER BY key ASC")
      let entries = try keys.compactMap { key -> MemoryEntry? in
        guard let row = try MemoryRepo.getMemoryEntry(db, key: key) else { return nil }
        return SwiftLorvexMemoryDeserializers.memoryEntry(
          key: row.key, content: row.content, updatedAt: row.updatedAt.asString)
      }
      return MemorySnapshot(entries: entries)
    }
  }

  // MARK: - Memory writes

  public func upsertMemory(key: String, content: String) async throws -> MemoryEntry {
    return try withWrite { db, hlc, deviceId in
      let existing = try Row.fetchOne(
        db, sql: "SELECT id, version FROM memories WHERE key = ?", arguments: [key])
      let existingId: String? = existing?["id"]
      let existingVersion: String? = existing?["version"]
      let version = try VersionFloor.mint(
        hlc: hlc, existingVersion: existingVersion,
        entityType: EntityName.memory, entityId: existingId ?? key)
      let now = SyncTimestampFormat.syncTimestampNow()
      guard
        let mutation = try MemoryOps.upsertMemoryEntry(
          db, key: key, content: content, version: version, now: now)
      else {
        let observed = try Row.fetchOne(
          db, sql: "SELECT id, version FROM memories WHERE key = ?", arguments: [key])
        guard let observed else {
          throw StoreError.invariant("memory '\(key)' vanished during upsert")
        }
        let observedId: String = observed["id"]
        let observedVersion: String = observed["version"]
        throw StoreError.versionSuperseded(
          entityType: EntityName.memory, entityId: observedId,
          attemptedVersion: version, existingVersion: observedVersion)
      }
      guard let row = try MemoryRepo.getMemoryEntry(db, key: key) else {
        throw LorvexCoreError.unsupportedOperation("Memory '\(key)' missing after upsert.")
      }
      // Route the outbound envelope on the row's opaque `id` (resolved by
      // MemoryOps), never the human `key`, so the CloudKit `entity_id` is opaque.
      try self.enqueueUpsert(
        db, hlc: hlc, deviceId: deviceId, kind: .memory, entityId: mutation.memoryId)
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: SyncNaming.opUpsert, entityType: EntityName.memory, entityId: key,
          summary: "Upserted memory '\(key)'"),
        deviceId: deviceId)
      return SwiftLorvexMemoryDeserializers.memoryEntry(
        key: row.key, content: row.content, updatedAt: row.updatedAt.asString)
    }
  }

  public func renameMemory(oldKey: String, newKey: String, content: String?) async throws
    -> MemoryEntry
  {
    let old = oldKey.trimmingCharacters(in: .whitespacesAndNewlines)
    let new = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !new.isEmpty else {
      throw LorvexCoreError.validation(field: "new_key", message: "A memory key is required.")
    }
    return try withWrite { db, hlc, deviceId in
      guard try MemoryRepo.getMemoryEntry(db, key: old) != nil else {
        throw LorvexCoreError.notFound(entity: .memory, id: old)
      }
      // Reject a rename onto a DIFFERENT existing memory: memory keys are distinct
      // semantic sections, so silently merging one under the other would LWW-clobber
      // its content with no explicit intent. (A same-key save is a content edit, not
      // a collision — the conflict is the same row.) Cross-device collisions still
      // converge via the ApplyMemoryMerge min-id path.
      let oldId = try String.fetchOne(
        db, sql: "SELECT id FROM memories WHERE key = ?", arguments: [old])
      if new != old,
        let conflictId = try String.fetchOne(
          db, sql: "SELECT id FROM memories WHERE key = ?", arguments: [new]),
        conflictId != oldId
      {
        throw LorvexCoreError.conflict(
          message: "A memory named '\(new)' already exists. Combine their content under one key "
            + "instead of renaming '\(old)' onto it.")
      }
      let version = hlc.nextVersionString()
      let now = SyncTimestampFormat.syncTimestampNow()
      guard
        let mutation = try MemoryOps.renameMemoryEntry(
          db, oldKey: old, newKey: new, content: content, version: version, now: now)
      else {
        throw LorvexCoreError.notFound(entity: .memory, id: old)
      }
      guard let row = try MemoryRepo.getMemoryEntry(db, key: new) else {
        throw LorvexCoreError.unsupportedOperation("Memory '\(new)' missing after rename.")
      }
      // Route the outbound envelope on the row's opaque `id` (unchanged by the
      // rename), never the human key, so the CloudKit entity_id is stable and the
      // rename is one in-place record edit, not a create + tombstone.
      try self.enqueueUpsert(
        db, hlc: hlc, deviceId: deviceId, kind: .memory, entityId: mutation.memoryId)
      let renamed = new != old
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: renamed ? "rename" : SyncNaming.opUpsert,
          entityType: EntityName.memory, entityId: new,
          summary: renamed ? "Renamed memory '\(old)' to '\(new)'" : "Updated memory '\(new)'"),
        deviceId: deviceId)
      return SwiftLorvexMemoryDeserializers.memoryEntry(
        key: row.key, content: row.content, updatedAt: row.updatedAt.asString)
    }
  }

  public func importMemoryEntry(
    key: String,
    content: String,
    updatedAt: String?
  ) async throws -> MemoryEntry {
    let canonicalUpdatedAt = try Self.canonicalImportTimestamp(
      updatedAt, field: "memory updatedAt", fallback: SyncTimestampFormat.syncTimestampNow())
    return try withWrite { db, hlc, deviceId in
      let existing = try Row.fetchOne(
        db, sql: "SELECT id, version FROM memories WHERE key = ?", arguments: [key])
      let existingId: String? = existing?["id"]
      let existingVersion: String? = existing?["version"]
      let version = try VersionFloor.mint(
        hlc: hlc, existingVersion: existingVersion,
        entityType: EntityName.memory, entityId: existingId ?? key)
      guard
        let mutation = try MemoryOps.upsertMemoryEntry(
          db, key: key, content: content, version: version, now: canonicalUpdatedAt)
      else {
        let observed = try Row.fetchOne(
          db, sql: "SELECT id, version FROM memories WHERE key = ?", arguments: [key])
        guard let observed else {
          throw StoreError.invariant("memory '\(key)' vanished during import")
        }
        let observedId: String = observed["id"]
        let observedVersion: String = observed["version"]
        throw StoreError.versionSuperseded(
          entityType: EntityName.memory, entityId: observedId,
          attemptedVersion: version, existingVersion: observedVersion)
      }
      guard let row = try MemoryRepo.getMemoryEntry(db, key: key) else {
        throw LorvexCoreError.unsupportedOperation("Memory '\(key)' missing after import.")
      }
      try self.enqueueUpsert(
        db, hlc: hlc, deviceId: deviceId, kind: .memory, entityId: mutation.memoryId)
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: SyncNaming.opUpsert, entityType: EntityName.memory, entityId: key,
          summary: "Imported memory '\(key)'"),
        deviceId: deviceId)
      return SwiftLorvexMemoryDeserializers.memoryEntry(
        key: row.key, content: row.content, updatedAt: row.updatedAt.asString)
    }
  }

  public func importMemoryEntry(_ entry: ExportMemoryEntry) async throws -> MemoryEntry {
    let key = try Self.requiredMemoryImportText(entry.key, field: "memory key")
    let now = try Self.canonicalImportTimestamp(
      entry.updatedAt, field: "memory updatedAt", fallback: SyncTimestampFormat.syncTimestampNow())
    let content = try Memory.normalizeContent(entry.content)
    return try withWrite { db, hlc, deviceId in
      try self.upsertImportedMemoryInTx(
        db, hlc: hlc, deviceId: deviceId, key: key, entry: entry, content: content, now: now)
    }
  }

  public func importMemoryEntryIfAbsent(_ entry: ExportMemoryEntry) async throws -> (
    MemoryEntry?, Bool
  ) {
    let key = try Self.requiredMemoryImportText(entry.key, field: "memory key")
    let now = try Self.canonicalImportTimestamp(
      entry.updatedAt, field: "memory updatedAt", fallback: SyncTimestampFormat.syncTimestampNow())
    let content = try Memory.normalizeContent(entry.content)
    return try withWrite { db, hlc, deviceId in
      // Presence is keyed on the human `key` (the UNIQUE conflict target the
      // upsert lands on); a live row means a concurrent write already holds it, so
      // skip rather than overwrite it. The tombstone is keyed on the opaque memory
      // id (the sync routing identity a delete tombstones), so a memory the user
      // deleted after the backup is not resurrected at a fresh dominating import
      // HLC. Both checks share this write lock with the write.
      if try Int.fetchOne(db, sql: "SELECT 1 FROM memories WHERE key = ?", arguments: [key]) != nil
      {
        return (nil, false)
      }
      let memoryID = try Self.memoryImportID(db, key: key, exportedID: entry.id)
      if try Tombstone.isTombstoned(db, entityType: EntityName.memory, entityId: memoryID) {
        return (nil, false)
      }
      let result = try self.upsertImportedMemoryInTx(
        db, hlc: hlc, deviceId: deviceId, key: key, entry: entry, content: content, now: now)
      return (result, true)
    }
  }

  /// Upsert one imported memory (its opaque id + latest content) inside the
  /// caller's transaction. Shared by ``importMemoryEntry(_:)`` (overwrite-on-
  /// reimport) and ``importMemoryEntryIfAbsent(_:)`` (skip-if-present/tombstoned);
  /// the latter guards the key before calling.
  func upsertImportedMemoryInTx(
    _ db: Database, hlc: HlcSession, deviceId: String, key: String, entry: ExportMemoryEntry,
    content: String, now: String
  ) throws -> MemoryEntry {
    let memoryID = try Self.memoryImportID(db, key: key, exportedID: entry.id)
    let existingVersion = try String.fetchOne(
      db, sql: "SELECT version FROM memories WHERE key = ?", arguments: [key])
    let memoryVersion = try VersionFloor.mint(
      hlc: hlc, existingVersion: existingVersion,
      entityType: EntityName.memory, entityId: memoryID)
    try db.execute(
      sql: """
        INSERT INTO memories (id, key, content, version, updated_at)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(key) DO UPDATE SET
          content = excluded.content,
          version = excluded.version,
          updated_at = excluded.updated_at
        WHERE excluded.version > memories.version
        """,
      arguments: [memoryID, key, content, memoryVersion, now])
    if db.changesCount == 0 {
      let observed = try Row.fetchOne(
        db, sql: "SELECT id, version FROM memories WHERE key = ?", arguments: [key])
      guard let observed else {
        throw StoreError.invariant("memory '\(key)' vanished during import")
      }
      let observedId: String = observed["id"]
      let observedVersion: String = observed["version"]
      throw StoreError.versionSuperseded(
        entityType: EntityName.memory, entityId: observedId,
        attemptedVersion: memoryVersion, existingVersion: observedVersion)
    }

    try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .memory, entityId: memoryID)
    try self.writeChangelogRow(
      db,
      ChangelogEntry(
        operation: SyncNaming.opUpsert, entityType: EntityName.memory, entityId: key,
        summary: "Imported memory '\(key)'"),
      deviceId: deviceId)
    guard let row = try MemoryRepo.getMemoryEntry(db, key: key) else {
      throw LorvexCoreError.unsupportedOperation("Memory '\(key)' missing after import.")
    }
    return SwiftLorvexMemoryDeserializers.memoryEntry(
      key: row.key, content: row.content, updatedAt: row.updatedAt.asString)
  }

  private static func memoryImportID(_ db: Database, key: String, exportedID: String?) throws
    -> String
  {
    if let existing = try String.fetchOne(
      db, sql: "SELECT id FROM memories WHERE key = ?", arguments: [key])
    {
      return existing
    }
    if let exportedID = exportedID?.trimmingCharacters(in: .whitespacesAndNewlines),
      !exportedID.isEmpty,
      let canonical = canonicalMemoryImportID(exportedID, kind: .memory)
    {
      return canonical
    }
    return EntityID.newEntityIDString()
  }

  /// Imported memory ids are sync routing identities. Reuse an export id only
  /// when it already has the canonical wire shape; a bad export falls back to a
  /// fresh opaque id rather than tainting `memories.id` and failing later at
  /// outbox enqueue.
  private static func canonicalMemoryImportID(_ raw: String, kind: EntityKind) -> String? {
    let canonical = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if case .success = SyncEntityId.validateForKind(kind, canonical) {
      return canonical
    }
    return nil
  }

  private static func requiredMemoryImportText(_ raw: String, field: String) throws -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw LorvexCoreError.unsupportedOperation("A \(field) is required.")
    }
    return trimmed
  }

  public func deleteMemory(key: String) async throws -> Bool {
    try deleteMemoryWithReceipt(key: key).deleted
  }

  public func deleteMemoryForMcp(key: String) async throws -> McpDeletionReceipt<MemoryEntry> {
    try deleteMemoryWithReceipt(key: key)
  }

  private func deleteMemoryWithReceipt(key: String) throws -> McpDeletionReceipt<MemoryEntry> {
    try withWrite { db, hlc, deviceId in
      let previous = try MemoryRepo.getMemoryEntry(db, key: key).map { row in
        SwiftLorvexMemoryDeserializers.memoryEntry(
          key: row.key, content: row.content, updatedAt: row.updatedAt.asString)
      }
      let version = hlc.nextVersionString()
      let result = try MemoryOps.deleteMemoryEntry(db, key: key, version: version)
      if let result {
        try self.enqueueDelete(
          db, hlc: hlc, deviceId: deviceId, kind: .memory, entityId: result.memoryId,
          payload: result.preDeletePayload ?? .object([:]))
        try self.writeChangelogRow(
          db,
          ChangelogEntry(
            operation: SyncNaming.opDelete, entityType: EntityName.memory, entityId: key,
            summary: "Deleted memory '\(key)'"),
          deviceId: deviceId)
      }
      return McpDeletionReceipt(previous: result == nil ? nil : previous)
    }
  }
}

private extension String {
  var nilIfMemoryBlank: String? {
    trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
  }
}
