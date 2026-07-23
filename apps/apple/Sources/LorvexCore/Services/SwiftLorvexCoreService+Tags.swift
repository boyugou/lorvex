import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

/// `LorvexListTagServicing` over the pure-Swift core.
///
/// List CRUD goes through `ListRepo` (reads) and the `+WriteSurface` adapter
/// (writes, LWW-gated); tag operations go through `TagRepo`. List/task mapping
/// reuses `SwiftLorvexListDeserializers` / `SwiftLorvexTaskDeserializers`, which
/// preserve the stable field shapes consumed by MCP and UI surfaces.
///
/// `getTasksByTag` resolves the tag's `lookup_key` and runs the canonical
/// `ListTasksQuery` tag predicate. `getListHealthSnapshot` is computed inline
/// (no dedicated core repo): per-list open / overdue-open / due-today-open task
/// counts against the connection's "today".
extension SwiftLorvexCoreService {

  /// Sanitized + validated list write fields shared by ``createList`` and
  /// ``importList``. `name` is required and non-empty; `description` / `aiNotes`
  /// are sanitized + length-capped free text; `color` / `icon` are validated as
  /// machine tokens (hex color / SF Symbol name or single emoji).
  struct NormalizedListFields {
    let name: String
    let description: String?
    let aiNotes: String?
    let color: String?
    let icon: String?
  }

  static func normalizedListFields(
    name: String, description: String?, color: String?, icon: String?, aiNotes: String?
  ) throws -> NormalizedListFields {
    NormalizedListFields(
      name: try ListValidation.normalizeName(name),
      description: try ListValidation.normalizeOptionalText(
        description, field: "description", max: ValidationLimits.maxBodyLength,
        escapedBudget: PayloadByteBudget.longTextEscapedBytes),
      aiNotes: try ListValidation.normalizeOptionalText(
        aiNotes, field: "ai_notes", max: ValidationLimits.maxAiNotesLength,
        escapedBudget: PayloadByteBudget.aiNotesEscapedBytes),
      color: try ListValidation.normalizeColor(color),
      icon: try ListValidation.normalizeIcon(icon))
  }

  public func createList(
    name: String, description: String?, color: String?, icon: String?, aiNotes: String?
  ) async throws -> LorvexList {
    let fields = try Self.normalizedListFields(
      name: name, description: description, color: color, icon: icon, aiNotes: aiNotes)
    return try withWrite { db, hlc, deviceId in
      let version = hlc.nextVersionString()
      let row = try ListRepo.createListWithAiNotes(
        db,
        params: ListCreateParams(
          id: ListId(trusted: EntityID.newEntityIDString()), name: fields.name,
          color: fields.color, icon: fields.icon,
          description: fields.description, aiNotes: fields.aiNotes, version: version))
      try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .list, entityId: row.id)
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: SyncNaming.opUpsert, entityType: EntityName.list, entityId: row.id,
          summary: "Created list '\(row.name)'"),
        deviceId: deviceId)
      return SwiftLorvexListDeserializers.list(row)
    }
  }

  public func importList(
    id: LorvexList.ID,
    name: String,
    description: String?,
    color: String?,
    icon: String?,
    aiNotes: String? = nil,
    archivedAt: String? = nil,
    position: Int64? = nil
  ) async throws -> LorvexList {
    let fields = try Self.normalizedListFields(
      name: name, description: description, color: color, icon: icon, aiNotes: aiNotes)
    return try withWrite { db, hlc, deviceId in
      try self.writeImportedListInTx(
        db, hlc: hlc, deviceId: deviceId, id: id, fields: fields, archivedAt: archivedAt,
        position: position)
    }
  }

  public func importListIfAbsent(
    id: LorvexList.ID,
    name: String,
    description: String?,
    color: String?,
    icon: String?,
    aiNotes: String?,
    archivedAt: String?,
    position: Int64?
  ) async throws -> (LorvexList?, Bool) {
    let fields = try Self.normalizedListFields(
      name: name, description: description, color: color, icon: icon, aiNotes: aiNotes)
    return try withWrite { db, hlc, deviceId in
      // A non-destructive restore skips an id a concurrent create already landed
      // (no overwrite) and one the user deleted after the backup (no resurrection:
      // a fresh dominating import HLC would beat the death version and re-propagate
      // the list fleet-wide). Both checks share this write lock with the insert, so
      // the decision cannot race the write.
      if try Int.fetchOne(db, sql: "SELECT 1 FROM lists WHERE id = ?", arguments: [id]) != nil {
        return (nil, false)
      }
      if try Tombstone.isTombstoned(db, entityType: EntityName.list, entityId: id) {
        return (nil, false)
      }
      let row = try self.writeImportedListInTx(
        db, hlc: hlc, deviceId: deviceId, id: id, fields: fields, archivedAt: archivedAt,
        position: position)
      return (row, true)
    }
  }

  /// Insert one imported list row (via ``ListRepo/upsertListForImport``) and
  /// enqueue its sync envelope + changelog, inside the caller's transaction.
  /// Shared by ``importList(id:name:description:color:icon:aiNotes:archivedAt:position:)``
  /// (overwrite-on-reimport) and ``importListIfAbsent(id:name:description:color:icon:aiNotes:archivedAt:position:)``
  /// (skip-if-present/tombstoned); the latter guards the id before calling, so its
  /// upsert path only ever inserts.
  func writeImportedListInTx(
    _ db: Database, hlc: HlcSession, deviceId: String, id: LorvexList.ID,
    fields: NormalizedListFields, archivedAt: String?, position: Int64?
  ) throws -> LorvexList {
    let version = hlc.nextVersionString()
    let now = SyncTimestampFormat.syncTimestampNow()
    let canonicalArchivedAt = try Self.canonicalOptionalImportTimestamp(
      archivedAt, field: "list archivedAt")
    let row = try ListRepo.upsertListForImport(
      db,
      params: ListCreateParams(
        id: ListId(trusted: id), name: fields.name, color: fields.color, icon: fields.icon,
        description: fields.description, aiNotes: fields.aiNotes, archivedAt: canonicalArchivedAt,
        position: position ?? 0, version: version),
      now: now)
    try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .list, entityId: row.id)
    try self.writeChangelogRow(
      db,
      ChangelogEntry(
        operation: SyncNaming.opUpsert, entityType: EntityName.list, entityId: row.id,
        summary: "Imported list '\(row.name)'"),
      deviceId: deviceId)
    let counts = try Self.listCounts(db, id: row.id)
    return SwiftLorvexListDeserializers.list(
      row, openCount: counts.open, totalCount: counts.total)
  }

  public func updateList(
    id: LorvexList.ID,
    name: String?,
    description: String?,
    color: String?,
    icon: String?,
    aiNotes: String?
  ) async throws -> LorvexList {
    guard name != nil || description != nil || color != nil || icon != nil || aiNotes != nil else {
      return try await getList(id: id)
    }
    // Sanitize + validate each provided field before opening the write. A field
    // left `nil` stays "leave unchanged"; a field that is blank after sanitizing
    // collapses to `nil` (no-op) rather than writing an empty value.
    let normName = try name.map(ListValidation.normalizeName)
    let normDescription = try ListValidation.normalizeOptionalText(
      description, field: "description", max: ValidationLimits.maxBodyLength,
      escapedBudget: PayloadByteBudget.longTextEscapedBytes)
    let normAiNotes = try ListValidation.normalizeOptionalText(
      aiNotes, field: "ai_notes", max: ValidationLimits.maxAiNotesLength,
      escapedBudget: PayloadByteBudget.aiNotesEscapedBytes)
    let normColor = try ListValidation.normalizeColor(color)
    let normIcon = try ListValidation.normalizeIcon(icon)
    return try withWrite { db, hlc, deviceId in
      guard let current = try ListRepo.getList(db, id: ListId(trusted: id)) else {
        throw LorvexCoreError.notFound(entity: .list, id: id)
      }
      // A patch whose values equal the current row (rename to the same name,
      // re-set the same color/icon/description/ai_notes) is a value-level no-op:
      // skip the sync enqueue AND the changelog row. `updateList` writes each
      // non-nil field verbatim, so compare only the participating fields; an
      // unchanged write would still bump the version and could LWW-win over a
      // concurrent legitimate remote edit.
      let nameUnchanged = normName == nil || normName == current.name
      let colorUnchanged = normColor == nil || normColor == current.color
      let iconUnchanged = normIcon == nil || normIcon == current.icon
      let descriptionUnchanged = normDescription == nil || normDescription == current.description
      let aiNotesUnchanged = normAiNotes == nil || normAiNotes == current.aiNotes
      let unchanged =
        nameUnchanged && colorUnchanged && iconUnchanged && descriptionUnchanged && aiNotesUnchanged
      guard !unchanged else {
        let counts = try Self.listCounts(db, id: id)
        return SwiftLorvexListDeserializers.list(
          current, openCount: counts.open, totalCount: counts.total)
      }
      let version = hlc.nextVersionString()
      let now = SyncTimestampFormat.syncTimestampNow()
      try ListRepo.updateList(
        db,
        params: ListUpdateParams(
          id: ListId(trusted: id), name: normName, color: normColor, icon: normIcon,
          description: normDescription, aiNotes: normAiNotes, now: now, version: version))
      guard let row = try ListRepo.getList(db, id: ListId(trusted: id)) else {
        throw LorvexCoreError.notFound(entity: .list, id: id)
      }
      try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .list, entityId: id)
      let counts = try Self.listCounts(db, id: id)
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: "update", entityType: EntityName.list, entityId: id,
          summary: "Updated list '\(row.name)'"),
        deviceId: deviceId)
      return SwiftLorvexListDeserializers.list(
        row, openCount: counts.open, totalCount: counts.total)
    }
  }

  public func setListAINotes(id: LorvexList.ID, notes: String) async throws -> LorvexList {
    let normalized = try ListValidation.normalizeOptionalText(
      notes, field: "ai_notes", max: ValidationLimits.maxAiNotesLength,
      escapedBudget: PayloadByteBudget.aiNotesEscapedBytes)
    return try withWrite { db, hlc, deviceId in
      let version = hlc.nextVersionString()
      let now = SyncTimestampFormat.syncTimestampNow()
      try ListRepo.updateListPatched(
        db,
        id: ListId(trusted: id),
        patch: ListUpdatePatch(aiNotes: normalized.map(Patch.set) ?? .clear),
        version: version,
        now: now
      )
      guard let row = try ListRepo.getList(db, id: ListId(trusted: id)) else {
        throw LorvexCoreError.notFound(entity: .list, id: id)
      }
      try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .list, entityId: id)
      let counts = try Self.listCounts(db, id: id)
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: "set_list_ai_notes", entityType: EntityName.list, entityId: id,
          summary: "Updated AI context for list '\(row.name)'"),
        deviceId: deviceId)
      return SwiftLorvexListDeserializers.list(
        row, openCount: counts.open, totalCount: counts.total)
    }
  }

  public func archiveList(id: LorvexList.ID) async throws -> LorvexList {
    try setListArchived(id: id, archived: true)
  }

  public func unarchiveList(id: LorvexList.ID) async throws -> LorvexList {
    try setListArchived(id: id, archived: false)
  }

  /// Set or clear a whole list's archive state. Archiving keeps the list and all
  /// its tasks (completed history under the list name) but drops it from the
  /// active catalog; unarchiving restores it. Bumps version + emits the list
  /// upsert/changelog like any other list write.
  private func setListArchived(id: LorvexList.ID, archived: Bool) throws -> LorvexList {
    try withWrite { db, hlc, deviceId in
      let version = hlc.nextVersionString()
      let now = SyncTimestampFormat.syncTimestampNow()
      guard
        let row = try ListRepo.setListArchived(
          db, id: ListId(trusted: id), archivedAt: archived ? now : nil,
          version: version, now: now)
      else {
        throw LorvexCoreError.notFound(entity: .list, id: id)
      }
      try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .list, entityId: id)
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: "update", entityType: EntityName.list, entityId: id,
          summary: archived ? "Archived list '\(row.name)'" : "Unarchived list '\(row.name)'"),
        deviceId: deviceId)
      let counts = try Self.listCounts(db, id: id)
      return SwiftLorvexListDeserializers.list(
        row, openCount: counts.open, totalCount: counts.total)
    }
  }

  public func deleteList(id: LorvexList.ID) async throws {
    _ = try deleteListWithReceipt(id: id)
  }

  public func deleteListForMcp(id: LorvexList.ID) async throws
    -> McpDeletionReceipt<LorvexList>
  {
    try deleteListWithReceipt(id: id)
  }

  private func deleteListWithReceipt(id: LorvexList.ID) throws
    -> McpDeletionReceipt<LorvexList>
  {
    try withWrite { db, hlc, deviceId in
      // The `inbox` list is the schema-designated canonical fallback target for
      // orphaned tasks and is re-ensured on every managed open by
      // `LorvexStore.ensureInboxListRow` (`INSERT OR IGNORE INTO lists('inbox', …
      // version '0000…')`, mirroring the `schema.sql` baseline seed). Deleting it
      // mints a `list:inbox` tombstone, but the next open resurrects Inbox locally
      // UNDER that strictly-newer tombstone — so this device shows Inbox while
      // peers keep it deleted and inbound inbox upserts are tombstone-dropped.
      // Refuse the delete outright; inbox must always exist. (The
      // `reset_all_data_db` full wipe clears inbox via direct SQL, not this
      // workflow path.)
      if id == inboxListId {
        throw LorvexCoreError.unsupportedOperation(
          "Cannot delete the inbox list: it is the canonical fallback for tasks and must "
            + "always exist.")
      }
      // At least one list must always exist for task creation. This mirrors the
      // sync-apply ApplyList invariant so a local delete can't drain the
      // workspace to zero lists and leave `default_list_id` dangling, which
      // would break every later create_task.
      let totalLists = try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM lists") ?? 0
      if totalLists <= 1 {
        throw LorvexCoreError.unsupportedOperation(
          "Cannot delete the last list. At least one list must exist for task creation.")
      }
      let assigned = try ListRepo.countAssignedTasksInList(db, listId: ListId(trusted: id))
      if assigned > 0 {
        throw LorvexCoreError.unsupportedOperation(
          "Cannot delete list while \(assigned) task(s) are assigned.")
      }
      let snapshot: JSONValue?
      do {
        snapshot = try OutboxEnqueue.readEntityPayloadSnapshot(
          db, entityType: EntityName.list, entityId: id)
      } catch EnqueueError.entityNotFound {
        // Nothing to tombstone — the row is already gone; the delete below is a no-op.
        snapshot = nil
      }
      // The `assigned` guard counts only non-archived tasks, but the schema's
      // `trg_lists_before_delete` re-homes EVERY task still pointing at this list
      // to inbox — including trashed (`archived_at IS NOT NULL`) tasks — and does
      // so without bumping their version or enqueuing an outbox row. Capture those
      // ids BEFORE the delete (the trigger overwrites `list_id`) so the re-home is
      // re-propagated as a versioned edit, matching the sync-apply path
      // (`ListDeleteRehome`) — otherwise the trashed tasks move locally with no
      // outbox row, changelog, or peer propagation.
      let rehomedTaskIds =
        id == inboxListId
        ? []
        : try String.fetchAll(db, sql: "SELECT id FROM tasks WHERE list_id = ?", arguments: [id])
      let previous = try ListRepo.getList(db, id: ListId(trusted: id)).map { row in
        let counts = try Self.listCounts(db, id: id)
        return SwiftLorvexListDeserializers.list(
          row, openCount: counts.open, totalCount: counts.total)
      }
      // Any other error propagates and rolls back the whole withWrite transaction,
      // so we never permanently delete the row without emitting its sync tombstone.
      let deleted = try ListRepo.deleteList(db, id: ListId(trusted: id))
      if deleted > 0 {
        if let snapshot {
          try self.enqueueDelete(
            db, hlc: hlc, deviceId: deviceId, kind: .list, entityId: id, payload: snapshot)
        }
        try self.writeChangelogRow(
          db,
          ChangelogEntry(
            operation: SyncNaming.opDelete, entityType: EntityName.list, entityId: id,
            summary: "Deleted list '\(id)'"),
          deviceId: deviceId)
        // Propagate the trigger's re-home (now `list_id='inbox'`) as a versioned
        // outbox upsert per task, so the move converges across peers instead of
        // being a silent local mutation. Mirrors `applyInbound`'s handling of a
        // peer's list delete.
        try ListDeleteRehome.reenqueueRehomed(
          db, taskIds: rehomedTaskIds,
          mintVersion: { floor in hlc.nextVersionString(dominating: floor) },
          deviceId: deviceId)
        if !rehomedTaskIds.isEmpty {
          try self.writeChangelogRow(
            db,
            ChangelogEntry(
              operation: SyncNaming.opUpsert, entityType: EntityName.list, entityId: inboxListId,
              summary:
                "Re-homed \(rehomedTaskIds.count) trashed task(s) to inbox after deleting list '\(id)'"),
            deviceId: deviceId)
        }
        // If this list was the configured default, repoint `default_list_id` to
        // inbox so the deletion never leaves a dangling default (which would
        // otherwise silently heal to inbox only at create time on this device).
        try Self.repointDefaultListAfterDelete(
          db, service: self, deviceId: deviceId, hlc: hlc, deletedListId: id)
      }
      return McpDeletionReceipt(previous: deleted > 0 ? previous : nil)
    }
  }

  public func moveTask(id: LorvexTask.ID, toListID listID: LorvexList.ID) async throws -> LorvexTask
  {
    let moved = try await batchMoveTasks(ids: [id], toListID: listID)
    guard let task = moved.moved.first else { throw LorvexCoreError.taskNotFound }
    return task
  }
}
