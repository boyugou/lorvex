import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync
import LorvexWorkflow

extension SwiftLorvexCoreService {
  public func importRemoteTask(
    id: LorvexTask.ID,
    title: String,
    notes: String,
    aiNotes: String?,
    rawInput: String?,
    priority: LorvexTask.Priority,
    status: LorvexTask.Status,
    estimatedMinutes: Int?,
    dueDate: Date?,
    plannedDate: Date?,
    availableFrom: Date?,
    tags: [String],
    dependsOn: [LorvexTask.ID]
  ) async throws -> LorvexTask {
    try withWrite { db, hlc, deviceId in
      try self.createImportedTaskInTx(
        db, hlc: hlc, deviceId: deviceId, id: id, title: title, notes: notes, aiNotes: aiNotes,
        rawInput: rawInput, priority: priority, status: status, estimatedMinutes: estimatedMinutes,
        dueDate: dueDate, plannedDate: plannedDate, availableFrom: availableFrom, tags: tags,
        dependsOn: dependsOn, listId: nil)
    }
  }

  /// Create one imported task (body, tags, dates, status, optional list
  /// membership, dependency edges) and enqueue its sync envelopes + changelog,
  /// inside the caller's transaction. Shared by
  /// ``importRemoteTask(id:title:notes:aiNotes:rawInput:priority:status:estimatedMinutes:dueDate:plannedDate:availableFrom:tags:dependsOn:)``
  /// (which passes `listId: nil` and attaches membership separately) and the
  /// transactional task-record importer, which sets `listId` here so the whole
  /// task record commits atomically. A create only expresses `open` / `someday`
  /// directly (plus `completed` via the `completed` flag); `cancelled` and
  /// `in_progress` are created as `.open` and reached by a later transition —
  /// see ``LorvexDataImporter`` — so their lifecycle rules (dependency-detach for
  /// cancel, dependency-blocked gate for start) run through the same funnel as the
  /// live tools.
  func createImportedTaskInTx(
    _ db: Database, hlc: HlcSession, deviceId: String, id: LorvexTask.ID, title: String,
    notes: String, aiNotes: String?, rawInput: String?, priority: LorvexTask.Priority,
    status: LorvexTask.Status, estimatedMinutes: Int?, dueDate: Date?, plannedDate: Date?,
    availableFrom: Date?, tags: [String], dependsOn: [LorvexTask.ID], listId: LorvexList.ID?
  ) throws -> LorvexTask {
    let statusPatch: Patch<String> =
      status == .someday ? .set("someday") : .unset
    let taskInput = TaskCreateInput(
      title: title,
      listId: listId.map { .set($0) } ?? .unset,
      priority: .set(UInt8(priority.tier)),
      dueDate: dueDate.map {
        .set(SwiftLorvexTaskDeserializers.plannedDateFormatter.string(from: $0))
      } ?? .unset,
      estimatedMinutes: estimatedMinutes.map { .set(UInt32(clamping: max(0, $0))) } ?? .unset,
      tags: tags,
      body: .set(notes),
      rawInput: rawInput.map { .set($0) } ?? .unset,
      aiNotes: aiNotes.map { .set($0) } ?? .unset,
      dependsOn: dependsOn,
      plannedDate: plannedDate.map {
        .set(SwiftLorvexTaskDeserializers.plannedDateFormatter.string(from: $0))
      } ?? .unset,
      availableFrom: availableFrom.map {
        .set(SwiftLorvexTaskDeserializers.plannedDateFormatter.string(from: $0))
      } ?? .unset,
      completed: status == .completed ? true : nil,
      status: statusPatch)
    let input = CreateTaskInput(id: id, task: taskInput)
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

  public func restoreImportedTaskMetadata(
    id: LorvexTask.ID,
    archivedAt: String?,
    deferCount: Int?,
    lastDeferReason: String?,
    lastDeferredAt: String?,
    completedAt: String?,
    createdAt: String?,
    updatedAt: String?
  ) async throws {
    try withWrite { db, hlc, deviceId in
      try self.restoreImportedTaskMetadataInTx(
        db, hlc: hlc, deviceId: deviceId, id: id, archivedAt: archivedAt, deferCount: deferCount,
        lastDeferReason: lastDeferReason, lastDeferredAt: lastDeferredAt,
        completedAt: completedAt, createdAt: createdAt, updatedAt: updatedAt)
    }
  }

  /// The metadata restore inside an open write transaction, shared by the public
  /// entry and the single-transaction batch record create. Same contract as
  /// ``restoreImportedTaskMetadata(id:archivedAt:deferCount:lastDeferReason:lastDeferredAt:completedAt:createdAt:updatedAt:)``.
  func restoreImportedTaskMetadataInTx(
    _ db: Database, hlc: HlcSession, deviceId: String,
    id: LorvexTask.ID,
    archivedAt: String?,
    deferCount: Int?,
    lastDeferReason: String?,
    lastDeferredAt: String?,
    completedAt: String?,
    createdAt: String?,
    updatedAt: String?
  ) throws {
    let canonicalArchivedAt = try Self.canonicalOptionalImportTimestamp(
      archivedAt, field: "task archivedAt")
    let canonicalLastDeferredAt = try Self.canonicalOptionalImportTimestamp(
      lastDeferredAt, field: "task lastDeferredAt")
    let canonicalCompletedAt = try Self.canonicalOptionalImportTimestamp(
      completedAt, field: "task completedAt")
    let canonicalCreatedAt = try Self.canonicalOptionalImportTimestamp(
      createdAt, field: "task createdAt")
    let canonicalUpdatedAt = try Self.canonicalOptionalImportTimestamp(
      updatedAt, field: "task updatedAt")
    let typedId = TaskId(trusted: id)
    let before = try TaskResponse.loadEnrichedTaskJSON(db, taskId: typedId)
    var assignments: [String] = []
    var values: [DatabaseValueConvertible?] = []
    var registerIntent: TaskRegisterIntent = []

    if let canonicalArchivedAt {
      assignments.append("archived_at = ?")
      values.append(canonicalArchivedAt)
      registerIntent.insert(.archive)
    }
    if let deferCount {
      assignments.append("defer_count = ?")
      values.append(Int64(max(0, deferCount)))
      registerIntent.insert(.schedule)
    }
    if let lastDeferReason {
      assignments.append("last_defer_reason = ?")
      values.append(lastDeferReason)
      registerIntent.insert(.schedule)
    }
    if let canonicalLastDeferredAt {
      assignments.append("last_deferred_at = ?")
      values.append(canonicalLastDeferredAt)
      registerIntent.insert(.schedule)
    }
    if let canonicalCompletedAt {
      assignments.append("completed_at = ?")
      values.append(canonicalCompletedAt)
      registerIntent.insert(.lifecycle)
    }
    if let canonicalCreatedAt {
      assignments.append("created_at = MIN(created_at, ?)")
      values.append(canonicalCreatedAt)
      registerIntent.insert(.content)
    }

    guard !assignments.isEmpty || canonicalUpdatedAt != nil else { return }
    assignments.append("updated_at = ?")
    values.append(canonicalUpdatedAt ?? SyncTimestampFormat.syncTimestampNow())
    if canonicalUpdatedAt != nil {
      // Historical identity metadata is outside the four value groups. The
      // content register is its replay carrier on this import-only surface so
      // an authoritative-snapshot cutover cannot discard the correction.
      registerIntent.insert(.content)
    }
    let version = hlc.nextVersionString()
    if registerIntent.contains(.content) {
      assignments.append("content_version = ?")
      values.append(version)
    }
    if registerIntent.contains(.schedule) {
      assignments.append("schedule_version = ?")
      values.append(version)
    }
    if registerIntent.contains(.lifecycle) {
      assignments.append("lifecycle_version = ?")
      values.append(version)
    }
    if registerIntent.contains(.archive) {
      assignments.append("archive_version = ?")
      values.append(version)
    }
    assignments.append("version = ?")
    values.append(version)

    // LWW-gate the metadata restore on `version` (`? > version`) so an import
    // never REGRESSES a row a peer stamped with a future HLC. On a refused
    // write `LwwOps` throws `staleVersion`, routing through the
    // `runWriteAttempt` retry, which advances the clock past the future version
    // and re-runs so the import wins at a dominating version.
    try LwwOps.executeUpdate(
      db, table: "tasks", entity: EntityName.task, id: id, version: version,
      setClauses: assignments, bindings: values)
    try self.enqueueUpsert(
      db, deviceId: deviceId, kind: .task, entityId: id, version: version,
      registerIntent: .task(registerIntent))
    let after = try TaskResponse.loadEnrichedTaskJSON(db, taskId: typedId)
    try self.writeChangelogRow(
      db,
      ChangelogEntry(
        operation: "restore_metadata",
        entityId: id,
        summary: "Restored metadata for task '\(TaskResponse.taskTitle(after))'",
        before: before,
        after: after),
      deviceId: deviceId)
  }

  public func restoreImportedTaskLifecycleState(
    id: LorvexTask.ID, status: LorvexTask.Status
  ) async throws {
    try withWrite { db, hlc, deviceId in
      try self.restoreImportedTaskLifecycleStateInTx(
        db, hlc: hlc, deviceId: deviceId, id: id, status: status)
    }
  }

  func restoreImportedTaskLifecycleStateInTx(
    _ db: Database, hlc: HlcSession, deviceId: String,
    id: LorvexTask.ID, status: LorvexTask.Status
  ) throws {
    guard status == .inProgress else {
      throw LorvexCoreError.unsupportedOperation(
        "Exact lifecycle import currently accepts only in_progress.")
    }
    let typedId = TaskId(trusted: id)
    guard let row = try TaskRepo.Read.getTask(db, taskId: typedId) else {
      throw LorvexCoreError.taskNotFound
    }
    let oldStatus = try LifecycleStatus.parsePersistedTaskStatus(
      taskId: typedId, raw: row.core.status)
    guard oldStatus != .inProgress else { return }
    guard oldStatus == .open else {
      throw LorvexCoreError.unsupportedOperation(
        "Exact in_progress restore requires an open imported task.")
    }

    let before = try TaskResponse.loadEnrichedTaskJSON(db, taskId: typedId)
    let version = hlc.nextVersionString()
    let now = SyncTimestampFormat.syncTimestampNow()
    let changed = try LifecycleWriteStatus.writeStatusAndMetadata(
      db, taskId: typedId, oldStatus: oldStatus,
      newStatus: TaskStatus.inProgress, now: now, version: version)
    guard changed == 1 else {
      throw StoreError.staleVersion(entity: EntityName.task, id: id)
    }
    try self.enqueueUpsert(
      db, deviceId: deviceId, kind: .task, entityId: id, version: version,
      registerIntent: .task(.lifecycle))
    let after = try TaskResponse.loadEnrichedTaskJSON(db, taskId: typedId)
    try self.writeChangelogRow(
      db,
      ChangelogEntry(
        operation: "restore_lifecycle", entityId: id,
        summary: "Restored task lifecycle state to in_progress",
        before: before, after: after),
      deviceId: deviceId)
  }
}
