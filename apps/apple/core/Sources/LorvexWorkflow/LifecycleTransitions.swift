import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Transition orchestrators that wrap a status primitive with snapshot
/// reads, recurrence spawn (`→ completed` / non-series `→ cancelled`),
/// successor cancellation (`→ open` from `completed`), and the data-
/// layer side-effect cascade. Pipeline order:
///
/// 1. `readTaskSnapshot` + `readActiveTaskReminderTimes` (only when the
///    transition crosses into `completed` or `cancelled`).
/// 2. `writeStatusAndMetadata` (LWW-gated; 0 rows ⇒ ``StoreError/staleVersion``).
/// 3. `LifecycleSideEffects.apply` — composes ``StatusSideEffects``,
///    plus the injected ``RecurrenceSpawnHandler``'s spawn /
///    cancel-successor branches.
///
/// Each orchestrator must run inside the caller's write transaction
/// (`DatabaseWriter.write { db in … }`); a precondition asserts
/// `db.isInsideTransaction` so a missing wrapper fails loudly.
public enum LifecycleTransitions {
  // MARK: - Generic status patch

  /// Generic `update_task(status=...)` orchestrator. Owns the status row
  /// mutation; callers MUST NOT write status via the generic patch.
  public static func applyLifecycleTransition(
    _ db: Database,
    taskId: TaskId,
    oldStatus: TaskStatus,
    newStatus: TaskStatus,
    now: String,
    reminderVersion: String,
    handler: RecurrenceSpawnHandler = LifecycleRecurrenceSpawnHandler()
  ) throws -> LifecycleTransitionResult {
    precondition(
      db.isInsideTransaction,
      "applyLifecycleTransition must run inside a transaction "
        + "(write_status + cascade side-effects + recurrence spawn must "
        + "commit atomically)")

    try LifecycleStatus.rejectTerminalToTerminal(
      taskId: taskId, oldStatus: oldStatus, newStatus: newStatus)

    // Starting a task (→ in_progress) requires its dependencies to be resolved.
    if newStatus == .inProgress && oldStatus != .inProgress {
      try LifecycleStatus.rejectStartWhenDependencyBlocked(db, taskId: taskId)
    }

    let snapshot = try LifecycleSnapshot.readTaskSnapshot(db, taskId: taskId)
    let activeReminderTimes: [String]
    if (newStatus == .completed && oldStatus != .completed)
      || (newStatus == .cancelled && oldStatus != .cancelled)
    {
      activeReminderTimes = try LifecycleSnapshot.readActiveTaskReminderTimes(
        db, taskId: taskId)
    } else {
      activeReminderTimes = []
    }

    let rows = try LifecycleWriteStatus.writeStatusAndMetadata(
      db, taskId: taskId,
      oldStatus: oldStatus, newStatus: newStatus,
      now: now, version: reminderVersion)
    if rows == 0 {
      throw StoreError.staleVersion(entity: "task", id: taskId.asString)
    }

    return try LifecycleSideEffects.apply(
      db,
      input: LifecycleSideEffectsInput(
        taskId: taskId,
        oldStatus: oldStatus,
        newStatus: newStatus,
        now: now,
        reminderVersion: reminderVersion,
        snapshot: snapshot,
        preTransitionActiveReminderTimes: activeReminderTimes),
      handler: handler)
  }

  // MARK: - Dedicated completion surface

  /// Dedicated completion orchestrator. Owns: status mutation →
  /// `completed`, reminder cancellation (via ``LifecycleStatus``), and
  /// recurrence spawn. Does NOT re-run ``StatusSideEffects`` — the
  /// primitive `completeTask` already handles reminders and completion
  /// does not remove dependency edges.
  public static func applyCompletionTransition(
    _ db: Database,
    taskId: TaskId,
    now: String,
    reminderVersion: String,
    handler: RecurrenceSpawnHandler = LifecycleRecurrenceSpawnHandler()
  ) throws -> CompletionLifecycleTransitionResult {
    precondition(
      db.isInsideTransaction,
      "applyCompletionTransition must run inside a transaction "
        + "(complete_task + recurrence spawn must commit atomically)")

    let snapshot = try LifecycleSnapshot.readTaskSnapshot(db, taskId: taskId)
    let activeReminderTimes = try LifecycleSnapshot.readActiveTaskReminderTimes(
      db, taskId: taskId)

    let completion = try LifecycleStatus.completeTask(
      db, taskId: taskId, now: now, reminderVersion: reminderVersion)

    var spawnedSuccessorId: String? = nil
    var spawnedTagEdges: [CopiedTagEdge] = []
    var spawnedChecklistItemIds: [String] = []
    var spawnedReminderIds: [String] = []
    var rewiredFocusScheduleDates: [String] = []
    var rewiredCurrentFocusDates: [String] = []

    if completion.updated, let snap = snapshot,
      let rule = snap.recurrence, !rule.isEmpty
    {
      if let spawn = try handler.spawnRecurrenceSuccessor(
        db, taskId: taskId, snapshot: snap,
        activeReminderTimes: activeReminderTimes,
        now: now, reminderVersion: reminderVersion)
      {
        spawnedSuccessorId = spawn.successorId
        spawnedTagEdges = spawn.copiedTagEdges
        spawnedChecklistItemIds = spawn.copiedChecklistItemIds
        spawnedReminderIds = spawn.copiedReminderIds
        rewiredFocusScheduleDates = spawn.rewiredFocusScheduleDates
        rewiredCurrentFocusDates = spawn.rewiredCurrentFocusDates
      }
    }

    return CompletionLifecycleTransitionResult(
      updated: completion.updated,
      cancelledReminderIds: completion.cancelledReminderIds,
      spawnedSuccessorId: spawnedSuccessorId,
      spawnedSuccessorTagEdges: spawnedTagEdges,
      spawnedSuccessorChecklistItemIds: spawnedChecklistItemIds,
      spawnedSuccessorReminderIds: spawnedReminderIds,
      rewiredFocusScheduleDates: rewiredFocusScheduleDates,
      rewiredCurrentFocusDates: rewiredCurrentFocusDates)
  }

  // MARK: - Dedicated cancel surface

  /// Dedicated cancel orchestrator.
  ///
  /// - `cancelSeries == false`: cancel this task; if recurring, spawn
  ///   the next occurrence (skip-this-one).
  /// - `cancelSeries == true`: cancel this task; if recurring, clear all
  ///   recurrence fields (rule, group id, canonical_occurrence_date,
  ///   exception list, instance key) and do NOT spawn. Requires a
  ///   caller-supplied `seriesClearVersion` so the recurrence-clear UPDATE
  ///   ships its own LWW stamp distinct from the cancel write.
  /// - For non-recurring tasks, `cancelSeries` is ignored.
  public static func applyCancelTransition(
    _ db: Database,
    taskId: TaskId,
    now: String,
    reminderVersion: String,
    cancelSeries: Bool,
    seriesClearVersion: String?,
    handler: RecurrenceSpawnHandler = LifecycleRecurrenceSpawnHandler()
  ) throws -> CancelLifecycleTransitionResult {
    precondition(
      db.isInsideTransaction,
      "applyCancelTransition must run inside a transaction "
        + "(cancel_task + recurrence spawn/clear must commit atomically)")

    let snapshot = try LifecycleSnapshot.readTaskSnapshot(db, taskId: taskId)
    let activeReminderTimes = try LifecycleSnapshot.readActiveTaskReminderTimes(
      db, taskId: taskId)

    let cancel = try LifecycleStatus.cancelTask(
      db, taskId: taskId, now: now, reminderVersion: reminderVersion)

    if !cancel.updated {
      return CancelLifecycleTransitionResult(
        updated: false,
        cancelledReminderIds: [],
        affectedDependentIds: [],
        deletedDependencyEdges: [],
        spawnedSuccessorId: nil,
        spawnedSuccessorTagEdges: [],
        spawnedSuccessorChecklistItemIds: [],
        spawnedSuccessorReminderIds: [],
        rewiredFocusScheduleDates: [],
        rewiredCurrentFocusDates: [])
    }

    var spawnedSuccessorId: String? = nil
    var spawnedTagEdges: [CopiedTagEdge] = []
    var spawnedChecklistItemIds: [String] = []
    var spawnedReminderIds: [String] = []
    var rewiredFocusScheduleDates: [String] = []
    var rewiredCurrentFocusDates: [String] = []

    if let snap = snapshot, let rule = snap.recurrence, !rule.isEmpty {
      if cancelSeries {
        guard let seriesClearVersion = seriesClearVersion else {
          throw StoreError.invariant(
            "apply_cancel_transition: cancel_series recurrence clear "
              + "requires a caller-supplied HLC version")
        }
        try db.execute(
          sql:
            "UPDATE tasks SET recurrence = NULL, recurrence_group_id = NULL, "
            + "canonical_occurrence_date = NULL, "
            + "recurrence_instance_key = NULL, "
            + "recurrence_rollover_state = 'ended', recurrence_successor_id = NULL, "
            + "schedule_version = ?3, lifecycle_version = ?3, "
            + "version = ?3, updated_at = ?2 "
            + "WHERE id = ?1 AND ?3 > version",
          arguments: [taskId.asString, now, seriesClearVersion])
        let rows = db.changesCount
        if rows != 0 {
          try RecurrenceExceptionsRepo.replaceTaskExceptions(
            db, taskId: taskId.asString, dates: [])
        }
        if rows == 0 {
          throw StoreError.staleVersion(entity: "task", id: taskId.asString)
        }
      } else {
        if let spawn = try handler.spawnRecurrenceSuccessor(
          db, taskId: taskId, snapshot: snap,
          activeReminderTimes: activeReminderTimes,
          now: now, reminderVersion: reminderVersion)
        {
          spawnedSuccessorId = spawn.successorId
          spawnedTagEdges = spawn.copiedTagEdges
          spawnedChecklistItemIds = spawn.copiedChecklistItemIds
          spawnedReminderIds = spawn.copiedReminderIds
          rewiredFocusScheduleDates = spawn.rewiredFocusScheduleDates
          rewiredCurrentFocusDates = spawn.rewiredCurrentFocusDates
        }
      }
    }

    return CancelLifecycleTransitionResult(
      updated: true,
      cancelledReminderIds: cancel.cancelledReminderIds,
      affectedDependentIds: cancel.affectedDependentIds,
      deletedDependencyEdges: cancel.deletedDependencyEdges,
      spawnedSuccessorId: spawnedSuccessorId,
      spawnedSuccessorTagEdges: spawnedTagEdges,
      spawnedSuccessorChecklistItemIds: spawnedChecklistItemIds,
      spawnedSuccessorReminderIds: spawnedReminderIds,
      rewiredFocusScheduleDates: rewiredFocusScheduleDates,
      rewiredCurrentFocusDates: rewiredCurrentFocusDates)
  }

  // MARK: - Dedicated reopen surface

  /// Dedicated reopen orchestrator. Wraps the primitive `reopenTask`
  /// (status + reminders) with the side-effect cascade (cancel
  /// previously-spawned recurrence successors via the injected handler).
  public static func applyReopenTransition(
    _ db: Database,
    taskId: TaskId,
    oldStatus: TaskStatus,
    now: String,
    reminderVersion: String,
    handler: RecurrenceSpawnHandler = LifecycleRecurrenceSpawnHandler()
  ) throws -> ReopenLifecycleTransitionResult {
    precondition(
      db.isInsideTransaction,
      "applyReopenTransition must run inside a transaction "
        + "(reopen_task + successor cancel cascade must commit atomically)")

    let snapshot = try LifecycleSnapshot.readTaskSnapshot(db, taskId: taskId)
    let reopen = try LifecycleStatus.reopenTask(
      db, taskId: taskId, now: now, reminderVersion: reminderVersion)
    let transition: LifecycleTransitionResult
    if reopen.updated {
      transition = try LifecycleSideEffects.apply(
        db,
        input: LifecycleSideEffectsInput(
          taskId: taskId,
          oldStatus: oldStatus,
          newStatus: .open,
          now: now,
          reminderVersion: reminderVersion,
          snapshot: snapshot,
          preTransitionActiveReminderTimes: []),
        handler: handler)
    } else {
      transition = LifecycleSideEffects.emptyResult
    }
    return ReopenLifecycleTransitionResult(
      updated: reopen.updated,
      reopenedReminderIds: reopen.reopenedReminderIds,
      transition: transition)
  }
}
