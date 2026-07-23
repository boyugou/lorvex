import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Recurrence skeleton + EXDATE-preserving patch for a single-row task
/// update. Forwards
/// the prepared recurrence / due-date three-state patch to
/// ``RecurrenceConfig/applyRecurrenceChangeInTx(_:taskId:recurrencePatch:dueDatePatch:today:version:now:)``
/// which owns the co-application rules between the recurring skeleton
/// and the anchoring `due_date` plus the EXDATE list preservation policy.
public enum TaskUpdateRecurrence {

  public static func applyRecurrencePatch(
    _ db: Database,
    hlc: HlcSession,
    taskId: TaskId,
    prepared: PreparedTaskUpdate,
    now: String,
    effects: inout TaskUpdateSyncEffects
  ) throws {
    let today = try WorkflowTimezone.todayYmdForConn(db)
    let version = hlc.nextVersionString()
    do {
      let result = try RecurrenceConfig.applyRecurrenceChangeWithEffectsInTx(
        db, taskId: taskId,
        recurrencePatch: prepared.newRecurrence,
        dueDatePatch: prepared.pendingDueDatePatch,
        today: today, version: version, now: now)
      try collectDisableEffects(db, result.disableEffects, into: &effects)
    } catch let e as RecurrenceConfig.ChangeError {
      throw mapRecurrenceError(e)
    }
  }

  private static func collectDisableEffects(
    _ db: Database,
    _ disable: RecurrenceDisableEffects,
    into effects: inout TaskUpdateSyncEffects
  ) throws {
    let cancelled = Set(disable.cancelledSuccessorIds)
    effects.taskUpsertIds.append(contentsOf:
      disable.taskUpsertIds.filter { !cancelled.contains($0) })
    effects.rerootedSuccessorIds.append(contentsOf: disable.rerootedSuccessorIds)
    effects.reminderUpsertIds.append(contentsOf: disable.reminderUpsertIds)
    effects.affectedDependentIds.append(contentsOf: disable.affectedDependentIds)
    effects.deletedDependencyEdges.append(contentsOf: disable.deletedDependencyEdges)
    effects.rewiredCurrentFocusDates.append(contentsOf: disable.currentFocusDates)
    effects.rewiredFocusScheduleDates.append(contentsOf: disable.focusScheduleDates)
    for successorId in disable.cancelledSuccessorIds {
      let task = try TaskResponse.loadEnrichedTaskJSON(
        db, taskId: TaskId(trusted: successorId))
      effects.cancelledSuccessors.append(
        UpdateTaskCancelledSuccessor(
          successorId: successorId,
          summary: "Cancelled recurrence successor after recurrence was removed",
          afterTask: task))
    }
  }

  /// Whether the prepared patch touches recurrence or due-date.
  public static func recurrencePatchPresent(_ prepared: PreparedTaskUpdate) -> Bool {
    return prepared.newRecurrence.isSetOrClear
      || prepared.pendingDueDatePatch.isSetOrClear
  }

  private static func mapRecurrenceError(
    _ error: RecurrenceConfig.ChangeError
  ) -> StoreError {
    switch error {
    case .clearDueDateOnRecurring:
      return StoreError.validation("recurring tasks must have a due_date")
    case .staleVersion(let taskId):
      return StoreError.staleVersion(entity: EntityName.task, id: taskId)
    }
  }
}
