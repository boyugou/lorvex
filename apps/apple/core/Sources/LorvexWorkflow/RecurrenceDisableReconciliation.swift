import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Cross-row effects produced when recurrence is disabled. All listed rows are
/// mutated inside the same transaction as the task's recurrence skeleton.
public struct RecurrenceDisableEffects: Sendable, Equatable {
  public var taskUpsertIds: [String] = []
  public var cancelledSuccessorIds: [String] = []
  public var rerootedSuccessorIds: [String] = []
  public var reminderUpsertIds: [String] = []
  public var affectedDependentIds: [String] = []
  public var deletedDependencyEdges: [DeletedDependencyEdge] = []
  public var currentFocusDates: [String] = []
  public var focusScheduleDates: [String] = []

  public init() {}

  mutating func normalize() {
    taskUpsertIds = Array(Set(taskUpsertIds)).sorted()
    cancelledSuccessorIds = Array(Set(cancelledSuccessorIds)).sorted()
    rerootedSuccessorIds = Array(Set(rerootedSuccessorIds)).sorted()
    reminderUpsertIds = Array(Set(reminderUpsertIds)).sorted()
    affectedDependentIds = Array(Set(affectedDependentIds)).sorted()
    currentFocusDates = Array(Set(currentFocusDates)).sorted()
    focusScheduleDates = Array(Set(focusScheduleDates)).sorted()
  }
}

/// Local counterpart of sync's parent/child rollover reconciliation. A local
/// recurrence-clear must converge immediately; waiting for the device's own
/// CloudKit envelope to round-trip would leave local UI and peers disagreeing.
enum RecurrenceDisableReconciliation {
  static func apply(
    _ db: Database,
    taskId: String,
    spawnedFrom: String?,
    recurrenceGroupId: String?,
    recordedSuccessorId: String?,
    decisionVersion: String,
    now: String
  ) throws -> RecurrenceDisableEffects {
    var effects = RecurrenceDisableEffects()
    var visited: Set<String> = []

    if let predecessorId = spawnedFrom {
      guard let recurrenceGroupId else {
        throw StoreError.invariant(
          "generated task \(taskId) has no recurrence_group_id before recurrence disable")
      }
      let expected = TaskRecurrenceSuccessorID.make(
        parentTaskId: predecessorId, recurrenceGroupId: recurrenceGroupId)
      guard expected == taskId else {
        throw StoreError.invariant(
          "task \(taskId) is not the deterministic successor of \(predecessorId)")
      }
      if try severPredecessor(
        db, predecessorId: predecessorId, successorId: taskId,
        version: decisionVersion, now: now)
      {
        effects.taskUpsertIds.append(predecessorId)
      }
    }

    var candidates = Set(
      try String.fetchAll(
        db, sql: "SELECT id FROM tasks WHERE spawned_from = ?1", arguments: [taskId]))
    if let recordedSuccessorId, recordedSuccessorId != taskId {
      candidates.insert(recordedSuccessorId)
    }
    for successorId in candidates.sorted() {
      try reconcileSuccessor(
        db, parentId: taskId, successorId: successorId,
        decisionVersion: decisionVersion, now: now,
        visited: &visited, effects: &effects)
    }
    effects.normalize()
    return effects
  }

  private static func severPredecessor(
    _ db: Database,
    predecessorId: String,
    successorId: String,
    version: String,
    now: String
  ) throws -> Bool {
    guard
      let row = try Row.fetchOne(
        db,
        sql:
          "SELECT recurrence_rollover_state, recurrence_successor_id, lifecycle_version "
          + "FROM tasks WHERE id = ?1",
        arguments: [predecessorId])
    else { return false }
    let state: String = row[0]
    let recorded: String? = row[1]
    guard recorded == successorId, state == "authorized" || state == "revoked" else {
      return false
    }
    let lifecycleVersion: String = row[2]
    guard version > lifecycleVersion else {
      throw StoreError.staleVersion(entity: EntityName.task, id: predecessorId)
    }
    let nextState = state == "authorized" ? "ended" : "none"
    try db.execute(
      sql:
        "UPDATE tasks SET recurrence_rollover_state = ?1, "
        + "recurrence_successor_id = NULL, lifecycle_version = ?2, "
        + "version = MAX(version, ?2), updated_at = ?3 WHERE id = ?4",
      arguments: [nextState, version, now, predecessorId])
    return db.changesCount == 1
  }

  private static func reconcileSuccessor(
    _ db: Database,
    parentId: String,
    successorId: String,
    decisionVersion: String,
    now: String,
    visited: inout Set<String>,
    effects: inout RecurrenceDisableEffects
  ) throws {
    guard visited.insert(successorId).inserted else {
      throw StoreError.invariant("recurrence successor lineage contains a cycle at \(successorId)")
    }
    guard
      let row = try Row.fetchOne(
        db,
        sql:
          "SELECT spawned_from, recurrence_group_id, content_version, schedule_version, "
          + "lifecycle_version, archive_version, version, "
          + "recurrence_successor_id FROM tasks WHERE id = ?1",
        arguments: [successorId])
    else { return }
    let spawnedFrom: String? = row[0]
    guard spawnedFrom == parentId else { return }
    guard let groupId: String = row[1] else {
      throw StoreError.invariant(
        "generated task \(successorId) has no recurrence_group_id")
    }
    let expected = TaskRecurrenceSuccessorID.make(
      parentTaskId: parentId, recurrenceGroupId: groupId)
    guard expected == successorId else {
      throw StoreError.invariant(
        "task \(successorId) is not the deterministic successor of \(parentId)")
    }

    let clocks = TaskRolloverRegisterClocks(
      content: row[2], schedule: row[3], lifecycle: row[4], archive: row[5])
    switch try TaskRolloverPolicy.resolveContradiction(
      decisionVersion: decisionVersion, childClocks: clocks)
    {
    case .rerootAdvancedSuccessor:
      let existingSchedule: String = row[3]
      let existingVersion: String = row[6]
      try db.execute(
        sql:
          "UPDATE tasks SET spawned_from = NULL, spawned_from_version = NULL, "
          + "schedule_version = ?1, version = ?2, updated_at = ?3 WHERE id = ?4",
        arguments: [
          max(existingSchedule, decisionVersion),
          max(existingVersion, decisionVersion), now, successorId,
        ])
      effects.taskUpsertIds.append(successorId)
      effects.rerootedSuccessorIds.append(successorId)

    case .cancelStableSuccessor:
      let descendantId: String? = row[7]
      try db.execute(
        sql:
          "UPDATE tasks SET status = 'cancelled', completed_at = NULL, "
          + "recurrence_rollover_state = 'ended', recurrence_successor_id = NULL, "
          + "lifecycle_version = ?1, version = MAX(version, ?1), updated_at = ?2 "
          + "WHERE id = ?3",
        arguments: [decisionVersion, now, successorId])
      effects.taskUpsertIds.append(successorId)
      effects.cancelledSuccessorIds.append(successorId)
      effects.reminderUpsertIds.append(contentsOf:
        try LifecycleReminders.cancelActiveReminders(
          db, taskId: TaskId(trusted: successorId), now: now,
          version: decisionVersion))
      let dependencies = try LifecycleDependencies.detachTaskDependencyEdges(
        db, taskId: TaskId(trusted: successorId))
      effects.affectedDependentIds.append(contentsOf: dependencies.affected)
      effects.deletedDependencyEdges.append(contentsOf: dependencies.deleted)
      try removeFocusReferences(db, taskId: successorId, effects: &effects)

      var descendants = Set(
        try String.fetchAll(
          db, sql: "SELECT id FROM tasks WHERE spawned_from = ?1",
          arguments: [successorId]))
      if let descendantId, descendantId != successorId {
        descendants.insert(descendantId)
      }
      for childId in descendants.sorted() {
        try reconcileSuccessor(
          db, parentId: successorId, successorId: childId,
          decisionVersion: decisionVersion, now: now,
          visited: &visited, effects: &effects)
      }
    }
  }

  private static func removeFocusReferences(
    _ db: Database,
    taskId: String,
    effects: inout RecurrenceDisableEffects
  ) throws {
    effects.currentFocusDates.append(contentsOf:
      try String.fetchAll(
        db,
        sql: "SELECT DISTINCT date FROM current_focus_items WHERE task_id = ?1",
        arguments: [taskId]))
    effects.focusScheduleDates.append(contentsOf:
      try String.fetchAll(
        db,
        sql:
          "SELECT DISTINCT date FROM focus_schedule_blocks WHERE task_id = ?1",
        arguments: [taskId]))
    try db.execute(
      sql: "DELETE FROM current_focus_items WHERE task_id = ?1", arguments: [taskId])
    try db.execute(
      sql: "DELETE FROM focus_schedule_blocks WHERE task_id = ?1", arguments: [taskId])
  }
}
