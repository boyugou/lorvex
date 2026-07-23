import Foundation
import GRDB
import LorvexDomain
import LorvexStore

extension TaskUpdate {

  /// Apply a single typed task update: opens its own immediate
  /// transaction, runs the shared per-row apply, re-runs the dependency-
  /// cycle validator over the final edge state, and reloads the
  /// enriched task JSON for the response. The caller drives the HLC
  /// session and is responsible for flushing
  /// ``TaskUpdateSyncEffects`` to the outbox + writing the audit row +
  /// bumping `local_change_seq`.
  public static func updateTask(
    _ writer: any DatabaseWriter,
    hlc: HlcSession,
    input rawInput: TaskUpdateInput,
    recurrenceHandler: RecurrenceSpawnHandler = LifecycleRecurrenceSpawnHandler()
  ) throws -> UpdatedTaskOutcome {
    var input = rawInput
    TaskUpdateSanitize.sanitizeInput(&input)
    try TaskUpdatePreparation.validateTaskIdShape(input.id, fieldName: "id")
    let taskId = input.id

    return try StoreTransactions.withImmediateTransaction(writer) { db in
      let typedTaskId = TaskId(trusted: taskId)
      let beforeTask = try TaskResponse.loadEnrichedTaskJSON(db, taskId: typedTaskId)
      let beforeStatus: String
      if case .object(let obj) = beforeTask, let v = obj["status"],
        case .string(let s) = v
      {
        beforeStatus = s
      } else {
        throw StoreError.invariant(
          "update_task before-task: missing string field `status`")
      }
      let now = SyncTimestampFormat.syncTimestampNow()
      var syncEffects = TaskUpdateSyncEffects()
      var depChangedIds: [String] = []
      try applySingleUpdateInSavepoint(
        db,
        hlc: hlc,
        update: input,
        beforeStatus: beforeStatus,
        now: now,
        syncEffects: &syncEffects,
        depChangedIds: &depChangedIds,
        recurrenceHandler: recurrenceHandler)
      try revalidateDependencyCycles(db, depChangedIds: depChangedIds, errorContext: "update_task")

      let updatedTasks = try TaskResponse.loadEnrichedTasksJSON(
        db, taskIds: [taskId])
      guard let updatedTask = updatedTasks.first else {
        throw StoreError.invariant("update_task after-task: row vanished")
      }
      let title: String
      if case .object(let obj) = updatedTask, let v = obj["title"],
        case .string(let s) = v
      {
        title = s
      } else {
        title = ""
      }
      let summary = "Updated task '\(title)'"
      let payload: JSONValue = .object([
        "task": updatedTask,
      ])

      return UpdatedTaskOutcome(
        taskId: taskId,
        beforeTask: beforeTask,
        updatedTask: updatedTask,
        payload: payload,
        summary: summary,
        syncEffects: syncEffects)
    }
  }

  /// Apply a single task update inside an already-open transaction.
  /// The caller owns: the outer transaction boundary and the cross-row
  /// dependency-cycle re-validation after every row's edges land.
  ///
  /// Pushes the row's id onto `depChangedIds` when the patch mutates the
  /// `task_dependencies` edge set so the caller can re-run the cycle
  /// validator with the final, post-update edge state.
  public static func applySingleUpdateInSavepoint(
    _ db: Database,
    hlc: HlcSession,
    update: TaskUpdateInput,
    beforeStatus: String,
    now: String,
    syncEffects: inout TaskUpdateSyncEffects,
    depChangedIds: inout [String],
    recurrenceHandler: RecurrenceSpawnHandler = LifecycleRecurrenceSpawnHandler()
  ) throws {
    let prepared = try TaskUpdatePreparation.prepareTaskUpdate(
      db, update: update, beforeStatus: beforeStatus)
    let typedId = TaskId(trusted: update.id)

    try TaskUpdateRow.applyPrimaryRowPatch(
      db, hlc: hlc, taskId: update.id, prepared: prepared, now: now)

    // Apply recurrence BEFORE reopen-side lifecycle WHEN the rule is
    // being REPLACED (`Patch::Set`) — so a joint reopen+rule-swap
    // patch spawns the next occurrence using the replacement rule.
    //
    // `Patch::Clear` is NOT treated as a rule change for ordering
    // purposes: clearing would wipe the series identity + durable
    // authorization BEFORE the reopen-cancel cascade can validate and
    // rewind the exact deterministic successor. Routing `Clear` through
    // the post-reopen branch lets the lifecycle owner consume the intact
    // pre-patch lineage first.
    //
    // Due-date-only recurrence patches (rule unchanged) also defer
    // past the reopen pass for the same reason.
    let ruleIsChanging: Bool
    if case .set = prepared.newRecurrence { ruleIsChanging = true } else {
      ruleIsChanging = false
    }
    let recurrencePatchActive = TaskUpdateRecurrence.recurrencePatchPresent(prepared)
    if ruleIsChanging {
      try TaskUpdateRecurrence.applyRecurrencePatch(
        db, hlc: hlc, taskId: typedId, prepared: prepared, now: now,
        effects: &syncEffects)
    }

    let statusReopensTask =
      prepared.newStatus == StatusName.open && beforeStatus != StatusName.open
    if statusReopensTask {
      try TaskUpdateStatus.applyStatusTransition(
        db, hlc: hlc, taskId: typedId,
        nextStatus: prepared.newStatus,
        beforeStatus: beforeStatus, now: now,
        effects: &syncEffects,
        recurrenceHandler: recurrenceHandler)
    }
    // Recurrence patches whose rule is NOT being replaced
    // (`Patch::Clear` and due-date-only re-anchors) run after the
    // reopen pass. They still run before the non-reopen status
    // transition because the due-date / rule columns are part of the
    // row's canonical post-patch state and downstream effects
    // (depending status, tag cascade) must observe the final values.
    if recurrencePatchActive && !ruleIsChanging {
      try TaskUpdateRecurrence.applyRecurrencePatch(
        db, hlc: hlc, taskId: typedId, prepared: prepared, now: now,
        effects: &syncEffects)
    }
    let nextStatusForNonReopen: String? = statusReopensTask ? nil : prepared.newStatus
    try TaskUpdateStatus.applyStatusTransition(
      db, hlc: hlc, taskId: typedId,
      nextStatus: nextStatusForNonReopen,
      beforeStatus: beforeStatus, now: now,
      effects: &syncEffects,
      recurrenceHandler: recurrenceHandler)

    let statusBecameCancelled =
      prepared.newStatus == StatusName.cancelled
      && beforeStatus != StatusName.cancelled
    if prepared.changedDeps && !statusBecameCancelled {
      if let deps = prepared.newDependsOn {
        try TaskUpdateDependencies.replaceDependencyEdges(
          db, hlc: hlc, taskId: typedId, newDependsOn: deps,
          effects: &syncEffects)
      }
      depChangedIds.append(update.id)
    }
    if prepared.changedTags {
      if let tags = prepared.newTags {
        try TaskUpdateTags.replaceTaskTags(
          db, hlc: hlc, taskId: typedId, newTags: tags,
          effects: &syncEffects)
      }
    }
    // Gate the row's `tasks` outbox enqueue on the patch actually
    // touching a row-visible field. An empty patch (every field
    // `Unset`, no status / tags / deps / recurrence) leaves the row
    // identical and must not produce a phantom upsert.
    let touchesRow =
      TaskUpdateRow.hasPrimaryRowPatch(prepared)
      || prepared.changedTags
      || prepared.changedDeps
      || prepared.newStatus != nil
      || recurrencePatchActive
    if touchesRow {
      syncEffects.taskUpsertIds.append(update.id)
    }
  }

  /// Cross-row dependency cycle re-validation. Both `updateTask`
  /// (single) and `batchUpdateTasks` (multi, deferred) defer the cycle
  /// check until after every row's new edge set has landed so the
  /// validator sees the final state of the graph.
  public static func revalidateDependencyCycles(
    _ db: Database, depChangedIds: [String], errorContext: String
  ) throws {
    for taskId in depChangedIds {
      let typed = TaskId(trusted: taskId)
      let newDeps = try TaskUpdateDependencies.findTaskDependencies(db, taskId: typed)
      do {
        try DependencyValidation.validateNoDependencyCycle(
          db, taskId: typed, newDependsOn: newDeps)
      } catch let e as StoreError {
        if case .validation(let msg) = e {
          throw StoreError.validation(
            "\(errorContext) for task \(taskId): \(msg)")
        }
        throw e
      }
    }
  }
}
