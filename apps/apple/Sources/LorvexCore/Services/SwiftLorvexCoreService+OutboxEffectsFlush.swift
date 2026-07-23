import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync
import LorvexWorkflow

/// Sync-effects and lifecycle-plan fan-out for `SwiftLorvexCoreService`'s outbox
/// flush. Translates the workflow-produced effect bundles (`TaskUpdateSyncEffects`,
/// `CreateTaskSyncEffects`, `BatchCreateSyncEffects`, `LifecycleSyncPlan`) into
/// ordered outbox enqueues via the primitive helpers in `+OutboxFlush.swift`.
extension SwiftLorvexCoreService {

  // MARK: - Recurrence-disable sync-effects fan-out

  /// Flush the cross-row work produced by a direct recurrence disable. These
  /// are independent rows changed by the workflow in the same transaction as
  /// the primary task: surviving recurrence neighbors, cancelled reminders,
  /// dependency tombstones, and focus aggregates.
  func flushRecurrenceDisableEffects(
    _ db: Database, hlc: HlcSession, deviceId: String,
    effects: RecurrenceDisableEffects
  ) throws {
    let rerooted = Set(effects.rerootedSuccessorIds)
    let cancelled = Set(effects.cancelledSuccessorIds)
    for taskID in Set(effects.taskUpsertIds).sorted() {
      let intent: TaskRegisterIntent
      if rerooted.contains(taskID) {
        intent = .schedule
      } else if cancelled.contains(taskID) {
        intent = .lifecycle
      } else {
        // The remaining task effect is the predecessor whose rollover
        // authorization was severed.
        intent = .lifecycle
      }
      try enqueueUpsert(
        db, hlc: hlc, deviceId: deviceId, kind: .task, entityId: taskID,
        registerIntent: .task(intent))
    }

    try enqueueUpserts(
      db, hlc: hlc, deviceId: deviceId, kind: .taskReminder,
      entityIds: effects.reminderUpsertIds)
    for edge in effects.deletedDependencyEdges {
      let payload = DependencyEdge.buildDeletePayload(
        taskId: edge.taskId, dependsOnTaskId: edge.dependsOnTaskId,
        version: edge.version, createdAt: edge.createdAt)
      try enqueueDelete(
        db, hlc: hlc, deviceId: deviceId, kind: .taskDependency,
        entityId: DependencyEdge.encodeEntityId(
          taskId: edge.taskId, dependsOnTaskId: edge.dependsOnTaskId),
        payload: payload)
    }
    // `affectedDependentIds` are reload hints only: deleting a dependency edge
    // does not mutate either surviving task row.
    try enqueueUpserts(
      db, hlc: hlc, deviceId: deviceId, kind: .currentFocus,
      entityIds: effects.currentFocusDates)
    try enqueueUpserts(
      db, hlc: hlc, deviceId: deviceId, kind: .focusSchedule,
      entityIds: effects.focusScheduleDates)
  }

  // MARK: - Task-update sync-effects fan-out

  /// Translate a `TaskUpdateSyncEffects` bundle (produced by `update_task` and
  /// the batch variants) into outbox enqueues, in a fixed order: tag edges →
  /// dependency edges → reminders → primary tasks → spawned successors →
  /// cancelled successors → focus-rewire aggregates.
  ///
  /// Edge UPSERTS read their live snapshot; edge DELETES carry the pre-delete
  /// snapshot the effects bundle captured. Reminder and successor rows were
  /// UPDATED (not deleted) by the workflow, so they enqueue as upserts.
  func flushTaskUpdateEffects(
    _ db: Database, hlc: HlcSession, deviceId: String, effects: TaskUpdateSyncEffects,
    primaryRegisterIntents: [String: TaskRegisterIntent]
  ) throws {
    // 1. Tag entity upserts + task_tag edge upserts + edge deletes.
    try enqueueUpserts(db, hlc: hlc, deviceId: deviceId, kind: .tag, entityIds: effects.tagUpsertIds)
    try enqueueTaskTagEdgeUpserts(db, hlc: hlc, deviceId: deviceId, edgeIds: effects.taskTagEdgeUpsertIds)
    for edge in effects.deletedTaskTagEdges {
      let payload = PayloadLoaders.taskTagPayload(
        taskId: edge.taskId, tagId: edge.tagId, version: edge.version, createdAt: edge.createdAt)
      try enqueueDelete(
        db, hlc: hlc, deviceId: deviceId, kind: .taskTag,
        entityId: "\(edge.taskId):\(edge.tagId)", payload: payload)
    }

    // 2. Dependency edge upserts + dependency edge tombstones.
    try enqueueDependencyEdgeUpserts(
      db, hlc: hlc, deviceId: deviceId, edgeIds: effects.dependencyEdgeUpsertIds)
    for edge in effects.deletedDependencyEdges {
      let payload = DependencyEdge.buildDeletePayload(
        taskId: edge.taskId, dependsOnTaskId: edge.dependsOnTaskId,
        version: edge.version, createdAt: edge.createdAt)
      try enqueueDelete(
        db, hlc: hlc, deviceId: deviceId, kind: .taskDependency,
        entityId: DependencyEdge.encodeEntityId(
          taskId: edge.taskId, dependsOnTaskId: edge.dependsOnTaskId),
        payload: payload)
    }

    // 3. Reminder upserts (cancellation + spawn + recurrence-rebase).
    try enqueueUpserts(
      db, hlc: hlc, deviceId: deviceId, kind: .taskReminder, entityIds: effects.reminderUpsertIds)

    // 4. Primary task upserts plus recurrence-neighbor task effects. The
    // primary map is derived from before/after snapshots. Recurrence disable
    // classifies rerooted successors as schedule writes and cancelled
    // successors / severed predecessors as lifecycle writes; do not rely on
    // final-row inference for those side effects because an unrelated register
    // may already own the row's transport `version`.
    let rerootedSuccessorIds = Set(effects.rerootedSuccessorIds)
    let cancelledSuccessorIds = Set(effects.cancelledSuccessors.map(\.successorId))
    let spawnedSuccessorIds = Set(effects.spawnedSuccessors.map(\.successorId))
    for taskID in effects.taskUpsertIds {
      if let intent = primaryRegisterIntents[taskID] {
        guard !intent.isEmpty else { continue }
        try enqueueUpsert(
          db, hlc: hlc, deviceId: deviceId, kind: .task, entityId: taskID,
          registerIntent: .task(intent))
      } else if rerootedSuccessorIds.contains(taskID) {
        try enqueueUpsert(
          db, hlc: hlc, deviceId: deviceId, kind: .task, entityId: taskID,
          registerIntent: .task(.schedule))
      } else if cancelledSuccessorIds.contains(taskID) {
        try enqueueUpsert(
          db, hlc: hlc, deviceId: deviceId, kind: .task, entityId: taskID,
          registerIntent: .task(.lifecycle))
      } else if spawnedSuccessorIds.contains(taskID) {
        // A newly inserted or revived successor owns a wider snapshot than a
        // recurrence-disable neighbor. Its workflow stamps the canonical
        // registers, so retain the snapshot-derived inference here.
        try enqueueUpsert(
          db, hlc: hlc, deviceId: deviceId, kind: .task, entityId: taskID)
      } else {
        // The only remaining non-primary task effect is the predecessor whose
        // rollover authorization was severed by recurrence disable.
        try enqueueUpsert(
          db, hlc: hlc, deviceId: deviceId, kind: .task, entityId: taskID,
          registerIntent: .task(.lifecycle))
      }
    }

    // 5. Spawned recurrence successors + their inherited children.
    for successor in effects.spawnedSuccessors {
      try enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .task, entityId: successor.successorId)
    }
    for edge in effects.spawnedSuccessorTagEdges {
      // `.taskTag` has no single-column PK, so the generic enqueueUpsert path
      // throws unknownEntityType and rolls back the whole transaction. Use the
      // composite-key copied-edge helper, matching the sibling flushes.
      try enqueueCopiedTagEdgeUpsert(db, hlc: hlc, deviceId: deviceId, edge: edge)
    }
    try enqueueUpserts(
      db, hlc: hlc, deviceId: deviceId, kind: .taskChecklistItem,
      entityIds: effects.spawnedSuccessorChecklistItemIds)
    try enqueueUpserts(
      db, hlc: hlc, deviceId: deviceId, kind: .taskReminder,
      entityIds: effects.spawnedSuccessorReminderIds)

    // 6. Cancelled successors (the row was updated to cancelled).
    for successor in effects.cancelledSuccessors {
      try enqueueUpsert(
        db, hlc: hlc, deviceId: deviceId, kind: .task,
        entityId: successor.successorId,
        registerIntent: .task(.lifecycle))
    }

    // 7. Focus-rewire aggregates last — they reference both parent + successor.
    try enqueueUpserts(
      db, hlc: hlc, deviceId: deviceId, kind: .focusSchedule,
      entityIds: effects.rewiredFocusScheduleDates)
    try enqueueUpserts(
      db, hlc: hlc, deviceId: deviceId, kind: .currentFocus,
      entityIds: effects.rewiredCurrentFocusDates)
  }

  /// Translate a `CreateTaskSyncEffects` bundle (produced by `create_task` and
  /// the batch-create variant) into outbox enqueues. `taskUpsertIds` already
  /// carries the primary created task, so no separate primary enqueue is needed.
  /// Ordering matches the task-update flush: tags → dependency edges → reminders
  /// → tasks → spawned successors → focus aggregates.
  func flushCreateTaskEffects(
    _ db: Database, hlc: HlcSession, deviceId: String, effects: CreateTaskSyncEffects
  ) throws {
    try enqueueUpserts(db, hlc: hlc, deviceId: deviceId, kind: .tag, entityIds: effects.tagUpsertIds)
    try enqueueTaskTagEdgeUpserts(
      db, hlc: hlc, deviceId: deviceId, edgeIds: effects.taskTagEdgeUpsertIds)
    try enqueueDependencyEdgeUpserts(
      db, hlc: hlc, deviceId: deviceId, edgeIds: effects.dependencyEdgeUpsertIds)
    try enqueueUpserts(
      db, hlc: hlc, deviceId: deviceId, kind: .taskReminder, entityIds: effects.reminderUpsertIds)
    try enqueueUpserts(
      db, hlc: hlc, deviceId: deviceId, kind: .taskReminder, entityIds: effects.cancelledReminderIds)
    for taskID in effects.taskUpsertIds {
      try enqueueUpsert(
        db, hlc: hlc, deviceId: deviceId, kind: .task, entityId: taskID,
        registerIntent: .task(.all))
    }
    for successor in effects.spawnedSuccessors {
      try enqueueUpsert(
        db, hlc: hlc, deviceId: deviceId, kind: .task, entityId: successor.successorId.asString)
    }
    for edge in effects.spawnedSuccessorTagEdges {
      try enqueueCopiedTagEdgeUpsert(db, hlc: hlc, deviceId: deviceId, edge: edge)
    }
    try enqueueUpserts(
      db, hlc: hlc, deviceId: deviceId, kind: .taskChecklistItem,
      entityIds: effects.spawnedSuccessorChecklistItemIds)
    try enqueueUpserts(
      db, hlc: hlc, deviceId: deviceId, kind: .taskReminder,
      entityIds: effects.spawnedSuccessorReminderIds)
    try enqueueUpserts(
      db, hlc: hlc, deviceId: deviceId, kind: .focusSchedule,
      entityIds: effects.rewiredFocusScheduleDates)
    try enqueueUpserts(
      db, hlc: hlc, deviceId: deviceId, kind: .currentFocus,
      entityIds: effects.rewiredCurrentFocusDates)
  }

  /// Translate a `BatchCreateSyncEffects` bundle (produced by
  /// `batch_create_tasks`) into outbox enqueues. Same fan-out as the single
  /// create plus the cross-task dependency-edge changes the batch can produce
  /// when a later task depends on an earlier one.
  func flushBatchCreateEffects(
    _ db: Database, hlc: HlcSession, deviceId: String, effects: BatchCreateSyncEffects
  ) throws {
    try enqueueUpserts(db, hlc: hlc, deviceId: deviceId, kind: .tag, entityIds: effects.tagUpsertIds)
    try enqueueTaskTagEdgeUpserts(
      db, hlc: hlc, deviceId: deviceId, edgeIds: effects.taskTagEdgeUpsertIds)
    try enqueueDependencyEdgeUpserts(
      db, hlc: hlc, deviceId: deviceId, edgeIds: effects.dependencyEdgeUpsertIds)
    for edge in effects.deletedDependencyEdges {
      let payload = DependencyEdge.buildDeletePayload(
        taskId: edge.taskId, dependsOnTaskId: edge.dependsOnTaskId,
        version: edge.version, createdAt: edge.createdAt)
      try enqueueDelete(
        db, hlc: hlc, deviceId: deviceId, kind: .taskDependency,
        entityId: DependencyEdge.encodeEntityId(
          taskId: edge.taskId, dependsOnTaskId: edge.dependsOnTaskId),
        payload: payload)
    }
    try enqueueUpserts(
      db, hlc: hlc, deviceId: deviceId, kind: .taskReminder, entityIds: effects.reminderUpsertIds)
    try enqueueUpserts(
      db, hlc: hlc, deviceId: deviceId, kind: .taskReminder, entityIds: effects.cancelledReminderIds)
    for taskID in effects.taskUpsertIds {
      try enqueueUpsert(
        db, hlc: hlc, deviceId: deviceId, kind: .task, entityId: taskID,
        registerIntent: .task(.all))
    }
    for successor in effects.spawnedSuccessors {
      try enqueueUpsert(
        db, hlc: hlc, deviceId: deviceId, kind: .task, entityId: successor.successorId.asString)
    }
    for edge in effects.spawnedSuccessorTagEdges {
      try enqueueCopiedTagEdgeUpsert(db, hlc: hlc, deviceId: deviceId, edge: edge)
    }
    try enqueueUpserts(
      db, hlc: hlc, deviceId: deviceId, kind: .taskChecklistItem,
      entityIds: effects.spawnedSuccessorChecklistItemIds)
    try enqueueUpserts(
      db, hlc: hlc, deviceId: deviceId, kind: .taskReminder,
      entityIds: effects.spawnedSuccessorReminderIds)
    try enqueueUpserts(
      db, hlc: hlc, deviceId: deviceId, kind: .focusSchedule,
      entityIds: effects.rewiredFocusScheduleDates)
    try enqueueUpserts(
      db, hlc: hlc, deviceId: deviceId, kind: .currentFocus,
      entityIds: effects.rewiredCurrentFocusDates)
  }

}
