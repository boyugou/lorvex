import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Status transition + lifecycle plan collection for a single-row task
/// update. Dispatches to
/// ``LifecycleTransitions/applyReopenTransition(_:taskId:oldStatus:now:reminderVersion:handler:)``
/// for reopens and
/// ``LifecycleTransitions/applyLifecycleTransition(_:taskId:oldStatus:newStatus:now:reminderVersion:handler:)``
/// for every other direction, then folds the resulting
/// ``LifecycleSyncPlan`` into the row's accumulating
/// ``TaskUpdateSyncEffects``.
public enum TaskUpdateStatus {

  /// Apply a status transition. No-op when `nextStatus == nil`.
  public static func applyStatusTransition(
    _ db: Database,
    hlc: HlcSession,
    taskId: TaskId,
    nextStatus: String?,
    beforeStatus: String,
    now: String,
    effects: inout TaskUpdateSyncEffects,
    recurrenceHandler: RecurrenceSpawnHandler = LifecycleRecurrenceSpawnHandler()
  ) throws {
    guard let status = nextStatus else { return }
    guard let before = TaskStatus.parse(beforeStatus) else {
      throw StoreError.validation(
        "Invalid status '\(beforeStatus)'. "
          + "Expected one of: open, in_progress, completed, cancelled, someday")
    }
    if status == StatusName.open && beforeStatus != StatusName.open {
      let reminderVersion = hlc.nextVersionString()
      let reopen = try LifecycleTransitions.applyReopenTransition(
        db, taskId: taskId, oldStatus: before, now: now,
        reminderVersion: reminderVersion, handler: recurrenceHandler)
      try collectLifecyclePlan(
        db,
        parentTaskId: taskId.asString,
        spawnedSummary: "Spawned recurrence successor from status transition",
        cancelledSummary: "Cancelled recurring successor (task reopened via update)",
        plan: LifecycleSyncPlan.from(reopen: reopen),
        effects: &effects)
    } else {
      guard let next = TaskStatus.parse(status) else {
        throw StoreError.validation(
          "Invalid status '\(status)'. "
            + "Expected one of: open, in_progress, completed, cancelled, someday")
      }
      let reminderVersion = hlc.nextVersionString()
      let transition = try LifecycleTransitions.applyLifecycleTransition(
        db, taskId: taskId, oldStatus: before, newStatus: next, now: now,
        reminderVersion: reminderVersion, handler: recurrenceHandler)
      try collectLifecyclePlan(
        db,
        parentTaskId: taskId.asString,
        spawnedSummary: "Spawned recurrence successor from status transition",
        cancelledSummary: "Cancelled recurring successor (task reopened via update)",
        plan: LifecycleSyncPlan.from(transition: transition),
        effects: &effects)
    }
  }

  private static func collectLifecyclePlan(
    _ db: Database,
    parentTaskId: String,
    spawnedSummary: String,
    cancelledSummary: String,
    plan: LifecycleSyncPlan,
    effects: inout TaskUpdateSyncEffects
  ) throws {
    effects.reminderUpsertIds.append(contentsOf: plan.status.cancelledReminderIds)
    effects.reminderUpsertIds.append(contentsOf: plan.reopenedReminderIds)
    effects.affectedDependentIds.append(contentsOf: plan.status.affectedDependentIds)
    effects.deletedDependencyEdges.append(
      contentsOf: plan.status.deletedDependencyEdges)
    effects.affectedDependentIds.append(
      contentsOf: plan.successorCancel.affectedDependentIds)
    effects.deletedDependencyEdges.append(
      contentsOf: plan.successorCancel.deletedDependencyEdges)
    effects.spawnedSuccessorTagEdges.append(
      contentsOf: plan.spawnedSuccessorTagEdges)
    effects.spawnedSuccessorChecklistItemIds.append(
      contentsOf: plan.spawnedSuccessorChecklistItemIds)
    effects.spawnedSuccessorReminderIds.append(
      contentsOf: plan.spawnedSuccessorReminderIds)
    effects.rewiredFocusScheduleDates.append(
      contentsOf: plan.rewiredFocusScheduleDates)
    effects.rewiredCurrentFocusDates.append(
      contentsOf: plan.rewiredCurrentFocusDates)
    if let successorId = plan.spawnedSuccessorId {
      let successor = try TaskResponse.loadEnrichedTaskJSON(
        db, taskId: TaskId(trusted: successorId))
      effects.taskUpsertIds.append(successorId)
      effects.spawnedSuccessors.append(
        UpdateTaskSpawnedSuccessor(
          successorId: successorId,
          summary: spawnedSummary,
          afterTask: successor))
      effects.focusRewireAudits.append(
        UpdateTaskFocusRewireAudit(
          parentTaskId: parentTaskId,
          successorId: successorId,
          focusScheduleDates: plan.rewiredFocusScheduleDates,
          currentFocusDates: plan.rewiredCurrentFocusDates))
    }
    for successorId in plan.cancelledSuccessorIds {
      let successor = try TaskResponse.loadEnrichedTaskJSON(
        db, taskId: TaskId(trusted: successorId))
      effects.taskUpsertIds.append(successorId)
      effects.cancelledSuccessors.append(
        UpdateTaskCancelledSuccessor(
          successorId: successorId,
          summary: cancelledSummary,
          afterTask: successor))
    }
  }
}
