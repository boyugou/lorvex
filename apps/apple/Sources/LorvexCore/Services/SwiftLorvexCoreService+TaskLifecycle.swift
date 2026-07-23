import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

extension SwiftLorvexCoreService {
  public func completeTask(id: LorvexTask.ID) async throws -> TodaySnapshot {
    try lifecycleTransition(id: id, operation: "complete") { db, hlc, deviceId in
      try self.applyCompletionMutation(db, hlc: hlc, deviceId: deviceId, id: id)
    }
  }

  public func completeTaskReturningTask(id: LorvexTask.ID) async throws -> LorvexTask {
    try lifecycleTransitionTask(id: id, operation: "complete") { db, hlc, deviceId in
      try self.applyCompletionMutation(db, hlc: hlc, deviceId: deviceId, id: id)
    }
  }

  public func cancelTask(id: LorvexTask.ID) async throws -> TodaySnapshot {
    try lifecycleTransition(id: id, operation: "cancel") { db, hlc, deviceId in
      try self.applyCancelMutation(db, hlc: hlc, deviceId: deviceId, id: id)
    }
  }

  public func cancelTaskReturningTask(id: LorvexTask.ID) async throws -> LorvexTask {
    try lifecycleTransitionTask(id: id, operation: "cancel") { db, hlc, deviceId in
      try self.applyCancelMutation(db, hlc: hlc, deviceId: deviceId, id: id)
    }
  }

  public func reopenTask(id: LorvexTask.ID) async throws -> TodaySnapshot {
    try lifecycleTransition(id: id, operation: "reopen") { db, hlc, deviceId in
      try self.applyReopenMutation(db, hlc: hlc, deviceId: deviceId, id: id)
    }
  }

  public func reopenTaskReturningTask(id: LorvexTask.ID) async throws -> LorvexTask {
    try lifecycleTransitionTask(id: id, operation: "reopen") { db, hlc, deviceId in
      try self.applyReopenMutation(db, hlc: hlc, deviceId: deviceId, id: id)
    }
  }

  public func startTask(id: LorvexTask.ID) async throws -> TodaySnapshot {
    try lifecycleTransition(id: id, operation: "start") { db, hlc, deviceId in
      try self.applyStartMutation(db, hlc: hlc, deviceId: deviceId, id: id)
    }
  }

  public func startTaskReturningTask(id: LorvexTask.ID) async throws -> LorvexTask {
    try lifecycleTransitionTask(id: id, operation: "start") { db, hlc, deviceId in
      try self.applyStartMutation(db, hlc: hlc, deviceId: deviceId, id: id)
    }
  }

  public func pauseTask(id: LorvexTask.ID) async throws -> TodaySnapshot {
    try lifecycleTransition(id: id, operation: "pause") { db, hlc, deviceId in
      try self.applyPauseMutation(db, hlc: hlc, deviceId: deviceId, id: id)
    }
  }

  public func pauseTaskReturningTask(id: LorvexTask.ID) async throws -> LorvexTask {
    try lifecycleTransitionTask(id: id, operation: "pause") { db, hlc, deviceId in
      try self.applyPauseMutation(db, hlc: hlc, deviceId: deviceId, id: id)
    }
  }

  public func deferTask(id: LorvexTask.ID, until date: Date, reason: String?, note: String?)
    async throws -> TodaySnapshot
  {
    let reason = try Self.normalizedDeferField(reason, field: "reason")
    let note = try Self.normalizedDeferField(note, field: "note")
    return try lifecycleTransition(
      id: id, operation: "defer",
      deferDetail: DeferChangelogDetail(structuredReason: reason, note: note)
    ) { db, hlc, deviceId in
      try self.applyDeferMutation(db, hlc: hlc, deviceId: deviceId, id: id, date: date, reason: reason)
    }
  }

  public func deferTaskReturningTask(
    id: LorvexTask.ID, until date: Date, reason: String?, note: String?
  ) async throws -> LorvexTask {
    let reason = try Self.normalizedDeferField(reason, field: "reason")
    let note = try Self.normalizedDeferField(note, field: "note")
    return try lifecycleTransitionTask(
      id: id, operation: "defer",
      deferDetail: DeferChangelogDetail(structuredReason: reason, note: note)
    ) { db, hlc, deviceId in
      try self.applyDeferMutation(db, hlc: hlc, deviceId: deviceId, id: id, date: date, reason: reason)
    }
  }

  /// Trim a defer field (structured reason or free-text note) and collapse an
  /// empty / whitespace-only value to `nil`, so a blank note records nothing
  /// extra on the changelog row. Both fields are short-text-capped:
  /// `last_defer_reason` rides the task sync payload, and its 2,000-codepoint
  /// cap bounds the worst-case escaped size at the 12,000 bytes the
  /// ``PayloadByteBudget`` task arithmetic reserves for it.
  static func normalizedDeferField(_ raw: String?, field: String) throws -> String? {
    guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
    else { return nil }
    guard trimmed.unicodeScalars.count <= ValidationLimits.maxShortTextLength else {
      throw LorvexCoreError.validation(
        field: field,
        message:
          "\(field) may be at most \(ValidationLimits.maxShortTextLength) characters.")
    }
    return trimmed
  }

  /// Move a task into the GTD Someday/Maybe bucket (`status = 'someday'`).
  /// Drives the shared LWW-gated status writer so the transition-metadata rules
  /// (e.g. clearing `completed_at` when leaving the completed state) apply
  /// uniformly with the other lifecycle tools. `list_id` is never touched —
  /// status is orthogonal to list membership. Records the before/after task in
  /// `ai_changelog` and returns the full updated task.
  public func markTaskSomeday(id: LorvexTask.ID) async throws -> LorvexTask {
    try withWrite { db, hlc, deviceId in
      try self.markTaskSomedayInTx(db, hlc: hlc, deviceId: deviceId, id: id)
    }
  }

  /// The someday transition inside an open write transaction, shared by the
  /// public entry and the single-transaction batch record create. Same contract
  /// as ``markTaskSomeday(id:)``.
  func markTaskSomedayInTx(
    _ db: Database, hlc: HlcSession, deviceId: String, id: LorvexTask.ID
  ) throws -> LorvexTask {
    let typedId = TaskId(trusted: id)
    guard let row = try TaskRepo.Read.getTask(db, taskId: typedId) else {
      throw LorvexCoreError.taskNotFound
    }
    let oldStatus = try LifecycleStatus.parsePersistedTaskStatus(
      taskId: typedId, raw: row.core.status)
    let before = try TaskResponse.loadEnrichedTaskJSON(db, taskId: typedId)
    // Already someday — no-op: skip the status write, the sync enqueue, AND the
    // ai_changelog row. Logging a "Parked as someday" entry and bumping sync for
    // a status that did not change would pollute the audit trail and trigger a
    // spurious push. Mirrors the lifecycleTransition funnel's changed-gating.
    guard oldStatus != .someday else {
      return try SwiftLorvexTaskDeserializers.task(before)
    }
    // Someday is a real nonterminal lifecycle transition. In particular,
    // moving a completed/cancelled recurring parent back to an active state
    // must run the same guarded successor rewind as `reopen`: cancel the
    // exact authorized successor and its active graph projections, or reject
    // when that successor has already advanced. A direct status UPDATE here
    // would leave two actionable occurrences in the recurrence chain.
    let result = try LifecycleTransitions.applyLifecycleTransition(
      db, taskId: typedId, oldStatus: oldStatus, newStatus: .someday,
      now: SyncTimestampFormat.syncTimestampNow(),
      reminderVersion: hlc.nextVersionString())
    try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .task, entityId: id)
    try self.flushLifecyclePlan(
      db, hlc: hlc, deviceId: deviceId,
      plan: LifecycleSyncPlan.from(transition: result))
    let after = try TaskResponse.loadEnrichedTaskJSON(db, taskId: typedId)
    try self.writeChangelogRow(
      db,
      ChangelogEntry(
        operation: "someday", entityId: id,
        summary: "Parked task '\(TaskResponse.taskTitle(after))' as someday",
        before: before, after: after),
      deviceId: deviceId)
    return try SwiftLorvexTaskDeserializers.task(after)
  }

  // MARK: - Shared status mutations

  /// Each `apply…Mutation` performs one status transition (and its sync
  /// bookkeeping) inside an open `withWrite` transaction and reports whether the
  /// row actually changed. Shared by the `TodaySnapshot`-returning tools (UI /
  /// intents) and the `…ReturningTask` tools (MCP), so both surfaces run the
  /// identical write.

  func applyCompletionMutation(
    _ db: Database, hlc: HlcSession, deviceId: String, id: LorvexTask.ID
  ) throws -> Bool {
    let result = try LifecycleTransitions.applyCompletionTransition(
      db, taskId: TaskId(trusted: id), now: SyncTimestampFormat.syncTimestampNow(),
      reminderVersion: hlc.nextVersionString())
    guard result.updated else { return false }
    try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .task, entityId: id)
    try self.flushLifecyclePlan(
      db, hlc: hlc, deviceId: deviceId, plan: LifecycleSyncPlan.from(completion: result))
    return true
  }

  func applyCancelMutation(
    _ db: Database, hlc: HlcSession, deviceId: String, id: LorvexTask.ID
  ) throws -> Bool {
    let result = try LifecycleTransitions.applyCancelTransition(
      db, taskId: TaskId(trusted: id), now: SyncTimestampFormat.syncTimestampNow(),
      reminderVersion: hlc.nextVersionString(), cancelSeries: false, seriesClearVersion: nil)
    guard result.updated else { return false }
    try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .task, entityId: id)
    try self.flushLifecyclePlan(
      db, hlc: hlc, deviceId: deviceId, plan: LifecycleSyncPlan.from(cancel: result))
    return true
  }

  private func applyReopenMutation(
    _ db: Database, hlc: HlcSession, deviceId: String, id: LorvexTask.ID
  ) throws -> Bool {
    guard let row = try TaskRepo.Read.getTask(db, taskId: TaskId(trusted: id)) else {
      throw LorvexCoreError.taskNotFound
    }
    let oldStatus = try LifecycleStatus.parsePersistedTaskStatus(
      taskId: TaskId(trusted: id), raw: row.core.status)
    let result = try LifecycleTransitions.applyReopenTransition(
      db, taskId: TaskId(trusted: id), oldStatus: oldStatus,
      now: SyncTimestampFormat.syncTimestampNow(), reminderVersion: hlc.nextVersionString())
    guard result.updated else { return false }
    try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .task, entityId: id)
    try self.flushLifecyclePlan(
      db, hlc: hlc, deviceId: deviceId, plan: LifecycleSyncPlan.from(reopen: result))
    return true
  }

  /// Start a task: `open → in_progress`. Idempotent no-op when the task is
  /// already in_progress. Rejects any non-open source (reopen a terminal /
  /// someday task first). The dependency-blocked-start guard lives inside
  /// ``LifecycleTransitions/applyLifecycleTransition`` so `start_task`, the
  /// create-path status route, and update paths all reject a blocked start
  /// identically.
  func applyStartMutation(
    _ db: Database, hlc: HlcSession, deviceId: String, id: LorvexTask.ID
  ) throws -> Bool {
    let typedId = TaskId(trusted: id)
    guard let row = try TaskRepo.Read.getTask(db, taskId: typedId) else {
      throw LorvexCoreError.taskNotFound
    }
    let oldStatus = try LifecycleStatus.parsePersistedTaskStatus(
      taskId: typedId, raw: row.core.status)
    guard oldStatus != .inProgress else { return false }
    guard oldStatus == .open else {
      throw StoreError.validation(
        "Cannot start a \(oldStatus.asString) task; reopen it to open first.")
    }
    let result = try LifecycleTransitions.applyLifecycleTransition(
      db, taskId: typedId, oldStatus: .open, newStatus: .inProgress,
      now: SyncTimestampFormat.syncTimestampNow(), reminderVersion: hlc.nextVersionString())
    try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .task, entityId: id)
    try self.flushLifecyclePlan(
      db, hlc: hlc, deviceId: deviceId, plan: LifecycleSyncPlan.from(transition: result))
    return true
  }

  /// Pause a task: `in_progress → open` (un-start). Idempotent no-op when the
  /// task is already open. Rejects a terminal / someday source — only a started
  /// task can be paused. Deliberately leaves `planned_date` / `defer_count`
  /// intact: start → pause is a metadata no-op (see
  /// ``LorvexDomain/statusTransitionColumns(oldStatus:newStatus:now:)``).
  private func applyPauseMutation(
    _ db: Database, hlc: HlcSession, deviceId: String, id: LorvexTask.ID
  ) throws -> Bool {
    let typedId = TaskId(trusted: id)
    guard let row = try TaskRepo.Read.getTask(db, taskId: typedId) else {
      throw LorvexCoreError.taskNotFound
    }
    let oldStatus = try LifecycleStatus.parsePersistedTaskStatus(
      taskId: typedId, raw: row.core.status)
    guard oldStatus != .open else { return false }
    guard oldStatus == .inProgress else {
      throw StoreError.validation(
        "Cannot pause a \(oldStatus.asString) task; only an in-progress task can be paused.")
    }
    let result = try LifecycleTransitions.applyLifecycleTransition(
      db, taskId: typedId, oldStatus: .inProgress, newStatus: .open,
      now: SyncTimestampFormat.syncTimestampNow(), reminderVersion: hlc.nextVersionString())
    try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .task, entityId: id)
    try self.flushLifecyclePlan(
      db, hlc: hlc, deviceId: deviceId, plan: LifecycleSyncPlan.from(transition: result))
    return true
  }

  private func applyDeferMutation(
    _ db: Database, hlc: HlcSession, deviceId: String, id: LorvexTask.ID, date: Date, reason: String?
  ) throws -> Bool {
    let version = hlc.nextVersionString()
    let planned = SwiftLorvexTaskDeserializers.plannedDateFormatter.string(from: date)
    let result = try TaskDeferral.deferTask(
      db, taskId: TaskId(trusted: id),
      patch: TaskDeferral.DeferralPatch(plannedDate: planned, lastDeferReason: reason),
      version: version, now: SyncTimestampFormat.syncTimestampNow(),
      nextReminderVersion: { hlc.nextVersionString() })
    if result.updated {
      try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .task, entityId: id)
      try self.enqueueUpserts(
        db, hlc: hlc, deviceId: deviceId, kind: .taskReminder,
        entityIds: result.shiftedReminderIds)
    }
    return result.updated
  }

  // MARK: - Transition funnels

  /// Per-defer detail folded into the defer changelog row's `after_json` under
  /// the reserved ``AiChangelogDeferHistory/deferDetailKey`` object, so the
  /// coarse `structuredReason` and free-text `note` supplied at a defer survive
  /// on the append-only changelog (the `get_task` `defer_history` read side).
  /// Both fields are already trimmed to nil-when-empty; a detail with neither
  /// present writes nothing extra, keeping a plain defer's snapshot clean.
  struct DeferChangelogDetail {
    var structuredReason: String?
    var note: String?

    var hasContent: Bool { structuredReason != nil || note != nil }

    /// Return `after` with the reserved `_defer` object merged in, or `after`
    /// unchanged when there is no detail to record (or `after` is not an object).
    func enriched(_ after: JSONValue) -> JSONValue {
      guard hasContent, case .object(var object) = after else { return after }
      var detail: [String: JSONValue] = [:]
      if let structuredReason { detail["structured_reason"] = .string(structuredReason) }
      if let note { detail["note"] = .string(note) }
      object[AiChangelogDeferHistory.deferDetailKey] = .object(detail)
      return .object(object)
    }
  }

  /// Shared funnel for status-transition writes that return a fresh
  /// `TodaySnapshot`. Records the before/after task in the changelog and
  /// re-reads `loadToday` from the same store afterwards so the returned
  /// snapshot reflects the just-applied transition.
  private func lifecycleTransition(
    id: LorvexTask.ID,
    operation: String,
    deferDetail: DeferChangelogDetail? = nil,
    _ mutate: (Database, HlcSession, String) throws -> Bool
  ) throws -> TodaySnapshot {
    try withWrite { db, hlc, deviceId in
      _ = try self.applyLifecycleTransition(
        db, hlc: hlc, deviceId: deviceId, id: id, operation: operation,
        deferDetail: deferDetail, mutate)
      return try Self.loadTodaySnapshot(db)
    }
  }

  /// Sibling of ``lifecycleTransition(id:operation:deferDetail:_:)`` that returns
  /// the full mutated task enriched inside the same write transaction — the
  /// enriched value the MCP host needs without a post-commit read-back that a
  /// concurrent delete could turn into a spurious not-found error.
  private func lifecycleTransitionTask(
    id: LorvexTask.ID,
    operation: String,
    deferDetail: DeferChangelogDetail? = nil,
    _ mutate: (Database, HlcSession, String) throws -> Bool
  ) throws -> LorvexTask {
    try withWrite { db, hlc, deviceId in
      let after = try self.applyLifecycleTransition(
        db, hlc: hlc, deviceId: deviceId, id: id, operation: operation,
        deferDetail: deferDetail, mutate)
      return try SwiftLorvexTaskDeserializers.task(after)
    }
  }

  /// Run one transition inside the caller's `withWrite`: load the before task
  /// (failing the transaction rather than committing a changelog row with a
  /// missing before/after payload — Core Design Rule 2 wants a complete audit
  /// entry or none), apply the mutation, load the after task, and record the
  /// changelog only when the row actually changed. Returns the enriched after
  /// task so both funnels can shape their own return value.
  ///
  /// `deferDetail`, when supplied, folds the per-defer reason / note into the
  /// changelog row's `after_json` only — the returned task stays a clean
  /// snapshot without the reserved `_defer` key.
  func applyLifecycleTransition(
    _ db: Database, hlc: HlcSession, deviceId: String, id: LorvexTask.ID, operation: String,
    deferDetail: DeferChangelogDetail? = nil,
    _ mutate: (Database, HlcSession, String) throws -> Bool
  ) throws -> JSONValue {
    let before = try TaskResponse.loadEnrichedTaskJSON(db, taskId: TaskId(trusted: id))
    let changed = try mutate(db, hlc, deviceId)
    let after = try TaskResponse.loadEnrichedTaskJSON(db, taskId: TaskId(trusted: id))
    if changed {
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: operation,
          entityId: id,
          summary: "Task \(operation): \(id)",
          before: before,
          after: deferDetail?.enriched(after) ?? after),
        deviceId: deviceId)
    }
    return after
  }
}
