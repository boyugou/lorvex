import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

extension SwiftLorvexCoreService {
  public func listAllTags() async throws -> [String] {
    try read { db in
      // Only tags attached to at least one non-archived task — honors the
      // documented "tags attached to non-archived tasks" contract and keeps
      // tags whose tasks were all deleted or archived out of the result. Tag
      // rows are intentionally NOT usage-GC'd: a usage-based cross-device tag
      // delete is a delete-vs-concurrent-use hazard, so this read-time filter is
      // the single source of truth for which tags are "live".
      try String.fetchAll(
        db,
        sql: """
          SELECT t.display_name FROM tags t \
          WHERE EXISTS ( \
            SELECT 1 FROM task_tags tt JOIN tasks tk ON tk.id = tt.task_id \
            WHERE tt.tag_id = t.id AND tk.archived_at IS NULL \
          ) \
          ORDER BY t.display_name ASC, t.id ASC
          """)
    }
  }

  public func renameTag(oldTag: String, newTag: String) async throws {
    // Sanitize the new display name (strip bidi / zero-width / control, NFC) so
    // the stored + synced `display_name` cannot carry a rendering-attack payload.
    // The `lookup_key` normalization already sanitizes independently.
    let newTag = UnicodeHygiene.sanitizeUserText(newTag)
    _ = try withWrite { db, hlc, deviceId -> Bool in
      guard let existing = try TagRepo.getTagByName(db, name: oldTag) else {
        throw LorvexCoreError.notFound(entity: .tag, id: oldTag)
      }
      // A rename whose normalized key collides with a *different* existing tag
      // would leave two rows sharing one lookup_key; getTagByLookupKey then
      // collapses to the min-id row, hiding the loser's tasks from getTasksByTag
      // until a sync round-trip. Reject rather than silently duplicate — re-tag
      // the tasks onto the existing tag instead. A case-only change (same
      // lookup_key) is not a collision and proceeds. Cross-device tag merges
      // still arrive via sync apply, which converges duplicates by min-id winner.
      let newLookupKey = normalizeLookupKey(newTag)
      if newLookupKey != existing.lookupKey,
        let conflict = try TagRepo.getTagByName(db, name: newTag),
        conflict.id != existing.id
      {
        throw LorvexCoreError.conflict(
          message: "A tag named '\(newTag)' already exists. Re-tag those tasks onto it "
            + "instead of renaming '\(oldTag)' into it.")
      }
      let version = hlc.nextVersionString()
      let now = SyncTimestampFormat.syncTimestampNow()
      try TagRepo.renameTag(
        db, tagId: TagId(trusted: existing.id), newDisplayName: newTag,
        version: version, now: now)
      try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .tag, entityId: existing.id)
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: "rename", entityType: EntityName.tag, entityId: existing.id,
          summary: "Renamed tag '\(oldTag)' to '\(newTag)'"),
        deviceId: deviceId)
      return true
    }
  }

  public func deleteTag(name: String) async throws -> TagDeletionOutcome {
    try withWrite { db, hlc, deviceId in
      let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else {
        throw LorvexCoreError.validation(field: "name", message: "A tag name is required.")
      }
      guard let existing = try TagRepo.getTagByName(db, name: trimmed) else {
        throw LorvexCoreError.notFound(entity: .tag, id: trimmed)
      }
      let tagId = TagId(trusted: existing.id)
      // Capture the edges + the tag snapshot BEFORE the delete: the `tags` row
      // cascades its `task_tags` rows away (FK ON DELETE CASCADE), and Delete
      // envelopes carry a pre-delete payload the gone row can no longer supply.
      let edges = try TagRepo.taskTagEdges(db, tagId: tagId)
      let snapshot = try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: EntityName.tag, entityId: existing.id)
      // Tombstone each task_tag edge (the cascade drops them silently otherwise).
      for edge in edges {
        let payload = PayloadLoaders.taskTagPayload(
          taskId: edge.taskId, tagId: edge.tagId, version: edge.version, createdAt: edge.createdAt)
        try self.enqueueDelete(
          db, hlc: hlc, deviceId: deviceId, kind: .taskTag,
          entityId: "\(edge.taskId):\(edge.tagId)", payload: payload)
      }
      _ = try TagRepo.deleteTag(db, tagId: tagId)
      try self.enqueueDelete(
        db, hlc: hlc, deviceId: deviceId, kind: .tag, entityId: existing.id, payload: snapshot)
      let taskIDs = edges.map { $0.taskId }
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: SyncNaming.opDelete, entityType: EntityName.tag, entityId: existing.id,
          summary: "Deleted tag '\(existing.displayName)' from \(taskIDs.count) task(s)"),
        deviceId: deviceId)
      return TagDeletionOutcome(
        tag: existing.displayName, tasksUpdated: taskIDs.count, taskIDs: taskIDs)
    }
  }

  public func mergeTags(source: String, target: String) async throws -> TagMergeOutcome {
    try withWrite { db, hlc, deviceId in
      let sourceTrim = source.trimmingCharacters(in: .whitespacesAndNewlines)
      let targetTrim = target.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !sourceTrim.isEmpty else {
        throw LorvexCoreError.validation(field: "source", message: "A source tag name is required.")
      }
      guard !targetTrim.isEmpty else {
        throw LorvexCoreError.validation(field: "target", message: "A target tag name is required.")
      }
      // Same normalized key is the no-op self-merge; reject so callers don't
      // delete the only tag thinking they merged. A case-only difference is the
      // same tag — use rename_tag to change its display casing.
      guard normalizeLookupKey(sourceTrim) != normalizeLookupKey(targetTrim) else {
        throw LorvexCoreError.validation(
          field: nil,
          message: "Source and target are the same tag. Use rename_tag to change a tag's name.")
      }
      guard let sourceTag = try TagRepo.getTagByName(db, name: sourceTrim) else {
        throw LorvexCoreError.notFound(entity: .tag, id: sourceTrim)
      }
      // Both tags must already exist — merging into a brand-new bucket is just a
      // rename, so route the caller to rename_tag instead of silently minting a tag.
      // The target miss keeps its actionable guidance (and its `unsupportedOperation`
      // wire code) rather than a bare `.notFound`, since the recovery differs from a
      // plain "no such tag": the caller likely wants rename_tag.
      guard let targetTag = try TagRepo.getTagByName(db, name: targetTrim) else {
        throw LorvexCoreError.unsupportedOperation(
          "Tag '\(targetTrim)' not found. Use rename_tag to rename '\(sourceTrim)' to a new name.")
      }
      // Capture the source tag's payload BEFORE the merge deletes its row, so
      // the Delete envelope below can carry a complete pre-delete snapshot.
      let sourceSnapshot = try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: EntityName.tag, entityId: sourceTag.id)
      let version = hlc.nextVersionString()
      let now = SyncTimestampFormat.syncTimestampNow()
      let result = try TagRepo.mergeTag(
        db, sourceId: TagId(trusted: sourceTag.id), targetId: TagId(trusted: targetTag.id),
        version: version, now: now)
      // Re-pointed target edges upsert; source edges + the source tag tombstone.
      let targetEdgeIds = result.sourceEdges.map { "\($0.taskId):\(targetTag.id)" }
      try self.enqueueTaskTagEdgeUpserts(
        db, hlc: hlc, deviceId: deviceId, edgeIds: targetEdgeIds)
      for edge in result.sourceEdges {
        let payload = PayloadLoaders.taskTagPayload(
          taskId: edge.taskId, tagId: edge.tagId, version: edge.version, createdAt: edge.createdAt)
        try self.enqueueDelete(
          db, hlc: hlc, deviceId: deviceId, kind: .taskTag,
          entityId: "\(edge.taskId):\(edge.tagId)", payload: payload)
      }
      try self.enqueueDelete(
        db, hlc: hlc, deviceId: deviceId, kind: .tag, entityId: sourceTag.id,
        payload: sourceSnapshot)
      let taskIDs = result.sourceEdges.map { $0.taskId }
      let dedupedCount = result.dedupedTaskIds.count
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: "merge", entityType: EntityName.tag, entityId: targetTag.id,
          entityIds: [sourceTag.id, targetTag.id],
          summary: "Merged tag '\(sourceTag.displayName)' into '\(targetTag.displayName)' "
            + "(\(taskIDs.count) task(s))"),
        deviceId: deviceId)
      return TagMergeOutcome(
        source: sourceTag.displayName, target: targetTag.displayName,
        tasksUpdated: taskIDs.count, tasksMoved: taskIDs.count - dedupedCount,
        tasksDeduped: dedupedCount, taskIDs: taskIDs)
    }
  }

  public func getTasksByTag(tag: String) async throws -> [LorvexTask] {
    try read { db in
      let query = TaskRepo.ListTasksQuery(
        status: .all, tags: [tag], limit: 500, offset: 0)
      let result = try TaskRepo.Read.listTasks(db, query: query)
      return try Self.enrich(db, rows: result.rows)
    }
  }

  public func countTasksByTag(tag: String) async throws -> Int {
    try read { db in
      try TaskRepo.Read.countTasksByTag(db, tagLookupKey: normalizeLookupKey(tag))
    }
  }
}
