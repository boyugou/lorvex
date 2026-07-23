import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Canonical archive / restore mutations for tasks.
///
/// Soft-delete (archive) and restore are LWW-stamped writes on the
/// parent task row. The op lives here so every consumer surface (app,
/// CLI, MCP, sync apply) shares one SQL site that stamps `version`,
/// `updated_at`, and `archived_at` together.
///
/// Each op is gated by `?version > version` so a stale stamp from a
/// delayed caller cannot clobber a fresher peer write — zero rows
/// changed surfaces as ``StoreError/staleVersion(entity:id:)`` (or
/// ``StoreError/notFound(entity:id:)`` when the row is missing the
/// expected sentinel state).
public enum TaskArchive {
  /// Soft-delete a task by stamping `archived_at`. Requires the row to
  /// be currently un-archived; throws ``StoreError/validation(_:)`` if
  /// it is already in the Trash and ``StoreError/notFound(entity:id:)``
  /// if the id has no row.
  public static func archiveTaskOp(
    _ db: Database,
    taskId: TaskId,
    version: String,
    now: String
  ) throws {
    let row = try Row.fetchOne(
      db,
      sql: "SELECT archived_at FROM tasks WHERE id = ?",
      arguments: [taskId.rawValue])
    guard let row else {
      throw StoreError.notFound(entity: EntityName.task, id: taskId.asString)
    }
    let archivedAt: String? = row[0]
    if archivedAt != nil {
      throw StoreError.validation(
        "Task '\(taskId.asString)' is already in the Trash")
    }
    try db.execute(
      sql:
        "UPDATE tasks SET archived_at = ?, archive_version = ?, updated_at = ?, version = ? "
        + "WHERE id = ? AND archived_at IS NULL AND ? > version",
      arguments: [now, version, now, version, taskId.rawValue, version])
    if db.changesCount == 0 {
      throw StoreError.staleVersion(entity: EntityName.task, id: taskId.asString)
    }
  }

  /// Restore a previously-archived task by clearing `archived_at`.
  /// Inverse of ``archiveTaskOp(_:taskId:version:now:)``. Throws
  /// ``StoreError/validation(_:)`` if the row is not in the Trash and
  /// ``StoreError/notFound(entity:id:)`` if the id has no row.
  public static func restoreTaskOp(
    _ db: Database,
    taskId: TaskId,
    version: String,
    now: String
  ) throws {
    let row = try Row.fetchOne(
      db,
      sql: "SELECT archived_at FROM tasks WHERE id = ?",
      arguments: [taskId.rawValue])
    guard let row else {
      throw StoreError.notFound(entity: EntityName.task, id: taskId.asString)
    }
    let archivedAt: String? = row[0]
    if archivedAt == nil {
      throw StoreError.validation(
        "Task '\(taskId.asString)' is not in the Trash")
    }
    try db.execute(
      sql:
        "UPDATE tasks SET archived_at = NULL, archive_version = ?, updated_at = ?, version = ? "
        + "WHERE id = ? AND archived_at IS NOT NULL AND ? > version",
      arguments: [version, now, version, taskId.rawValue, version])
    if db.changesCount == 0 {
      throw StoreError.staleVersion(entity: EntityName.task, id: taskId.asString)
    }
  }
}
