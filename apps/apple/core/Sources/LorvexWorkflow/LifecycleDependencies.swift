import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Pre-delete snapshot of a `task_dependencies` row removed by a lifecycle
/// cascade. Includes `(createdAt, version)` so the cascade tombstone can ship
/// a payload-bearing `enqueue_payload_delete` rather than an empty `{}`
/// envelope, letting peers reconstruct the row from the tombstone in
/// restore-from-trash flows.
public struct DeletedDependencyEdge: Sendable, Equatable {
  public let taskId: String
  public let dependsOnTaskId: String
  public let createdAt: String
  public let version: String

  public init(taskId: String, dependsOnTaskId: String, createdAt: String, version: String) {
    self.taskId = taskId
    self.dependsOnTaskId = dependsOnTaskId
    self.createdAt = createdAt
    self.version = version
  }
}

/// Dependency-side lifecycle primitives.
public enum LifecycleDependencies {
  /// Remove `taskId` from every dependency edge (both incoming and outgoing)
  /// and return `(affectedTaskIds, deletedEdges)`. `affectedTaskIds` are the
  /// rows that depended on `taskId` (now unblocked); `deletedEdges` carries
  /// the full pre-delete row shape so cascade tombstones round-trip.
  ///
  /// Issued as two separate DELETEs (one per direction) rather than a single
  /// `OR` predicate so each DELETE uses its own index — SQLite cannot
  /// combine the composite PK and the secondary `idx_task_deps_depends_on`
  /// for an `OR`. The pair runs inside the caller's transaction.
  ///
  /// Exposed under the `detachTaskDependencyEdges` name.
  public static func detachTaskDependencyEdges(
    _ db: Database, taskId: TaskId
  ) throws -> (affected: [String], deleted: [DeletedDependencyEdge]) {
    var deletedEdges: [DeletedDependencyEdge] = []
    var affected: [String] = []

    // Incoming edges: rows that depend on `taskId`.
    let incomingRows = try Row.fetchAll(
      db,
      sql:
        "SELECT task_id, created_at, version FROM task_dependencies "
        + "WHERE depends_on_task_id = ?1",
      arguments: [taskId.asString])
    for row in incomingRows {
      let depTaskId: String = row[0]
      let createdAt: String = row[1]
      let version: String = row[2]
      affected.append(depTaskId)
      deletedEdges.append(
        DeletedDependencyEdge(
          taskId: depTaskId, dependsOnTaskId: taskId.asString,
          createdAt: createdAt, version: version))
    }

    // Outgoing edges: `taskId`'s own dependencies.
    let outgoingRows = try Row.fetchAll(
      db,
      sql:
        "SELECT depends_on_task_id, created_at, version FROM task_dependencies "
        + "WHERE task_id = ?1",
      arguments: [taskId.asString])
    for row in outgoingRows {
      let depId: String = row[0]
      let createdAt: String = row[1]
      let version: String = row[2]
      deletedEdges.append(
        DeletedDependencyEdge(
          taskId: taskId.asString, dependsOnTaskId: depId,
          createdAt: createdAt, version: version))
    }

    try db.execute(
      sql: "DELETE FROM task_dependencies WHERE task_id = ?1",
      arguments: [taskId.asString])
    try db.execute(
      sql: "DELETE FROM task_dependencies WHERE depends_on_task_id = ?1",
      arguments: [taskId.asString])

    return (affected, deletedEdges)
  }
}
