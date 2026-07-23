import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync

extension SwiftLorvexCoreService {
  public func importTag(_ tag: ExportTag) async throws {
    let displayName = try Self.requiredTagImportText(tag.displayName, field: "tag displayName")
    let lookupKey = normalizeLookupKey(displayName)
    let now = SyncTimestampFormat.syncTimestampNow()
    try withWrite { db, hlc, deviceId in
      let id = try Self.tagImportID(db, exportedID: tag.id, lookupKey: lookupKey)
      try self.writeImportedTagInTx(
        db, hlc: hlc, deviceId: deviceId, id: id, displayName: displayName, lookupKey: lookupKey,
        tag: tag, now: now)
    }
  }

  public func importTagIfAbsent(_ tag: ExportTag) async throws -> Bool {
    let displayName = try Self.requiredTagImportText(tag.displayName, field: "tag displayName")
    let lookupKey = normalizeLookupKey(displayName)
    let now = SyncTimestampFormat.syncTimestampNow()
    return try withWrite { db, hlc, deviceId in
      let id = try Self.tagImportID(db, exportedID: tag.id, lookupKey: lookupKey)
      // A tag resolves by exported id first, then by `lookup_key` (merge-by-name):
      // either match means a live tag already exists, so a non-destructive restore
      // skips rather than overwriting a tag a peer or concurrent create authored.
      // A tombstone means the user deleted this tag after the backup, so skip
      // rather than resurrect it at a fresh dominating import HLC. Both checks
      // share this write lock with the insert.
      if try Int.fetchOne(
        db, sql: "SELECT 1 FROM tags WHERE id = ? OR lookup_key = ? LIMIT 1",
        arguments: [id, lookupKey]) != nil
      {
        return false
      }
      if try Tombstone.isTombstoned(db, entityType: EntityName.tag, entityId: id) {
        return false
      }
      try self.writeImportedTagInTx(
        db, hlc: hlc, deviceId: deviceId, id: id, displayName: displayName, lookupKey: lookupKey,
        tag: tag, now: now)
      return true
    }
  }

  /// Insert one imported tag row and enqueue its sync envelope + changelog,
  /// inside the caller's transaction. `id` is the already-resolved tag identity
  /// (existing by id, existing by `lookup_key`, or the exported id). Shared by
  /// ``importTag(_:)`` (overwrite-on-reimport) and ``importTagIfAbsent(_:)``
  /// (skip-if-present/tombstoned).
  func writeImportedTagInTx(
    _ db: Database, hlc: HlcSession, deviceId: String, id: String, displayName: String,
    lookupKey: String, tag: ExportTag, now: String
  ) throws {
    // LWW-gate the upsert on `version` so an import never REGRESSES a row a
    // peer stamped with a future HLC; on a refused conflict `staleVersion`
    // routes through the `runWriteAttempt` retry so the import wins at a
    // dominating version. See `importCalendarEvent` for the full rationale.
    try db.execute(
      sql: """
        INSERT INTO tags (id, display_name, lookup_key, color, version, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          display_name = excluded.display_name,
          lookup_key = excluded.lookup_key,
          color = excluded.color,
          version = excluded.version,
          created_at = excluded.created_at,
          updated_at = excluded.updated_at
        WHERE excluded.version > tags.version
        """,
      arguments: [
        id, displayName, lookupKey, tag.color, hlc.nextVersionString(),
        try Self.canonicalImportTimestamp(tag.createdAt, field: "tag createdAt", fallback: now),
        try Self.canonicalImportTimestamp(tag.updatedAt, field: "tag updatedAt", fallback: now),
      ])
    if db.changesCount == 0 {
      throw StoreError.staleVersion(entity: EntityName.tag, id: id)
    }
    try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .tag, entityId: id)
    try self.writeChangelogRow(
      db,
      ChangelogEntry(
        operation: SyncNaming.opUpsert, entityType: EntityName.tag,
        entityId: id, summary: "Imported tag '\(displayName)'"),
      deviceId: deviceId)
  }

  private static func tagImportID(_ db: Database, exportedID: String, lookupKey: String) throws
    -> String
  {
    let trimmedID = exportedID.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedID.isEmpty,
      let existingByID = try String.fetchOne(
        db, sql: "SELECT id FROM tags WHERE id = ?", arguments: [trimmedID])
    {
      return existingByID
    }
    if let existingByLookup = try String.fetchOne(
      db,
      sql: "SELECT id FROM tags WHERE lookup_key = ? ORDER BY id ASC LIMIT 1",
      arguments: [lookupKey])
    {
      return existingByLookup
    }
    guard !trimmedID.isEmpty else {
      throw LorvexCoreError.unsupportedOperation("A tag id is required.")
    }
    return trimmedID
  }

  private static func requiredTagImportText(_ raw: String, field: String) throws -> String {
    let trimmed = UnicodeHygiene.sanitizeUserText(raw)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw LorvexCoreError.unsupportedOperation("A \(field) is required.")
    }
    return trimmed
  }

}
