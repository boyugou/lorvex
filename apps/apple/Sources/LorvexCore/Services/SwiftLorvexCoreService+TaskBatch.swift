import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

extension SwiftLorvexCoreService {
  // MARK: - Batch

  public func batchCompleteTasks(ids: [LorvexTask.ID]) async throws -> TaskBatchLifecycleResult {
    try batchLifecycle(ids: ids, operation: "batch_complete") { db, hlc, deviceId, id in
      let result = try LifecycleTransitions.applyCompletionTransition(
        db, taskId: TaskId(trusted: id), now: SyncTimestampFormat.syncTimestampNow(),
        reminderVersion: hlc.nextVersionString())
      guard result.updated else { return .skipped }
      try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .task, entityId: id)
      try self.flushLifecyclePlan(
        db, hlc: hlc, deviceId: deviceId, plan: LifecycleSyncPlan.from(completion: result))
      return .changed
    }
  }

  public func batchReopenTasks(ids: [LorvexTask.ID]) async throws -> TaskBatchLifecycleResult {
    try batchLifecycle(ids: ids, operation: "batch_reopen") { db, hlc, deviceId, id in
      guard let row = try TaskRepo.Read.getTask(db, taskId: TaskId(trusted: id)) else {
        return .skipped
      }
      guard let oldStatus = TaskStatus.parse(row.core.status) else { return .skipped }
      let result = try LifecycleTransitions.applyReopenTransition(
        db, taskId: TaskId(trusted: id), oldStatus: oldStatus,
        now: SyncTimestampFormat.syncTimestampNow(), reminderVersion: hlc.nextVersionString())
      guard result.updated else { return .skipped }
      try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .task, entityId: id)
      try self.flushLifecyclePlan(
        db, hlc: hlc, deviceId: deviceId, plan: LifecycleSyncPlan.from(reopen: result))
      return .changed
    }
  }

  public func batchDeferTasks(
    ids: [LorvexTask.ID], until date: Date, reason: String?, note: String?
  ) async throws -> TaskBatchLifecycleResult {
    let reason = try Self.normalizedDeferField(reason, field: "reason")
    let note = try Self.normalizedDeferField(note, field: "note")
    let planned = SwiftLorvexTaskDeserializers.plannedDateFormatter.string(from: date)
    return try batchLifecycle(
      ids: ids, operation: "batch_defer",
      deferDetail: DeferChangelogDetail(structuredReason: reason, note: note)
    ) { db, hlc, deviceId, id in
      let result = try TaskDeferral.deferTask(
        db, taskId: TaskId(trusted: id),
        patch: TaskDeferral.DeferralPatch(plannedDate: planned, lastDeferReason: reason),
        version: hlc.nextVersionString(), now: SyncTimestampFormat.syncTimestampNow(),
        nextReminderVersion: { hlc.nextVersionString() })
      if result.updated {
        try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .task, entityId: id)
        try self.enqueueUpserts(
          db, hlc: hlc, deviceId: deviceId, kind: .taskReminder,
          entityIds: result.shiftedReminderIds)
      }
      return result.updated ? .changed : .skipped
    }
  }

  private enum BatchLifecycleMutationOutcome {
    case changed
    case skipped
  }

  private func batchLifecycle(
    ids: [LorvexTask.ID],
    operation: String,
    deferDetail: DeferChangelogDetail? = nil,
    _ mutate: (Database, HlcSession, String, LorvexTask.ID) throws -> BatchLifecycleMutationOutcome
  ) throws -> TaskBatchLifecycleResult {
    try withWrite { db, hlc, deviceId in
      var changedIds: [LorvexTask.ID] = []
      var changedTasks: [LorvexTask] = []
      var skipped: [LorvexTask.ID] = []
      for id in ids {
        switch try mutate(db, hlc, deviceId, id) {
        case .changed:
          changedIds.append(id)
          // Capture the enriched task in the same transaction as its mutation so
          // the caller never re-reads it after commit (where a concurrent delete
          // could drop a task the batch actually changed).
          changedTasks.append(
            try SwiftLorvexTaskDeserializers.task(
              try TaskResponse.loadEnrichedTaskJSON(db, taskId: TaskId(trusted: id))))
        case .skipped:
          skipped.append(id)
        }
      }
      if !changedIds.isEmpty {
        // A batch defer stamps its reason/note onto the single shared changelog
        // row's `after_json._defer`; the `defer_history` reader unions this row in
        // via the entity registry, so every task in the batch surfaces the detail.
        let deferAfter = deferDetail.flatMap {
          $0.hasContent ? $0.enriched(.object([:])) : nil
        }
        try self.writeChangelogRow(
          db,
          ChangelogEntry(
            operation: operation, entityId: changedIds.first, entityIds: changedIds,
            summary: "\(operation): \(changedIds.count) task\(changedIds.count == 1 ? "" : "s")",
            after: deferAfter),
          deviceId: deviceId)
      }
      return TaskBatchLifecycleResult(
        snapshot: try Self.loadTodaySnapshot(db),
        changedIDs: changedIds,
        changedTasks: changedTasks,
        skipped: skipped)
    }
  }

  public func batchCreateTasks(_ drafts: [TaskCreateDraft]) async throws -> [LorvexTask] {
    try withWrite { db, hlc, deviceId in
      let inputs = drafts.map { draft -> TaskCreateInput in
        TaskCreateInput(
          title: draft.title,
          listId: draft.listID.map { .set($0) } ?? .unset,
          priority: .set(
            UInt8(draft.priority.tier)),
          dueDate: draft.dueDate.map { .set(Self.formatTaskDate($0)) } ?? .unset,
          estimatedMinutes: draft.estimatedMinutes.map { .set(UInt32(clamping: max(0, $0))) } ?? .unset,
          tags: draft.tags,
          body: .set(draft.notes),
          dependsOn: draft.dependsOn,
          plannedDate: draft.plannedDate.map { .set(Self.formatTaskDate($0)) } ?? .unset)
      }
      let result = try TaskBatchCreate.batchCreateTasks(
        db, hlc: hlc, input: BatchCreateTasksInput(ids: nil, tasks: inputs, includeAdvice: false))
      try self.flushBatchCreateEffects(db, hlc: hlc, deviceId: deviceId, effects: result.syncEffects)
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: "batch_create", entityId: result.createdIds.first,
          entityIds: result.createdIds, summary: result.summary),
        deviceId: deviceId)
      return try SwiftLorvexTaskDeserializers.tasks(result.createdTasks)
    }
  }

  public func batchCreateTaskRecords(
    _ specs: [TaskRecordCreateSpec]
  ) async throws -> [TaskRecordCreateOutcome] {
    try await batchCreateTaskRecordsForMcp(specs, includeAdvice: false).map { outcome in
      switch outcome {
      case .created(let task, _): return .created(task)
      case .failed(let reference, let error): return .failed(reference: reference, error: error)
      }
    }
  }

  public func batchCreateTaskRecordsForMcp(
    _ specs: [TaskRecordCreateSpec], includeAdvice: Bool
  ) async throws -> [McpTaskRecordCreateOutcome] {
    try withWrite { db, hlc, deviceId in
      var outcomes: [McpTaskRecordCreateOutcome] = []
      outcomes.reserveCapacity(specs.count)
      for spec in specs {
        do {
          let task = try StoreTransactions.withSavepoint(db, "batch_create_task_record") { db in
            try self.createTaskRecordInTx(db, hlc: hlc, deviceId: deviceId, spec: spec)
          }
          outcomes.append(.created(task: task, advice: []))
        } catch where Self.isWriteFunnelControlFlow(error) {
          // Not a per-row failure: the whole transaction is stale/refused and
          // `withWrite` owns the cutover/LWW retry. The same errors were
          // previously raised inside each row's own private transaction,
          // invisible to the per-row loop.
          throw error
        } catch {
          outcomes.append(.failed(reference: spec.reference, error: error))
        }
      }
      guard includeAdvice else { return outcomes }
      return try outcomes.map { outcome in
        switch outcome {
        case .created(let task, _):
          let taskJSON = try TaskResponse.loadEnrichedTaskJSON(
            db, taskId: TaskId(trusted: task.id))
          let advice = try TaskCreateAdvice.buildTaskIntakeAdvice(db, task: taskJSON)
            .compactMap(Self.taskIntakeAdviceItem(from:))
          return .created(task: task, advice: advice)
        case .failed:
          return outcome
        }
      }
    }
  }

  /// One complete task-record create inside an open write transaction: the
  /// id-preserving import arm (when `originalID` is set) or the ordinary create
  /// arm, then the requested lifecycle transition, historical timestamps, and —
  /// on the ordinary arm only — the initial checklist (the import arm's
  /// checklist is part of its record write). Mirrors the single `create_task`
  /// composition exactly, one savepoint-atomic row at a time.
  private func createTaskRecordInTx(
    _ db: Database, hlc: HlcSession, deviceId: String, spec: TaskRecordCreateSpec
  ) throws -> LorvexTask {
    if let originalID = spec.originalID {
      let exported = ExportTask(
        id: originalID, title: spec.title, notes: spec.notes,
        priority: spec.priority.rawValue,
        status: (spec.status ?? .open).rawValue, dueDate: nil, plannedDate: nil,
        availableFrom: nil, estimatedMinutes: spec.estimatedMinutes, tags: spec.tags,
        rawInput: spec.rawInput, dependsOn: spec.dependsOn,
        listID: spec.listID,
        checklist: spec.checklistTexts.enumerated().map {
          ExportChecklistItem(position: $0.offset, text: $0.element, completed: false)
        })
      let didImport = try importTaskRecordInTx(
        db, hlc: hlc, deviceId: deviceId, task: exported, priority: spec.priority,
        dueDate: spec.dueDate, plannedDate: spec.plannedDate,
        availableFrom: spec.availableFrom, dependenciesToApply: spec.dependsOn ?? [])
      guard didImport else {
        // Same id already live → return it untouched (idempotent re-create);
        // tombstoned → conflict, matching the single-create surface. Any other
        // load failure propagates rather than masquerading as the conflict.
        do {
          return try SwiftLorvexTaskDeserializers.task(
            try TaskResponse.loadEnrichedTaskJSON(db, taskId: TaskId(trusted: originalID)))
        } catch StoreError.notFound {
          throw LorvexCoreError.conflict(
            message:
              "That original_id belongs to a deleted task. Omit original_id to create a new task.")
        }
      }
      // A `.cancelled` / `.inProgress` export was created `.open`; transition it
      // through the same guarded lifecycle funnel the live tools use.
      if spec.status == .cancelled {
        _ = try applyLifecycleTransition(
          db, hlc: hlc, deviceId: deviceId, id: originalID, operation: "cancel"
        ) { db, hlc, deviceId in
          try self.applyCancelMutation(db, hlc: hlc, deviceId: deviceId, id: originalID)
        }
      } else if spec.status == .inProgress {
        _ = try applyLifecycleTransition(
          db, hlc: hlc, deviceId: deviceId, id: originalID, operation: "start"
        ) { db, hlc, deviceId in
          try self.applyStartMutation(db, hlc: hlc, deviceId: deviceId, id: originalID)
        }
      }
      try restoreSpecTimestampsInTx(db, hlc: hlc, deviceId: deviceId, id: originalID, spec: spec)
      return try SwiftLorvexTaskDeserializers.task(
        try TaskResponse.loadEnrichedTaskJSON(db, taskId: TaskId(trusted: originalID)))
    }

    var task = try createTaskInTx(
      db, hlc: hlc, deviceId: deviceId,
      draft: TaskCreateDraft(
        title: spec.title,
        notes: spec.notes,
        listID: spec.listID,
        priority: spec.priority,
        estimatedMinutes: spec.estimatedMinutes,
        dueDate: spec.dueDate,
        plannedDate: spec.plannedDate,
        availableFrom: spec.availableFrom,
        tags: spec.tags,
        dependsOn: spec.dependsOn,
        rawInput: spec.rawInput))
    switch spec.status {
    case .none, .open:
      break
    case .completed:
      _ = try applyLifecycleTransition(
        db, hlc: hlc, deviceId: deviceId, id: task.id, operation: "complete"
      ) { db, hlc, deviceId in
        try self.applyCompletionMutation(db, hlc: hlc, deviceId: deviceId, id: task.id)
      }
    case .cancelled:
      _ = try applyLifecycleTransition(
        db, hlc: hlc, deviceId: deviceId, id: task.id, operation: "cancel"
      ) { db, hlc, deviceId in
        try self.applyCancelMutation(db, hlc: hlc, deviceId: deviceId, id: task.id)
      }
    case .inProgress:
      _ = try applyLifecycleTransition(
        db, hlc: hlc, deviceId: deviceId, id: task.id, operation: "start"
      ) { db, hlc, deviceId in
        try self.applyStartMutation(db, hlc: hlc, deviceId: deviceId, id: task.id)
      }
    case .someday:
      _ = try markTaskSomedayInTx(db, hlc: hlc, deviceId: deviceId, id: task.id)
    }
    try restoreSpecTimestampsInTx(db, hlc: hlc, deviceId: deviceId, id: task.id, spec: spec)
    for text in spec.checklistTexts {
      _ = try checklistMutationInTx(
        db, hlc: hlc, deviceId: deviceId, operation: "checklist_add"
      ) { db, hlc in
        try TaskChecklist.addTaskChecklistItem(
          db, hlc: hlc,
          input: TaskChecklist.AddInput(taskId: TaskId(trusted: task.id), text: text))
      }
    }
    task = try SwiftLorvexTaskDeserializers.task(
      try TaskResponse.loadEnrichedTaskJSON(db, taskId: TaskId(trusted: task.id)))
    return task
  }

  /// Errors that are `withWrite`-funnel control flow (storage-cutover retry and
  /// the LWW stale/superseded family that re-runs the transaction at a
  /// dominating clock). They must propagate out of the per-row savepoint loop so
  /// the funnel can retry the whole batch; everything else is a per-row failure.
  private static func isWriteFunnelControlFlow(_ error: any Error) -> Bool {
    switch error {
    case is StorageCutoverDuringWrite: return true
    case StoreError.staleVersion, StoreError.versionSuperseded: return true
    case EnqueueError.versionSuperseded: return true
    default: return false
    }
  }

  /// Apply a spec's optional historical `created_at` / `completed_at` inside the
  /// open transaction; a spec without either is a no-op.
  private func restoreSpecTimestampsInTx(
    _ db: Database, hlc: HlcSession, deviceId: String, id: LorvexTask.ID,
    spec: TaskRecordCreateSpec
  ) throws {
    guard spec.createdAt != nil || spec.completedAt != nil else { return }
    try restoreImportedTaskMetadataInTx(
      db, hlc: hlc, deviceId: deviceId, id: id, archivedAt: nil, deferCount: nil,
      lastDeferReason: nil, lastDeferredAt: nil, completedAt: spec.completedAt,
      createdAt: spec.createdAt, updatedAt: nil)
  }

  public func batchUpdateTasks(_ drafts: [TaskUpdateDraft]) async throws -> [LorvexTask] {
    try withWrite { db, hlc, deviceId in
      let updates = try drafts.map { draft -> TaskUpdateInput in
        if let title = draft.title, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          throw LorvexCoreError.emptyTitle
        }
        return TaskUpdateInput(
          id: draft.id,
          title: draft.title.map { .set($0) } ?? .unset,
          body: draft.notes.map { .set($0) } ?? .unset,
          listId: draft.listID.map { .set($0) } ?? .unset,
          tagsSet: draft.tags,
          priority: draft.priority.map {
            .set(UInt8($0.tier))
          } ?? .unset,
          dueDate: Self.formatTaskDatePatch(draft.dueDate),
          estimatedMinutes: Self.estimatedMinutesPatch(draft.estimatedMinutes),
          dependsOn: draft.dependsOn,
          plannedDate: Self.formatTaskDatePatch(draft.plannedDate),
          availableFrom: Self.formatTaskDatePatch(draft.availableFrom))
      }
      var beforeSyncPayloads: [String: JSONValue] = [:]
      for id in Set(updates.map(\.id)) {
        beforeSyncPayloads[id] = try OutboxEnqueue.readEntityPayloadSnapshot(
          db, entityType: EntityName.task, entityId: id)
      }
      let result = try TaskBatchUpdate.batchUpdateTasksInTransaction(
        db, hlc: hlc, input: BatchUpdateTasksInput(updates: updates))
      var registerIntents: [String: TaskRegisterIntent] = [:]
      for (id, before) in beforeSyncPayloads {
        let after = try OutboxEnqueue.readEntityPayloadSnapshot(
          db, entityType: EntityName.task, entityId: id)
        registerIntents[id] = try TaskRegisterIntent.authoredRegisters(
          between: before, and: after)
      }
      try self.flushTaskUpdateEffects(
        db, hlc: hlc, deviceId: deviceId, effects: result.syncEffects,
        primaryRegisterIntents: registerIntents)
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: "batch_update", entityId: result.updatedIds.first,
          entityIds: result.updatedIds, summary: result.summary),
        deviceId: deviceId)
      return try SwiftLorvexTaskDeserializers.tasks(result.updatedTasks)
    }
  }

  public func batchMoveTasks(ids: [LorvexTask.ID], toListID listID: LorvexList.ID) async throws
    -> TaskBatchMoveResult
  {
    try withWrite { db, hlc, deviceId in
      let now = SyncTimestampFormat.syncTimestampNow()
      var movedIds: [LorvexTask.ID] = []
      var moved: [JSONValue] = []
      var skipped: [LorvexTask.ID] = []
      moved.reserveCapacity(ids.count)
      for id in ids {
        guard let row = try TaskRepo.Read.getTask(db, taskId: TaskId(trusted: id)) else {
          skipped.append(id)
          continue
        }
        guard row.core.listId != listID else {
          skipped.append(id)
          continue
        }
        let version = hlc.nextVersionString()
        try db.execute(
          sql: """
            UPDATE tasks
            SET list_id = ?, content_version = ?, version = ?, updated_at = ?
            WHERE id = ? AND ? > version
            """,
          arguments: [listID, version, version, now, id, version])
        guard db.changesCount > 0 else {
          skipped.append(id)
          continue
        }
        let after = try TaskResponse.loadEnrichedTaskJSON(db, taskId: TaskId(trusted: id))
        movedIds.append(id)
        moved.append(after)
        try self.enqueueUpsert(
          db, deviceId: deviceId, kind: .task, entityId: id, version: version,
          registerIntent: .task(.content))
      }
      if !movedIds.isEmpty {
        try self.writeChangelogRow(
          db,
          ChangelogEntry(
            operation: "batch_move", entityId: movedIds.first, entityIds: movedIds,
            summary: "Moved \(movedIds.count) task\(movedIds.count == 1 ? "" : "s") to list \(listID)"),
          deviceId: deviceId)
      }
      return TaskBatchMoveResult(
        moved: try SwiftLorvexTaskDeserializers.tasks(moved),
        skipped: skipped)
    }
  }
}

extension SwiftLorvexCoreService {
  public func batchCancelTasks(ids: [LorvexTask.ID], cancelSeries: Bool) async throws
    -> TaskBatchCancelByIdResult
  {
    try withWrite { db, hlc, deviceId in
      if ids.isEmpty {
        throw StoreError.validation("batch_cancel_tasks requires at least one ID")
      }
      var cancelledIds: [String] = []
      var cancelledTasks: [JSONValue] = []
      var skipped: [String] = []
      var syncPlans: [LifecycleSyncPlan] = []
      let now = SyncTimestampFormat.syncTimestampNow()

      for id in ids {
        let typedId = TaskId(trusted: id)
        guard let row = try TaskRepo.Read.getTask(db, taskId: typedId) else {
          skipped.append(id)
          continue
        }
        guard let status = TaskStatus.parse(row.core.status) else {
          skipped.append(id)
          continue
        }
        // An explicit id cancel applies to any non-terminal task — open,
        // in_progress (started), or someday. Only an already-terminal
        // (completed / cancelled) task is skipped as a no-op.
        guard status.isActive else {
          skipped.append(id)
          continue
        }

        let result = try LifecycleTransitions.applyCancelTransition(
          db, taskId: typedId, now: now,
          reminderVersion: hlc.nextVersionString(),
          cancelSeries: cancelSeries,
          seriesClearVersion: cancelSeries ? hlc.nextVersionString() : nil)
        guard result.updated else {
          skipped.append(id)
          continue
        }
        try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .task, entityId: id)
        syncPlans.append(LifecycleSyncPlan.from(cancel: result))
        cancelledIds.append(id)
        cancelledTasks.append(try TaskResponse.loadEnrichedTaskJSON(db, taskId: typedId))
      }

      if !cancelledIds.isEmpty {
        for plan in syncPlans {
          try self.flushLifecyclePlan(db, hlc: hlc, deviceId: deviceId, plan: plan)
        }
        try self.writeChangelogRow(
          db,
          ChangelogEntry(
            operation: "batch_cancel", entityId: cancelledIds.first,
            entityIds: cancelledIds,
            summary: "Cancelled \(cancelledIds.count) task\(cancelledIds.count == 1 ? "" : "s")"),
          deviceId: deviceId)
      }
      return TaskBatchCancelByIdResult(
        cancelled: try SwiftLorvexTaskDeserializers.tasks(cancelledTasks),
        skipped: skipped)
    }
  }

  public func batchCancelTasksInList(
    listID: LorvexList.ID, statuses: [String]?, cancelSeries: Bool
  ) async throws -> [LorvexTask] {
    try withWrite { db, hlc, deviceId in
      let parsedStatuses = try statuses?.map { try BatchCancelStatus.parse($0) }
      let input = BatchCancelInListInput(
        listId: ListId(trusted: listID),
        statuses: parsedStatuses,
        cancelSeries: cancelSeries
      )
      let result = try TaskBatchCancel.batchCancelTasksInList(db, hlc: hlc, input: input)
      let cancelledIds = result.taskIds.map(\.asString)
      guard !cancelledIds.isEmpty else { return [] }
      try self.flushBatchCancelEffects(
        db, hlc: hlc, deviceId: deviceId, effects: result.syncEffects)
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: "batch_cancel_in_list", entityId: listID,
          entityIds: cancelledIds,
          summary: "Cancelled \(cancelledIds.count) task\(cancelledIds.count == 1 ? "" : "s") in list '\(listID)'"),
        deviceId: deviceId)
      // Enrich the cancelled tasks in this same transaction; a post-commit
      // re-read could miss one a concurrent delete removed.
      let cancelledTasks = try result.taskIds.map {
        try TaskResponse.loadEnrichedTaskJSON(db, taskId: $0)
      }
      return try SwiftLorvexTaskDeserializers.tasks(cancelledTasks)
    }
  }

  private static func formatTaskDate(_ date: Date) -> String {
    SwiftLorvexTaskDeserializers.plannedDateFormatter.string(from: date)
  }

  static func formatTaskDatePatch(_ patch: Patch<Date>) -> Patch<String> {
    switch patch {
    case .unset:
      return .unset
    case .clear:
      return .clear
    case .set(let date):
      return .set(formatTaskDate(date))
    }
  }

  static func estimatedMinutesPatch(_ patch: Patch<Int>) -> Patch<UInt32> {
    switch patch {
    case .unset:
      return .unset
    case .clear:
      return .clear
    case .set(let value):
      return .set(UInt32(clamping: max(0, value)))
    }
  }
}
