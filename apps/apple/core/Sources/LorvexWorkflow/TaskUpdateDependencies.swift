import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Dependency edge helpers for single-row task updates. The cross-row
/// cycle revalidator lives in ``TaskUpdateOrchestrator`` so it can
/// observe the final post-update graph after every row's edges have
/// landed.
public enum TaskUpdateDependencies {

  /// Snapshot `task_dependencies`, DELETE the row's outgoing edges,
  /// re-INSERT the new list, and fold the deleted-edge tombstones +
  /// upsert ids into `effects`.
  public static func replaceDependencyEdges(
    _ db: Database,
    hlc: HlcSession,
    taskId: TaskId,
    newDependsOn: [String],
    effects: inout TaskUpdateSyncEffects
  ) throws {
    let rows = try Row.fetchAll(
      db,
      sql: "SELECT depends_on_task_id, version, created_at "
        + "FROM task_dependencies WHERE task_id = ?",
      arguments: [taskId.asString])
    let oldDeps: [DeletedDependencyEdge] = rows.map { row in
      DeletedDependencyEdge(
        taskId: taskId.asString,
        dependsOnTaskId: row[0] as String,
        createdAt: row[2] as String,
        version: row[1] as String)
    }
    try db.execute(
      sql: "DELETE FROM task_dependencies WHERE task_id = ?",
      arguments: [taskId.asString])
    effects.deletedDependencyEdges.append(contentsOf: oldDeps)

    if newDependsOn.isEmpty { return }
    let version = hlc.nextVersionString()
    let now = SyncTimestampFormat.syncTimestampNow()
    let depTyped = newDependsOn.map { TaskId(trusted: $0) }
    _ = try TaskRepo.Dependencies.insertDependencyEdgesBatchInner(
      db, taskId: taskId, dependsOnIds: depTyped, version: version, now: now)
    for dep in newDependsOn {
      let edgeId = TaskDependencyEdgeId(taskId: taskId, dependsOnTaskId: TaskId(trusted: dep))
      effects.dependencyEdgeUpsertIds.append(edgeId.asString)
    }
  }

  /// Read the row's current outgoing `task_dependencies` edges.
  public static func findTaskDependencies(
    _ db: Database, taskId: TaskId
  ) throws -> [String] {
    try String.fetchAll(
      db,
      sql: "SELECT depends_on_task_id FROM task_dependencies WHERE task_id = ?",
      arguments: [taskId.asString])
  }

  /// Trim, drop blanks, deduplicate (first-seen wins). Used by both the
  /// replace (`depends_on`) and incremental (`depends_on_add` /
  /// `depends_on_remove`) paths in preparation.
  public static func normalizeDependencyIds(_ ids: [String]) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    out.reserveCapacity(ids.count)
    for id in ids {
      let trimmed = id.trimmingCharacters(in: .whitespaces)
      if !trimmed.isEmpty && seen.insert(trimmed).inserted {
        out.append(trimmed)
      }
    }
    return out
  }

  /// Merge `depends_on_add` / `depends_on_remove` against `current`.
  /// Removes run before adds so a single patch can replace a specific
  /// edge in place (remove + add the same id).
  public static func applyDependencyPatch(
    current: [String],
    dependsOnAdd: [String]?,
    dependsOnRemove: [String]?
  ) -> [String] {
    var deps = normalizeDependencyIds(current)
    let removeSet = Set(normalizeDependencyIds(dependsOnRemove ?? []))
    if !removeSet.isEmpty {
      deps.removeAll(where: { removeSet.contains($0) })
    }
    if let toAdd = dependsOnAdd {
      deps.append(contentsOf: toAdd)
    }
    return normalizeDependencyIds(deps)
  }
}
