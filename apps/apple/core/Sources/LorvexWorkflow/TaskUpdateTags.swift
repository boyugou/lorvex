import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Task-tag edge add/remove for single-row task updates. Diff the
/// prepared tag set against the row's current tags; emit per-edge
/// upserts (with `tags` row creation when the tag is new) and per-edge
/// deletes (carrying the pre-delete payload every surface needs to
/// enqueue an outbox tombstone).
public enum TaskUpdateTags {

  public static func replaceTaskTags(
    _ db: Database,
    hlc: HlcSession,
    taskId: TaskId,
    newTags: [String],
    effects: inout TaskUpdateSyncEffects
  ) throws {
    let oldTagRows = try findTaskTagRows(db, taskId: taskId)
    let oldSet = Set(oldTagRows.map { $0.displayName })
    let newSet = Set(newTags)

    for removed in oldSet.subtracting(newSet) {
      guard let row = oldTagRows.first(where: { $0.displayName == removed }) else {
        continue
      }
      try db.execute(
        sql: "DELETE FROM task_tags WHERE task_id = ? AND tag_id = ?",
        arguments: [taskId.asString, row.tagId])
      let edgeId = TaskTagEdgeId(taskId: taskId, tagId: TagId(trusted: row.tagId))
      effects.taskTagEdgeDeleteIds.append(edgeId.asString)
      effects.deletedTaskTagEdges.append(
        TaskTagEdgeDelete(
          taskId: taskId.asString,
          tagId: row.tagId,
          version: row.version,
          createdAt: row.createdAt))
    }

    let now = SyncTimestampFormat.syncTimestampNow()
    for added in newSet.subtracting(oldSet) {
      let tagVersion = hlc.nextVersionString()
      let (tagId, created) = try TagRepo.resolveOrCreateTag(
        db, displayName: added, version: tagVersion, now: now)
      if created {
        effects.tagUpsertIds.append(tagId)
      }
      let edgeVersion = hlc.nextVersionString()
      try db.execute(
        sql: "INSERT OR IGNORE INTO task_tags (task_id, tag_id, version, created_at) "
          + "VALUES (?, ?, ?, ?)",
        arguments: [taskId.asString, tagId, edgeVersion, now])
      let edgeId = TaskTagEdgeId(taskId: taskId, tagId: TagId(trusted: tagId))
      effects.taskTagEdgeUpsertIds.append(edgeId.asString)
    }
  }

  /// Read the row's current tag display names: the order the tags were
  /// added, alphabetical (`lookup_key`) within one write — same-transaction
  /// edges share `created_at`, so the tie-break must be deterministic.
  public static func findTaskTags(
    _ db: Database, taskId: TaskId
  ) throws -> [String] {
    try String.fetchAll(
      db,
      sql: "SELECT t.display_name FROM task_tags tt "
        + "JOIN tags t ON t.id = tt.tag_id "
        + "WHERE tt.task_id = ? ORDER BY tt.created_at ASC, t.lookup_key ASC",
      arguments: [taskId.asString])
  }

  struct TagEdgeRow {
    let displayName: String
    let tagId: String
    let version: String
    let createdAt: String
  }

  static func findTaskTagRows(
    _ db: Database, taskId: TaskId
  ) throws -> [TagEdgeRow] {
    let rows = try Row.fetchAll(
      db,
      sql: "SELECT t.display_name, t.id, tt.version, tt.created_at "
        + "FROM task_tags tt JOIN tags t ON t.id = tt.tag_id "
        + "WHERE tt.task_id = ? ORDER BY tt.created_at ASC, tt.tag_id ASC",
      arguments: [taskId.asString])
    return rows.map { row in
      TagEdgeRow(
        displayName: row[0] as String,
        tagId: row[1] as String,
        version: row[2] as String,
        createdAt: row[3] as String)
    }
  }

  /// Pure resolver for `tags_set` / `tags_add` / `tags_remove` against
  /// the row's current tag set. `tags_set` short-circuits to the
  /// replacement value (normalized). For the patch path, removes run
  /// before adds. Removes match by ``LorvexDomain/normalizeLookupKey(_:)``,
  /// not raw display-name equality.
  public static func applyTagPatch(
    currentTags: [String],
    tagsSet: [String]?,
    tagsAdd: [String]?,
    tagsRemove: [String]?
  ) -> [String] {
    if let tags = tagsSet {
      return normalizeTags(tags)
    }
    var tags = normalizeTags(currentTags)
    let removeKeys = Set(
      normalizeTags(tagsRemove ?? []).map { normalizeLookupKey($0) })
    if !removeKeys.isEmpty {
      tags.removeAll(where: { removeKeys.contains(normalizeLookupKey($0)) })
    }
    if let toAdd = tagsAdd {
      tags.append(contentsOf: toAdd)
    }
    return normalizeTags(tags)
  }

  private static func normalizeTags(_ tags: [String]) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    out.reserveCapacity(tags.count)
    for tag in tags {
      let trimmed = tag.trimmingCharacters(in: .whitespaces)
      if !trimmed.isEmpty && seen.insert(normalizeLookupKey(trimmed)).inserted {
        out.append(trimmed)
      }
    }
    return out
  }
}
