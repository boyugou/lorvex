import GRDB
import LorvexDomain
import LorvexSync
import LorvexWorkflow

extension SwiftLorvexCoreService {
  /// Translate a `LifecycleSyncPlan` (complete / cancel / reopen / defer) into
  /// outbox enqueues for every related entity the transition touched. The
  /// primary task's own upsert is enqueued by the caller.
  func flushLifecyclePlan(
    _ db: Database, hlc: HlcSession, deviceId: String, plan: LifecycleSyncPlan
  ) throws {
    try flushStatusSideEffects(db, hlc: hlc, deviceId: deviceId, status: plan.status)
    try flushStatusSideEffects(db, hlc: hlc, deviceId: deviceId, status: plan.successorCancel)

    try enqueueUpserts(
      db, hlc: hlc, deviceId: deviceId, kind: .taskReminder, entityIds: plan.reopenedReminderIds)

    if let successorId = plan.spawnedSuccessorId {
      try enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .task, entityId: successorId)
    }
    for edge in plan.spawnedSuccessorTagEdges {
      try enqueueCopiedTagEdgeUpsert(db, hlc: hlc, deviceId: deviceId, edge: edge)
    }
    try enqueueUpserts(
      db, hlc: hlc, deviceId: deviceId, kind: .taskChecklistItem,
      entityIds: plan.spawnedSuccessorChecklistItemIds)
    try enqueueUpserts(
      db, hlc: hlc, deviceId: deviceId, kind: .taskReminder,
      entityIds: plan.spawnedSuccessorReminderIds)

    try enqueueUpserts(
      db, hlc: hlc, deviceId: deviceId, kind: .task, entityIds: plan.cancelledSuccessorIds)

    try enqueueUpserts(
      db, hlc: hlc, deviceId: deviceId, kind: .focusSchedule,
      entityIds: plan.rewiredFocusScheduleDates)
    try enqueueUpserts(
      db, hlc: hlc, deviceId: deviceId, kind: .currentFocus,
      entityIds: plan.rewiredCurrentFocusDates)
  }

  /// Translate the flattened `BatchCancelSyncEffects` from
  /// `batch_cancel_tasks_in_list` into outbox enqueues. A batch cancel only
  /// flips each task's status to `cancelled` — the rows survive — so this
  /// upserts the cancelled tasks (Swift's changelog write does not enqueue),
  /// fans out the reminder/dependency-edge side effects, and re-emits any
  /// spawned recurrence successors, their copied children, and the focus
  /// aggregates rewired off the cancelled tasks. It must never DELETE-cascade
  /// the cancelled tasks' children, which still belong to the living rows.
  func flushBatchCancelEffects(
    _ db: Database, hlc: HlcSession, deviceId: String, effects: BatchCancelSyncEffects
  ) throws {
    try enqueueUpserts(
      db, hlc: hlc, deviceId: deviceId, kind: .task, entityIds: effects.taskUpsertIds)
    try flushStatusSideEffects(
      db, hlc: hlc, deviceId: deviceId,
      status: TaskBatchCancel.statusSideEffectPlan(effects))

    for successor in effects.spawnedSuccessors {
      try enqueueUpsert(
        db, hlc: hlc, deviceId: deviceId, kind: .task, entityId: successor.successorId.rawValue)
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

  private func flushStatusSideEffects(
    _ db: Database, hlc: HlcSession, deviceId: String, status: StatusSideEffectSyncPlan
  ) throws {
    try enqueueUpserts(
      db, hlc: hlc, deviceId: deviceId, kind: .taskReminder, entityIds: status.cancelledReminderIds)
    for edge in status.deletedDependencyEdges {
      let payload = DependencyEdge.buildDeletePayload(
        taskId: edge.taskId, dependsOnTaskId: edge.dependsOnTaskId,
        version: edge.version, createdAt: edge.createdAt)
      try enqueueDelete(
        db, hlc: hlc, deviceId: deviceId, kind: .taskDependency,
        entityId: DependencyEdge.encodeEntityId(
          taskId: edge.taskId, dependsOnTaskId: edge.dependsOnTaskId),
        payload: payload)
    }
  }
}
