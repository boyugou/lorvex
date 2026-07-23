import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Permanently delete a task that is already in the Trash
/// (`archived_at IS NOT NULL`).
///
/// The two-step Trash flow (archive → permanent_delete) is enforced
/// here: a task that has never been archived is rejected with a
/// validation error. This prevents a single MCP call from destroying
/// live data.
///
/// Side effects, in order:
///
/// 1. Snapshot `before` row.
/// 2. Collect tombstone-bound sync payloads for every cascading edge
///    / child (`task_tags`, `task_checklist_items`, `task_reminders`,
///    `task_calendar_event_links`, `task_dependencies`).
/// 3. Collect focus parent dates that
///    reference this task.
/// 4. Explicitly DELETE `current_focus_items`, `focus_schedule_blocks`,
///    and `task_dependencies` rows referencing this task on either
///    side. The schema's FK cascade handles the rest.
/// 5. Re-root any surviving recurrence neighbors so no durable lineage or
///    authorization points at the row being removed.
/// 6. LWW-gated `hardDeleteTaskLww` on the parent row. The synthetic
///    task tombstone payload uses the pre-delete row.
public enum TaskPermanentDelete {
  /// Input for ``permanentDeleteTask(_:hlc:input:)``.
  public struct PermanentDeleteTaskInput: Sendable {
    public let taskId: TaskId
    public init(taskId: TaskId) { self.taskId = taskId }
  }

  /// One per-entity sync payload tagged with its wire entity type +
  /// stringified id. Surface adapters translate these into outbox
  /// upserts or tombstones.
  public struct SyncPayloadChange: Sendable {
    public let entityType: String
    public let entityId: String
    public let payload: JSONValue
    public init(entityType: String, entityId: String, payload: JSONValue) {
      self.entityType = entityType
      self.entityId = entityId
      self.payload = payload
    }
  }

  /// Per-date focus aggregates the delete touched, so the caller can
  /// re-emit the affected aggregate snapshots.
  public struct FocusParentDates: Sendable {
    public let currentFocus: [String]
    public let focusSchedule: [String]
    public init(currentFocus: [String] = [], focusSchedule: [String] = []) {
      self.currentFocus = currentFocus
      self.focusSchedule = focusSchedule
    }
  }

  public struct PermanentDeleteTaskResult: Sendable {
    public let taskId: String
    public let title: String
    public let deleted: Bool
    public let payload: JSONValue
    public let beforeTask: JSONValue
    public let deleteSyncs: [SyncPayloadChange]
    public let focusParentDates: FocusParentDates
    /// Surviving task rows whose schedule or lifecycle register changed while
    /// severing recurrence links to the deleted row. The service boundary must
    /// enqueue task upserts for these ids in the same outer transaction.
    public let rerootedTaskIds: [String]
    public let summary: String
  }

  /// Hard-delete a task. Caller owns the surrounding savepoint /
  /// transaction and the HLC session.
  public static func permanentDeleteTask(
    _ db: Database,
    hlc: HlcSession,
    input: PermanentDeleteTaskInput
  ) throws -> PermanentDeleteTaskResult {
    let taskId = input.taskId
    let taskIdStr = taskId.asString
    guard let before = try TaskRepo.Read.getTask(db, taskId: taskId) else {
      throw StoreError.notFound(entity: EntityName.task, id: taskIdStr)
    }
    if before.lifecycle.archivedAt == nil {
      throw StoreError.validation(
        "task must be archived via archive_task before permanent_delete_task can remove it; "
        + "the two-step Trash flow prevents a single MCP call from destroying live data "
        + "(issue #2363)")
    }

    let title = before.core.title
    let beforeTask = TaskResponse.encodeTaskRow(before)

    var deleteSyncs: [SyncPayloadChange] = []
    deleteSyncs.append(contentsOf: tagged(
      EdgeName.taskTag,
      try PayloadLoaders.loadTaskTagsForTask(db, taskId: taskIdStr)))
    deleteSyncs.append(contentsOf: tagged(
      EntityName.taskChecklistItem,
      try PayloadLoaders.loadTaskChecklistItemsForTask(db, taskId: taskIdStr)))
    deleteSyncs.append(contentsOf: tagged(
      EntityName.taskReminder,
      try PayloadLoaders.loadTaskRemindersForTask(db, taskId: taskIdStr)))
    deleteSyncs.append(contentsOf: tagged(
      EdgeName.taskCalendarEventLink,
      try PayloadLoaders.loadTaskCalendarEventLinksForTask(db, taskId: taskIdStr)))
    deleteSyncs.append(contentsOf: tagged(
      EdgeName.taskDependency,
      try PayloadLoaders.loadTaskDependenciesForTask(db, taskId: taskIdStr)))

    let focusParentDates = try collectFocusParentDates(db, taskId: taskIdStr)

    try db.execute(
      sql: "DELETE FROM current_focus_items WHERE task_id = ?", arguments: [taskIdStr])
    try db.execute(
      sql: "DELETE FROM focus_schedule_blocks WHERE task_id = ?", arguments: [taskIdStr])
    try db.execute(
      sql: "DELETE FROM task_dependencies WHERE task_id = ?", arguments: [taskIdStr])
    try db.execute(
      sql: "DELETE FROM task_dependencies WHERE depends_on_task_id = ?", arguments: [taskIdStr])

    let deleteVersion = hlc.nextVersionString()
    let deleteNow = SyncTimestampFormat.syncTimestampNow()
    let rerootedTaskIds = try rerootRecurrenceNeighbors(
      db, deletedTaskId: taskIdStr, version: deleteVersion, now: deleteNow)
    let deletedRows = try TaskRepo.Write.hardDeleteTaskLww(
      db, taskId: taskId, version: deleteVersion)
    let deleted = deletedRows > 0
    if deleted {
      deleteSyncs.append(SyncPayloadChange(
        entityType: EntityName.task,
        entityId: taskIdStr,
        payload: beforeTask))
    }

    let summary = "Permanently deleted task '\(title)'"
    let payload: JSONValue = .object([
      "id": .string(taskIdStr),
      "deleted": .bool(deleted),
      "previous": beforeTask,
    ])

    return PermanentDeleteTaskResult(
      taskId: taskIdStr,
      title: title,
      deleted: deleted,
      payload: payload,
      beforeTask: beforeTask,
      deleteSyncs: deleteSyncs,
      focusParentDates: focusParentDates,
      rerootedTaskIds: rerootedTaskIds,
      summary: summary)
  }

  // MARK: - helpers

  private static func tagged(
    _ entityType: String, _ rows: [(String, JSONValue)]
  ) -> [SyncPayloadChange] {
    rows.map { id, payload in
      SyncPayloadChange(entityType: entityType, entityId: id, payload: payload)
    }
  }

  private static func collectFocusParentDates(
    _ db: Database, taskId: String
  ) throws -> FocusParentDates {
    let currentFocus = try String.fetchAll(
      db,
      sql: "SELECT DISTINCT date FROM current_focus_items WHERE task_id = ?",
      arguments: [taskId])
    let focusSchedule = try String.fetchAll(
      db,
      sql: "SELECT DISTINCT date FROM focus_schedule_blocks WHERE task_id = ?",
      arguments: [taskId])
    return FocusParentDates(currentFocus: currentFocus, focusSchedule: focusSchedule)
  }

  /// Sever both possible recurrence relationships around the deleted row:
  ///
  /// - If a terminal predecessor currently authorizes this row, advance that
  ///   predecessor to `ended` so it does not point at a missing successor.
  /// - If this row is the historical parent of surviving generated rows,
  ///   promote those rows to roots by clearing their lineage pair.
  ///
  /// Each changed register uses the delete HLC. A stale neighbor aborts the
  /// transaction instead of allowing a half-severed chain to commit.
  private static func rerootRecurrenceNeighbors(
    _ db: Database,
    deletedTaskId: String,
    version: String,
    now: String
  ) throws -> [String] {
    let predecessorIds = try String.fetchAll(
      db,
      sql:
        "SELECT id FROM tasks "
        + "WHERE recurrence_rollover_state = 'authorized' "
        + "AND recurrence_successor_id = ?1 ORDER BY id",
      arguments: [deletedTaskId])
    let successorIds = try String.fetchAll(
      db,
      sql:
        "SELECT id FROM tasks WHERE spawned_from = ?1 AND id <> ?1 ORDER BY id",
      arguments: [deletedTaskId])

    for predecessorId in predecessorIds {
      try db.execute(
        sql:
          "UPDATE tasks SET recurrence_rollover_state = 'ended', "
          + "recurrence_successor_id = NULL, lifecycle_version = ?1, "
          + "version = ?1, updated_at = ?2 "
          + "WHERE id = ?3 AND ?1 > version",
        arguments: [version, now, predecessorId])
      guard db.changesCount == 1 else {
        throw StoreError.staleVersion(entity: EntityName.task, id: predecessorId)
      }
    }

    for successorId in successorIds {
      try db.execute(
        sql:
          "UPDATE tasks SET spawned_from = NULL, spawned_from_version = NULL, "
          + "schedule_version = ?1, version = ?1, updated_at = ?2 "
          + "WHERE id = ?3 AND ?1 > version",
        arguments: [version, now, successorId])
      guard db.changesCount == 1 else {
        throw StoreError.staleVersion(entity: EntityName.task, id: successorId)
      }
    }

    return Array(Set(predecessorIds + successorIds)).sorted()
  }
}
