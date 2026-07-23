import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

/// `LorvexTaskServicing` over the pure-Swift core.
///
/// Reads go through `Overview` / `TaskRepo`; writes go through the
/// `LorvexWorkflow` orchestrators funneled through the `+WriteSurface` adapter
/// (HLC minting, immediate transaction, `ai_changelog`, `local_change_seq`).
/// Every result is mapped onto the app's stable `LorvexCore` model types via
/// `SwiftLorvexTaskDeserializers`, which reuses the exact field reads the
/// app's dependent files and views expect from the stable task shape.
extension SwiftLorvexCoreService {
  // MARK: - Create

  public func createTask(title: String, notes: String) async throws -> LorvexTask {
    try await createTask(TaskCreateDraft(title: title, notes: notes))
  }

  public func createTask(_ draft: TaskCreateDraft) async throws -> LorvexTask {
    try withWrite { db, hlc, deviceId in
      try self.createTaskInTx(db, hlc: hlc, deviceId: deviceId, draft: draft)
    }
  }

  /// One ordinary (server-assigns-the-id) task create — row, sync effects, and
  /// changelog — inside an open write transaction, shared by the public entry
  /// and the single-transaction batch record create.
  func createTaskInTx(
    _ db: Database, hlc: HlcSession, deviceId: String, draft: TaskCreateDraft
  ) throws -> LorvexTask {
    let input = CreateTaskInput(
      task: TaskCreateInput(
        title: draft.title,
        listId: draft.listID.map { .set($0) } ?? .unset,
        priority: .set(
          UInt8(draft.priority.tier)),
        dueDate: draft.dueDate.map {
          .set(SwiftLorvexTaskDeserializers.plannedDateFormatter.string(from: $0))
        } ?? .unset,
        estimatedMinutes: draft.estimatedMinutes.map { .set(UInt32(clamping: max(0, $0))) }
          ?? .unset,
        tags: draft.tags,
        body: .set(draft.notes),
        rawInput: draft.rawInput.map { .set($0) } ?? .unset,
        dependsOn: draft.dependsOn,
        plannedDate: draft.plannedDate.map {
          .set(SwiftLorvexTaskDeserializers.plannedDateFormatter.string(from: $0))
        } ?? .unset,
        availableFrom: draft.availableFrom.map {
          .set(SwiftLorvexTaskDeserializers.plannedDateFormatter.string(from: $0))
        } ?? .unset))
    let result = try TaskCreate.createTask(db, hlc: hlc, input: input)
    try self.flushCreateTaskEffects(db, hlc: hlc, deviceId: deviceId, effects: result.syncEffects)
    try self.writeChangelogRow(
      db,
      ChangelogEntry(
        operation: SyncNaming.opUpsert,
        entityId: result.taskId.asString,
        summary: result.summary,
        after: result.task),
      deviceId: deviceId)
    return try SwiftLorvexTaskDeserializers.task(result.task)
  }

  // MARK: - Update

  public func updateTask(
    id: LorvexTask.ID,
    title: String,
    notes: String,
    priority: LorvexTask.Priority,
    estimatedMinutes: Int?,
    dueDate: Date?,
    plannedDate: Date?,
    availableFrom: Date?,
    tags: [String],
    dependsOn: [LorvexTask.ID]
  ) async throws -> LorvexTask {
    try await updateTask(
      id: id, title: title, notes: notes, priority: priority,
      estimatedMinutes: estimatedMinutes, dueDate: dueDate, plannedDate: plannedDate,
      availableFrom: availableFrom, tags: tags, dependsOn: dependsOn,
      rawInput: .unset)
  }

  public func updateTask(
    id: LorvexTask.ID,
    title: String,
    notes: String,
    priority: LorvexTask.Priority,
    estimatedMinutes: Int?,
    dueDate: Date?,
    plannedDate: Date?,
    availableFrom: Date?,
    tags: [String],
    dependsOn: [LorvexTask.ID],
    rawInput: String?
  ) async throws -> LorvexTask {
    try await updateTask(
      id: id, title: title, notes: notes, priority: priority,
      estimatedMinutes: estimatedMinutes, dueDate: dueDate, plannedDate: plannedDate,
      availableFrom: availableFrom, tags: tags, dependsOn: dependsOn,
      rawInput: rawInput.map { .set($0) } ?? .clear)
  }

  /// Shared implementation for both force-set `updateTask` overloads (UI /
  /// intents supply a fully-resolved value for every column). `rawInput` is a
  /// `Patch` so the no-`raw_input`-param overload can pass `.unset` (leave the
  /// column untouched) while the `raw_input`-aware overload passes `.set`/`.clear`.
  private func updateTask(
    id: LorvexTask.ID,
    title: String,
    notes: String,
    priority: LorvexTask.Priority,
    estimatedMinutes: Int?,
    dueDate: Date?,
    plannedDate: Date?,
    availableFrom: Date?,
    tags: [String],
    dependsOn: [LorvexTask.ID],
    rawInput: Patch<String>
  ) async throws -> LorvexTask {
    try withWrite { db, hlc, deviceId in
      let input = TaskUpdateInput(
        id: id,
        title: .set(title),
        body: .set(notes),
        rawInput: rawInput,
        listId: .unset,
        tagsSet: tags,
        priority: .set(UInt8(priority.tier)),
        dueDate: dueDate.map {
          .set(SwiftLorvexTaskDeserializers.plannedDateFormatter.string(from: $0))
        } ?? .clear,
        estimatedMinutes: estimatedMinutes.map { .set(UInt32(clamping: max(0, $0))) } ?? .clear,
        dependsOn: dependsOn,
        plannedDate: plannedDate.map {
          .set(SwiftLorvexTaskDeserializers.plannedDateFormatter.string(from: $0))
        } ?? .clear,
        availableFrom: availableFrom.map {
          .set(SwiftLorvexTaskDeserializers.plannedDateFormatter.string(from: $0))
        } ?? .clear)
      return try self.performTaskUpdate(db, hlc: hlc, deviceId: deviceId, input: input)
    }
  }

  /// Patch one task using per-field ``Patch`` semantics: `.unset` columns are
  /// not written, so a field the caller omits is left exactly as a concurrent
  /// writer last set it (no read-modify-write clobber). The lost-update-safe
  /// entry for the singular `update_task` MCP tool; the whole read-and-write
  /// runs in one `withWrite` transaction.
  public func updateTask(_ draft: TaskUpdateDraft) async throws -> LorvexTask {
    if let title = draft.title, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      throw LorvexCoreError.emptyTitle
    }
    return try withWrite { db, hlc, deviceId in
      let input = TaskUpdateInput(
        id: draft.id,
        title: draft.title.map { .set($0) } ?? .unset,
        body: draft.notes.map { .set($0) } ?? .unset,
        rawInput: draft.rawInput,
        listId: draft.listID.map { .set($0) } ?? .unset,
        tagsSet: draft.tags,
        priority: draft.priority.map {
          .set(UInt8($0.tier))
        } ?? .unset,
        dueDate: Self.formatTaskDatePatch(draft.dueDate),
        estimatedMinutes: Self.estimatedMinutesPatch(draft.estimatedMinutes),
        dependsOn: draft.dependsOn,
        plannedDate: Self.formatTaskDatePatch(draft.plannedDate),
        availableFrom: Self.formatTaskDatePatch(draft.availableFrom))
      return try self.performTaskUpdate(db, hlc: hlc, deviceId: deviceId, input: input)
    }
  }

  /// Apply a prepared ``TaskUpdateInput`` in the current `withWrite`
  /// transaction and return the enriched task. `TaskUpdate.updateTask`
  /// self-wraps in its own immediate transaction, which cannot nest inside
  /// `withWrite`; to keep the outbox enqueue atomic with the row mutation
  /// (sync-correctness invariant) this drives the per-row primitive
  /// `applySingleUpdateInSavepoint` directly — the exact contract its docstring
  /// delegates to the caller. Records an `update` changelog row.
  func performTaskUpdate(
    _ db: Database, hlc: HlcSession, deviceId: String, input: TaskUpdateInput
  ) throws -> LorvexTask {
    let typedId = TaskId(trusted: input.id)
    let beforeTask = try TaskResponse.loadEnrichedTaskJSON(db, taskId: typedId)
    let beforeSyncPayload = try OutboxEnqueue.readEntityPayloadSnapshot(
      db, entityType: EntityName.task, entityId: input.id)
    let beforeStatus: String = {
      if case .object(let obj) = beforeTask, case .string(let s)? = obj["status"] { return s }
      return TaskStatus.open.rawValue
    }()
    var syncEffects = TaskUpdateSyncEffects()
    var depChangedIds: [String] = []
    try TaskUpdate.applySingleUpdateInSavepoint(
      db, hlc: hlc, update: input, beforeStatus: beforeStatus,
      now: SyncTimestampFormat.syncTimestampNow(),
      syncEffects: &syncEffects, depChangedIds: &depChangedIds)
    try TaskUpdate.revalidateDependencyCycles(
      db, depChangedIds: depChangedIds, errorContext: "update_task")
    let updatedTask = try TaskResponse.loadEnrichedTaskJSON(db, taskId: typedId)
    let afterSyncPayload = try OutboxEnqueue.readEntityPayloadSnapshot(
      db, entityType: EntityName.task, entityId: input.id)
    let registerIntent = try TaskRegisterIntent.authoredRegisters(
      between: beforeSyncPayload, and: afterSyncPayload)

    try self.flushTaskUpdateEffects(
      db, hlc: hlc, deviceId: deviceId, effects: syncEffects,
      primaryRegisterIntents: [input.id: registerIntent])
    try self.writeChangelogRow(
      db,
      ChangelogEntry(
        operation: "update", entityId: input.id,
        summary: "Updated task '\(TaskResponse.taskTitle(updatedTask))'",
        before: beforeTask, after: updatedTask),
      deviceId: deviceId)
    return try SwiftLorvexTaskDeserializers.task(updatedTask)
  }

  // MARK: - Permanent delete

  public func deleteTask(id: LorvexTask.ID) async throws {
    _ = try withWrite { db, hlc, deviceId in
      try self.performTaskPermanentDelete(db, hlc: hlc, deviceId: deviceId, id: id)
    }
  }

  public func deleteTaskForMcp(id: LorvexTask.ID) async throws
    -> McpDeletionReceipt<LorvexTask>
  {
    try withWrite { db, hlc, deviceId in
      try self.performTaskPermanentDelete(db, hlc: hlc, deviceId: deviceId, id: id)
    }
  }

  /// Archive (if needed) and permanently delete a task in one transaction — the
  /// human-confirmed UI Trash action. `deleteTask` requires the task to already
  /// be archived (the MCP two-step that stops the AI from destroying live data
  /// in a single call, issue #2363); a person clicking "Delete Permanently…"
  /// past a destructive confirmation is that deliberate step, so the archive is
  /// folded in. The row is tombstoned in the same transaction, so the
  /// in-transaction `archived_at` never needs its own sync envelope.
  public func permanentlyDeleteTask(id: LorvexTask.ID) async throws {
    _ = try withWrite { db, hlc, deviceId in
      try db.execute(
        sql: "UPDATE tasks SET archived_at = ? WHERE id = ? AND archived_at IS NULL",
        arguments: [SyncTimestampFormat.syncTimestampNow(), id])
      return try self.performTaskPermanentDelete(db, hlc: hlc, deviceId: deviceId, id: id)
    }
  }

  public func archiveTask(id: LorvexTask.ID) async throws -> LorvexTask {
    try withWrite { db, hlc, deviceId in
      let before = try TaskResponse.loadEnrichedTaskJSON(db, taskId: TaskId(trusted: id))
      let version = hlc.nextVersionString()
      try TaskArchive.archiveTaskOp(
        db, taskId: TaskId(trusted: id), version: version,
        now: SyncTimestampFormat.syncTimestampNow())
      try self.removeTaskFromFocusReferences(db, hlc: hlc, deviceId: deviceId, taskID: id)
      // The row still exists with `archived_at` set; an upsert propagates the
      // new archived state to peers (no tombstone — the task is not deleted).
      try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .task, entityId: id)
      let after = try TaskResponse.loadEnrichedTaskJSON(db, taskId: TaskId(trusted: id))
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: "archive", entityId: id,
          summary: "Archived task '\(TaskResponse.taskTitle(after))'",
          before: before, after: after),
        deviceId: deviceId)
      return try SwiftLorvexTaskDeserializers.task(after)
    }
  }

  public func unarchiveTask(id: LorvexTask.ID) async throws -> LorvexTask {
    try withWrite { db, hlc, deviceId in
      let before = try TaskResponse.loadEnrichedTaskJSON(db, taskId: TaskId(trusted: id))
      let version = hlc.nextVersionString()
      try TaskArchive.restoreTaskOp(
        db, taskId: TaskId(trusted: id), version: version,
        now: SyncTimestampFormat.syncTimestampNow())
      try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .task, entityId: id)
      let after = try TaskResponse.loadEnrichedTaskJSON(db, taskId: TaskId(trusted: id))
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: "unarchive", entityId: id,
          summary: "Restored task '\(TaskResponse.taskTitle(after))' from the Trash",
          before: before, after: after),
        deviceId: deviceId)
      return try SwiftLorvexTaskDeserializers.task(after)
    }
  }

  private func performTaskPermanentDelete(
    _ db: Database, hlc: HlcSession, deviceId: String, id: LorvexTask.ID
  ) throws -> McpDeletionReceipt<LorvexTask> {
    let before: JSONValue?
    if try TaskRepo.Read.getTask(db, taskId: TaskId(trusted: id)) != nil {
      before = try TaskResponse.loadEnrichedTaskJSON(db, taskId: TaskId(trusted: id))
    } else {
      before = nil
    }
    let previous = try before.map(SwiftLorvexTaskDeserializers.task)
    // Capture the canonical pre-delete task payload (the snapshot reader reads
    // the live row, which the permanent-delete op is about to remove).
    let taskSnapshot: JSONValue?
    do {
      taskSnapshot = try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: EntityName.task, entityId: id)
    } catch EnqueueError.entityNotFound {
      // Nothing to tombstone — the row is already gone; the delete below is a no-op.
      taskSnapshot = nil
    }
    // Any other error propagates and rolls back the whole withWrite transaction,
    // so we never permanently delete the row without emitting its sync tombstone.
    // Stamp DELETE envelopes for the child + edge rows BEFORE the parent
    // delete's ON DELETE CASCADE silently drops them.
    try self.enqueueTaskDeleteCascade(db, hlc: hlc, deviceId: deviceId, taskId: id)
    let result = try TaskPermanentDelete.permanentDeleteTask(
      db, hlc: hlc,
      input: TaskPermanentDelete.PermanentDeleteTaskInput(taskId: TaskId(trusted: id)))
    if result.deleted {
      if let taskSnapshot {
        try self.enqueueDelete(
          db, hlc: hlc, deviceId: deviceId, kind: .task, entityId: id, payload: taskSnapshot)
      }
      // The task was pulled out of any focus aggregates it belonged to; re-emit
      // those date-scoped parent snapshots so peers drop it from their copy.
      try self.enqueueUpserts(
        db, hlc: hlc, deviceId: deviceId, kind: .currentFocus,
        entityIds: result.focusParentDates.currentFocus)
      try self.enqueueUpserts(
        db, hlc: hlc, deviceId: deviceId, kind: .focusSchedule,
        entityIds: result.focusParentDates.focusSchedule)
      for rerootedTaskId in result.rerootedTaskIds {
        try self.enqueueUpsert(
          db, hlc: hlc, deviceId: deviceId, kind: .task,
          entityId: rerootedTaskId)
      }
    }
    try self.writeChangelogRow(
      db,
      ChangelogEntry(
        operation: SyncNaming.opDelete,
        entityId: id,
        summary: "Deleted task '\(result.title)'",
        before: before),
      deviceId: deviceId)
    return McpDeletionReceipt(previous: result.deleted ? previous : nil)
  }
}
