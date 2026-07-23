import Foundation
import GRDB
import LorvexDomain

/// One row from the `tags` table.
///
/// `createdAt` / `updatedAt` are parsed ``SyncTimestamp`` rather than bare
/// strings so row orderings flow through the parsed millisecond instant
/// rather than lex-compared text.
public struct TagRow: Sendable, Equatable {
  public let id: String
  public let displayName: String
  public let lookupKey: String
  public let color: String?
  public let createdAt: SyncTimestamp
  public let updatedAt: SyncTimestamp
  public let version: String
}

/// One `task_tags` edge row, captured before a delete/merge so the calling
/// surface can emit the matching sync tombstone (a Delete envelope carries a
/// pre-delete snapshot the live row no longer provides once it is gone).
public struct TaskTagEdge: Sendable, Equatable {
  public let taskId: String
  public let tagId: String
  public let version: String
  public let createdAt: String

  public init(taskId: String, tagId: String, version: String, createdAt: String) {
    self.taskId = taskId
    self.tagId = tagId
    self.version = version
    self.createdAt = createdAt
  }
}

/// Outcome of ``TagRepo/mergeTag(_:sourceId:targetId:version:now:)``.
public struct TagMergeRepoResult: Sendable, Equatable {
  /// Every `task_tags` row that pointed at the source tag before the merge —
  /// the re-pointed set, used by the surface for affected-task counts and
  /// per-edge source tombstones.
  public let sourceEdges: [TaskTagEdge]

  /// IDs of the source tag's tasks that already carried the target tag, so the
  /// source link was de-duplicated (dropped) rather than re-pointed onto a new
  /// target row.
  public let dedupedTaskIds: [String]

  public init(sourceEdges: [TaskTagEdge], dedupedTaskIds: [String]) {
    self.sourceEdges = sourceEdges
    self.dedupedTaskIds = dedupedTaskIds
  }
}

/// `tags`-table read/write operations.
///
/// Tag-name matching always flows through ``LorvexDomain/normalizeLookupKey(_:)``;
/// no ad-hoc lowercasing elsewhere.
public enum TagRepo {

  static let selectColumns =
    "id, display_name, lookup_key, color, created_at, updated_at, version"

  static func rowToTag(_ row: Row) throws -> TagRow {
    let rawCreated: String = row[4]
    let rawUpdated: String = row[5]
    guard let createdAt = SyncTimestamp.parse(rawCreated) else {
      throw DatabaseError(
        resultCode: .SQLITE_MISMATCH,
        message: "tags.created_at is not a canonical sync timestamp: \(rawCreated)")
    }
    guard let updatedAt = SyncTimestamp.parse(rawUpdated) else {
      throw DatabaseError(
        resultCode: .SQLITE_MISMATCH,
        message: "tags.updated_at is not a canonical sync timestamp: \(rawUpdated)")
    }
    return TagRow(
      id: row[0],
      displayName: row[1],
      lookupKey: row[2],
      color: row[3],
      createdAt: createdAt,
      updatedAt: updatedAt,
      version: row[6])
  }

  /// Look up a tag by its current `lookup_key` (exact match). Deterministic
  /// `ORDER BY id ASC LIMIT 1` tiebreaks against the brief race window where
  /// two devices emit the same key before the merge sweep collapses them —
  /// matches the merger's "min id wins" rule.
  static func getTagByLookupKey(_ db: Database, lookupKey: String) throws -> TagRow? {
    let row = try Row.fetchOne(
      db,
      sql: """
        SELECT \(selectColumns) FROM tags \
        WHERE lookup_key = ? ORDER BY id ASC LIMIT 1
        """,
      arguments: [lookupKey])
    guard let row else { return nil }
    return try rowToTag(row)
  }

  /// Look up a tag by display name. Normalizes the input to a `lookup_key`
  /// first, then queries the current `lookup_key` column. Returns `nil`
  /// when no row matches.
  public static func getTagByName(_ db: Database, name: String) throws -> TagRow? {
    let key = normalizeLookupKey(name)
    return try getTagByLookupKey(db, lookupKey: key)
  }

  /// Resolve a tag by display name, or create it if it does not exist.
  /// Returns `(tagId, wasCreated)`.
  ///
  /// `version` is the HLC string to stamp on a newly-created row. `now` is
  /// the canonical sync timestamp the caller staged upstream so the entire
  /// logical write shares one timestamp.
  @discardableResult
  public static func resolveOrCreateTag(
    _ db: Database, displayName: String, version: String, now: String
  ) throws -> (id: String, wasCreated: Bool) {
    let lookupKey = normalizeLookupKey(displayName)

    if let existing = try getTagByLookupKey(db, lookupKey: lookupKey) {
      return (existing.id, false)
    }

    let id = EntityID.newEntityIDString()
    try db.execute(
      sql: """
        INSERT INTO tags (id, display_name, lookup_key, created_at, updated_at, version) \
        VALUES (?, ?, ?, ?, ?, ?)
        """,
      arguments: [id, displayName, lookupKey, now, now, version])
    return (id, true)
  }

  /// Rename an existing tag, updating `display_name` and `lookup_key`.
  ///
  /// LWW-gated on `version > tags.version` (strict greater). Throws
  /// ``StoreError/notFound(entity:id:)`` when the tag id does not exist,
  /// and ``StoreError/staleVersion(entity:id:)`` when the row exists but
  /// the supplied `version` is not strictly greater.
  public static func renameTag(
    _ db: Database, tagId: TagId, newDisplayName: String, version: String, now: String
  ) throws {
    let newLookupKey = normalizeLookupKey(newDisplayName)
    try db.execute(
      sql: """
        UPDATE tags SET display_name = ?, lookup_key = ?, updated_at = ?, version = ? \
        WHERE id = ? AND ? > version
        """,
      arguments: [newDisplayName, newLookupKey, now, version, tagId.rawValue, version])
    if db.changesCount > 0 { return }

    // Distinguish missing row from stale-version no-op.
    let exists =
      try Int.fetchOne(
        db, sql: "SELECT 1 FROM tags WHERE id = ?", arguments: [tagId.rawValue]) != nil
    if !exists {
      throw StoreError.notFound(entity: EntityName.tag, id: tagId.rawValue)
    }
    throw StoreError.staleVersion(entity: EntityName.tag, id: tagId.rawValue)
  }

  /// Every `task_tags` edge pointing at `tagId`, ordered `task_id ASC` for a
  /// deterministic tombstone / enqueue order. Captured by the surface BEFORE a
  /// tag delete or merge so each removed edge can be tombstoned for sync.
  public static func taskTagEdges(_ db: Database, tagId: TagId) throws -> [TaskTagEdge] {
    try Row.fetchAll(
      db,
      sql: """
        SELECT task_id, version, created_at FROM task_tags \
        WHERE tag_id = ? ORDER BY task_id ASC
        """,
      arguments: [tagId.rawValue]
    ).map {
      TaskTagEdge(taskId: $0[0], tagId: tagId.rawValue, version: $0[1], createdAt: $0[2])
    }
  }

  /// Hard-delete a tag row by id. Its `task_tags` edges are removed by the
  /// schema's `ON DELETE CASCADE`; a syncing caller must capture
  /// ``taskTagEdges(_:tagId:)`` for the per-edge tombstones BEFORE calling this.
  /// Returns the number of `tags` rows deleted (0 when the id was absent, else 1).
  @discardableResult
  public static func deleteTag(_ db: Database, tagId: TagId) throws -> Int {
    try db.execute(sql: "DELETE FROM tags WHERE id = ?", arguments: [tagId.rawValue])
    return db.changesCount
  }

  /// Fold the source tag into the target: re-point every `task_tags` row from
  /// `sourceId` onto `targetId` (de-duplicating when a task already carries the
  /// target), LWW-fold each edge against `version` / `now`, then delete the source
  /// tag and its now-orphaned source edges. A future-stamped source or target edge
  /// is preserved so the caller's subsequent outbox stamp surfaces a typed
  /// supersession and replays the whole mutation on the detached HLC lane.
  ///
  /// Uses the same re-point upsert SQL as the sync-apply duplicate-tag merger
  /// (``LorvexSync`` `ApplyTagMerge.mergeDuplicateTags`) for a caller-chosen
  /// source/target pair, minus the apply-only HLC-minting / conflict-log
  /// machinery. Returns the pre-merge source edges + the de-duplicated task ids
  /// so the calling surface can emit the edge upsert / tombstone envelopes and a
  /// rich response. Caller must guarantee `sourceId != targetId`.
  public static func mergeTag(
    _ db: Database, sourceId: TagId, targetId: TagId, version: String, now: String
  ) throws -> TagMergeRepoResult {
    let sourceEdges = try taskTagEdges(db, tagId: sourceId)
    // Source tasks that already carry the target tag — their duplicate source
    // link collapses onto the existing target row rather than re-pointing.
    let dedupedTaskIds = try String.fetchAll(
      db,
      sql: """
        SELECT task_id FROM task_tags \
        WHERE tag_id = ? AND task_id IN (SELECT task_id FROM task_tags WHERE tag_id = ?) \
        ORDER BY task_id ASC
        """,
      arguments: [targetId.rawValue, sourceId.rawValue])
    // Re-point: insert a target edge for every source task, collapsing onto an
    // existing target edge via ON CONFLICT and re-stamping it at the merge
    // version so peers converge.
    try db.execute(
      sql: """
        INSERT INTO task_tags (task_id, tag_id, created_at, version) \
         SELECT task_id, :target_id, \
                CASE WHEN version > :version THEN created_at ELSE :now END, \
                max(version, :version) \
           FROM task_tags WHERE tag_id = :source_id \
         ON CONFLICT(task_id, tag_id) DO UPDATE SET \
             created_at = CASE \
                 WHEN excluded.version > task_tags.version THEN excluded.created_at \
                 ELSE task_tags.created_at END, \
             version = max(task_tags.version, excluded.version)
        """,
      arguments: [
        "target_id": targetId.rawValue, "now": now, "version": version,
        "source_id": sourceId.rawValue,
      ])
    try db.execute(sql: "DELETE FROM task_tags WHERE tag_id = ?", arguments: [sourceId.rawValue])
    try db.execute(sql: "DELETE FROM tags WHERE id = ?", arguments: [sourceId.rawValue])
    return TagMergeRepoResult(sourceEdges: sourceEdges, dedupedTaskIds: dedupedTaskIds)
  }
}
