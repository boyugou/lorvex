import GRDB
import LorvexDomain
import LorvexStore

struct TaskDeleteApplyResult {
  let decision: ApplyAggregate.CascadingDeleteDecision
  let repairTargets: [TaskGraphRepairTarget]
}

extension ApplyTask {
  static func applyTaskDelete(
    _ db: Database, entityId: String, version: String, applyTs: String
  ) throws -> ApplyAggregate.CascadingDeleteDecision {
    try applyTaskDeleteWithRepairs(
      db, entityId: entityId, version: version, applyTs: applyTs
    ).decision
  }

  static func applyTaskDeleteWithRepairs(
    _ db: Database, entityId: String, version: String, applyTs: String
  ) throws -> TaskDeleteApplyResult {
    var repairTargets: [TaskGraphRepairTarget] = []
    let decision = try ApplyAggregate.gateThenCascade(
      db, readVersionSQL: "SELECT version FROM tasks WHERE id = ?",
      deleteSQL: "DELETE FROM tasks WHERE id = :id", entityId: entityId,
      incomingVersion: version, tieBreak: .allowEqual
    ) { db in
      try reconcileRolloverNeighborsForDelete(
        db, deletedTaskId: entityId, decisionVersion: version,
        repairTargets: &repairTargets)
      try tombstoneCascadingChildren(
        db, taskId: entityId, version: version, deletedAt: applyTs)
      repairTargets += try TaskGraphReconciliation.removeFocusReferences(
        db, taskId: entityId)
    }
    if case .rejected = decision { repairTargets.removeAll() }
    return TaskDeleteApplyResult(
      decision: decision,
      repairTargets: TaskGraphRepairTarget.coalesced(repairTargets))
  }

  private static func reconcileRolloverNeighborsForDelete(
    _ db: Database, deletedTaskId: String, decisionVersion: String,
    repairTargets: inout [TaskGraphRepairTarget]
  ) throws {
    let descendantIds = try String.fetchAll(
      db,
      sql: "SELECT id FROM tasks WHERE spawned_from = ? ORDER BY id ASC",
      arguments: [deletedTaskId])
    for descendantId in descendantIds {
      guard var child = try TaskSyncRow.load(db, id: descendantId) else { continue }
      let original = child
      try child.reRootSuccessor(at: decisionVersion)
      guard child != original else { continue }
      try writeReconciledTask(db, row: child)
      repairTargets.append(
        .taskUpsert(
          taskId: descendantId,
          registerIntent: try child.changedRegisters(comparedTo: original)))
    }

    let predecessorIds = try String.fetchAll(
      db,
      sql: """
        SELECT id FROM tasks
         WHERE recurrence_successor_id = ?
           AND recurrence_rollover_state = 'authorized'
         ORDER BY id ASC
        """,
      arguments: [deletedTaskId])
    for predecessorId in predecessorIds {
      guard var predecessor = try TaskSyncRow.load(db, id: predecessorId) else { continue }
      let original = predecessor
      try predecessor.endAuthorizationForDeletedSuccessor(at: decisionVersion)
      guard predecessor != original else { continue }
      try writeReconciledTask(db, row: predecessor)
      repairTargets.append(
        .taskUpsert(
          taskId: predecessorId,
          registerIntent: try predecessor.changedRegisters(comparedTo: original)))
    }
  }

  /// Tombstone every cascading child / edge row before SQLite removes it.
  private static func tombstoneCascadingChildren(
    _ db: Database, taskId: String, version: String, deletedAt: String
  ) throws {
    try ApplyAggregate.tombstoneCompositeEdges(
      db, selectSQL: "SELECT tag_id, version FROM task_tags WHERE task_id = ?",
      parentId: taskId, entityType: EdgeName.taskTag,
      composeId: { "\(taskId):\($0)" }, version: version, deletedAt: deletedAt)
    try ApplyAggregate.tombstoneCompositeEdges(
      db, selectSQL: "SELECT depends_on_task_id, version FROM task_dependencies WHERE task_id = ?",
      parentId: taskId, entityType: EdgeName.taskDependency,
      composeId: { "\(taskId):\($0)" }, version: version, deletedAt: deletedAt)
    try ApplyAggregate.tombstoneCompositeEdges(
      db, selectSQL: "SELECT task_id, version FROM task_dependencies WHERE depends_on_task_id = ?",
      parentId: taskId, entityType: EdgeName.taskDependency,
      composeId: { "\($0):\(taskId)" }, version: version, deletedAt: deletedAt)
    try ApplyAggregate.tombstoneCompositeEdges(
      db,
      selectSQL: "SELECT calendar_event_id, version FROM task_calendar_event_links WHERE task_id = ?",
      parentId: taskId, entityType: EdgeName.taskCalendarEventLink,
      composeId: { "\(taskId):\($0)" }, version: version, deletedAt: deletedAt)
    try ApplyAggregate.tombstoneChildRows(
      db, selectSQL: "SELECT id, version FROM task_reminders WHERE task_id = ?",
      parentId: taskId, entityType: EntityName.taskReminder, version: version,
      deletedAt: deletedAt)
    try ApplyAggregate.tombstoneChildRows(
      db, selectSQL: "SELECT id, version FROM task_checklist_items WHERE task_id = ?",
      parentId: taskId, entityType: EntityName.taskChecklistItem, version: version,
      deletedAt: deletedAt)
  }
}
