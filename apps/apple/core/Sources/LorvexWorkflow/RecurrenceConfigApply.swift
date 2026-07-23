import Foundation
import GRDB
import LorvexDomain
import LorvexStore

extension RecurrenceConfig {
  public struct ApplyResult: Sendable, Equatable {
    public let transition: Transition
    public let disableEffects: RecurrenceDisableEffects

    public init(
      transition: Transition,
      disableEffects: RecurrenceDisableEffects = RecurrenceDisableEffects()
    ) {
      self.transition = transition
      self.disableEffects = disableEffects
    }
  }

  /// Domain error from ``applyRecurrenceChange(_:taskId:recurrencePatch:dueDatePatch:today:version:now:)``.
  /// Distinct from ``StoreError`` because the value rejection
  /// (`clearDueDateOnRecurring`) is domain-shaped, not a DB CHECK violation.
  public enum ChangeError: Error, Sendable, Equatable, CustomStringConvertible {
    /// Caller tried to clear `due_date` on a row that will remain
    /// recurring. Recurring tasks must always carry a `due_date`.
    case clearDueDateOnRecurring
    /// LWW gate rejected the UPDATE because a peer envelope landed
    /// between the boundary's HLC mint and the recurrence-config
    /// write. Boundary callers must re-stamp HLC and retry.
    case staleVersion(taskId: String)

    public var description: String {
      switch self {
      case .clearDueDateOnRecurring: return "recurring tasks must have a due_date"
      case .staleVersion(let id):
        return
          "stale version on task \(id): peer envelope landed between HLC mint "
          + "and recurrence_config UPDATE — re-stamp HLC and retry"
      }
    }
  }

  /// Atomically apply a recurrence patch with an LWW-gated UPDATE.
  ///
  /// Single shared owner for the combined `(recurrence, due_date,
  /// recurrence_group_id, canonical_occurrence_date)` patch
  /// semantics. All write surfaces delegate here — no surface-local
  /// recurrence / due_date logic.
  ///
  /// Threads `(version, now)` into the single emitted UPDATE so the
  /// planner column actions, the new recurrence value, and the
  /// `version` / `updated_at` bump all share one row write. The
  /// UPDATE is gated on `?version > tasks.version` so a stale
  /// caller stamp cannot clobber a peer's freshly-applied envelope.
  ///
  /// Self-wraps in an immediate transaction so the load → plan →
  /// UPDATE → exception rewrite sequence is atomic for every
  /// caller (boundary surfaces always invoke through a
  /// ``DatabaseWriter``; callers that need to share an outer
  /// transaction must instead call ``applyRecurrenceChangeInTx(_:taskId:recurrencePatch:dueDatePatch:today:version:now:)``).
  ///
  /// Throws ``ChangeError/clearDueDateOnRecurring`` for an invalid
  /// combination, and ``ChangeError/staleVersion(taskId:)`` when the
  /// LWW gate rejects the write.
  @discardableResult
  public static func applyRecurrenceChange(
    _ writer: any DatabaseWriter,
    taskId: TaskId,
    recurrencePatch: Patch<String>,
    dueDatePatch: Patch<String>,
    today: String,
    version: String,
    now: String
  ) throws -> Transition {
    try StoreTransactions.withImmediateTransaction(writer) { db in
      try applyRecurrenceChangeWithEffectsInTx(
        db, taskId: taskId, recurrencePatch: recurrencePatch,
        dueDatePatch: dueDatePatch, today: today, version: version, now: now
      ).transition
    }
  }

  /// Detailed writer boundary for surfaces that must enqueue the successor,
  /// reminder, dependency, and focus rows touched by a recurrence disable.
  public static func applyRecurrenceChangeWithEffects(
    _ writer: any DatabaseWriter,
    taskId: TaskId,
    recurrencePatch: Patch<String>,
    dueDatePatch: Patch<String>,
    today: String,
    version: String,
    now: String
  ) throws -> ApplyResult {
    try StoreTransactions.withImmediateTransaction(writer) { db in
      try applyRecurrenceChangeWithEffectsInTx(
        db, taskId: taskId, recurrencePatch: recurrencePatch,
        dueDatePatch: dueDatePatch, today: today, version: version, now: now)
    }
  }

  /// In-transaction variant of ``applyRecurrenceChange``. Use when the
  /// caller already holds an immediate transaction (e.g. an
  /// orchestrator that batches several mutations under one savepoint).
  @discardableResult
  public static func applyRecurrenceChangeInTx(
    _ db: Database,
    taskId: TaskId,
    recurrencePatch: Patch<String>,
    dueDatePatch: Patch<String>,
    today: String,
    version: String,
    now: String
  ) throws -> Transition {
    try applyRecurrenceChangeWithEffectsInTx(
      db, taskId: taskId, recurrencePatch: recurrencePatch,
      dueDatePatch: dueDatePatch, today: today, version: version, now: now
    ).transition
  }

  /// Detailed in-transaction boundary. This is the semantic owner used by
  /// update_task and remove_task_recurrence so cross-row cleanup is committed
  /// atomically with the parent task register.
  public static func applyRecurrenceChangeWithEffectsInTx(
    _ db: Database,
    taskId: TaskId,
    recurrencePatch: Patch<String>,
    dueDatePatch: Patch<String>,
    today: String,
    version: String,
    now: String
  ) throws -> ApplyResult {
    var old = try loadRecurrenceState(db, taskId: taskId)

    // Apply the due_date patch to the effective state for the planner +
    // validation pipeline.
    switch dueDatePatch {
    case .set(let value): old.dueDate = value
    case .clear: old.dueDate = nil
    case .unset: break
    }

    // Effective new_recurrence: when the recurrence column is not in
    // the patch, the planner needs the current DB value for the
    // "recurring requires due_date" validation downstream.
    let newRecurrence: String?
    switch recurrencePatch {
    case .set(let rule): newRecurrence = rule
    case .clear: newRecurrence = nil
    case .unset: newRecurrence = old.recurrence
    }

    // Only plan a transition when the recurrence column is in the
    // patch; otherwise emit a `NoChange` no-op action set so the
    // UPDATE only touches version + updated_at + any due_at patch.
    let transition: Transition
    let actions: ColumnActions
    switch recurrencePatch {
    case .unset:
      transition = .noChange
      actions = ColumnActions()
    default:
      (transition, actions) = planRecurrenceTransition(
        old: old, newRecurrence: newRecurrence, today: today)
    }

    let finalDueDate = actions.setDueDate ?? old.dueDate

    // Domain validations.
    let effectiveRecurring = !(newRecurrence ?? "").isEmpty
    if effectiveRecurring && finalDueDate == nil {
      throw ChangeError.clearDueDateOnRecurring
    }

    let rolloverBeforeChange = transition == .disable || transition == .enable
      ? try loadRolloverState(db, taskId: taskId)
      : nil
    let disableEffects: RecurrenceDisableEffects
    if transition == .disable, let rollover = rolloverBeforeChange {
      disableEffects = try RecurrenceDisableReconciliation.apply(
        db,
        taskId: taskId.asString,
        spawnedFrom: rollover.spawnedFrom,
        recurrenceGroupId: old.recurrenceGroupId,
        recordedSuccessorId: rollover.successorId,
        decisionVersion: version,
        now: now)
    } else {
      disableEffects = RecurrenceDisableEffects()
    }

    var setClauses: [String] = []
    var args: [DatabaseValueConvertible] = []

    switch recurrencePatch {
    case .set(let rule):
      setClauses.append("recurrence = ?")
      args.append(rule)
    case .clear:
      setClauses.append("recurrence = NULL")
    case .unset:
      break
    }

    if let gid = actions.setRecurrenceGroupId {
      setClauses.append("recurrence_group_id = ?")
      args.append(gid)
    }
    if actions.clearRecurrenceGroupId {
      setClauses.append("recurrence_group_id = NULL")
    }
    switch actions.setCanonicalOccurrenceDate {
    case .set(let date):
      setClauses.append("canonical_occurrence_date = ?")
      args.append(date)
    case .clear:
      setClauses.append("canonical_occurrence_date = NULL")
    case .unset:
      break
    }
    if actions.clearCanonicalOccurrenceDate {
      setClauses.append("canonical_occurrence_date = NULL")
    }
    // An explicit due_date reschedule on a task that stays recurring re-anchors
    // the cadence to the new due date, so future occurrences follow the new day
    // (e.g. a monthly task moved from the 6th to the 15th recurs on the 15th).
    // Deferral moves planned_date, not due_date, and never routes through this
    // applier, so the anchor stays put under deferral. Skip when the planner
    // already positioned the anchor (Enable) or cleared it (Disable).
    if effectiveRecurring,
      actions.setCanonicalOccurrenceDate == .unset,
      !actions.clearCanonicalOccurrenceDate,
      case .set(let rescheduledDue) = dueDatePatch
    {
      setClauses.append("canonical_occurrence_date = ?")
      args.append(rescheduledDue)
    }
    if let due = actions.setDueDate {
      setClauses.append("due_date = ?")
      args.append(due)
    }
    // If the planner didn't override due_date but the caller patched it,
    // include the caller's patch here.
    if actions.setDueDate == nil {
      switch dueDatePatch {
      case .set(let value):
        setClauses.append("due_date = ?")
        args.append(value)
      case .clear:
        setClauses.append("due_date = NULL")
      case .unset:
        break
      }
    }

    // Disabling recurrence also contracts the durable rollover register.
    // A reopened parent may retain a revoked successor id so a later
    // re-completion can revive that stable identity; once the series itself
    // is disabled that negative fact is no longer meaningful. Likewise, a
    // terminal parent that had authorized a child becomes an ended one-off.
    // Stamp schedule + lifecycle with the same HLC so peers never observe a
    // cleared recurrence skeleton paired with a stale rollover decision.
    if transition == .disable, let rollover = rolloverBeforeChange {
      switch (rollover.status.isActive, rollover.state) {
      case (true, .revoked):
        setClauses.append("recurrence_rollover_state = 'none'")
        setClauses.append("recurrence_successor_id = NULL")
        setClauses.append("lifecycle_version = ?")
        args.append(version)
      case (false, .authorized):
        setClauses.append("recurrence_rollover_state = 'ended'")
        setClauses.append("recurrence_successor_id = NULL")
        setClauses.append("lifecycle_version = ?")
        args.append(version)
      default:
        break
      }
      if rollover.spawnedFrom != nil {
        setClauses.append("spawned_from = NULL")
        setClauses.append("spawned_from_version = NULL")
      }
    }

    // Enabling recurrence on a terminal one-off creates an ended series, not
    // an implicitly-authorized next occurrence. This keeps the row valid and
    // makes the product semantics explicit: recurrence takes effect if the
    // task is reopened and completed again. A joint reopen+enable update then
    // immediately moves `ended -> none` in the lifecycle owner.
    if transition == .enable, let rollover = rolloverBeforeChange,
      rollover.status.isTerminal
    {
      setClauses.append("recurrence_rollover_state = 'ended'")
      setClauses.append("recurrence_successor_id = NULL")
      setClauses.append("lifecycle_version = ?")
      args.append(version)
    }

    // Always emit the UPDATE — even on a `NoChange` no-op — because
    // the boundary caller asked for a version bump on this row and
    // the changelog / outbox shape relies on the row's `version`
    // matching the outbox envelope.
    setClauses.append("schedule_version = ?")
    args.append(version)
    setClauses.append("version = ?")
    args.append(version)
    setClauses.append("updated_at = ?")
    args.append(now)
    args.append(taskId.asString)
    args.append(version)

    let sql =
      "UPDATE tasks SET \(setClauses.joined(separator: ", ")) "
      + "WHERE id = ? AND ? > version"
    try db.execute(sql: sql, arguments: StatementArguments(args))
    let rows = db.changesCount

    if rows != 0 && actions.clearRecurrenceExceptions {
      try RecurrenceExceptionsRepo.replaceTaskExceptions(
        db, taskId: taskId.asString, dates: [])
    }

    if rows == 0 {
      // Distinguish "row missing" (the recurrence helper read it
      // moments ago, so this is only possible if the txn raced)
      // from "LWW gate refused us". The typical case is the latter
      // — a peer envelope landed between the boundary's HLC mint
      // and the UPDATE. Surface as `staleVersion` so the caller
      // can re-stamp + retry. The probe checks existence regardless
      // of `archived_at`: the UPDATE itself is not archive-gated, so a
      // 0-row write on an archived row is still an LWW rejection and
      // must surface rather than silently returning success.
      let exists =
        (try Int.fetchOne(
          db,
          sql: "SELECT 1 FROM tasks WHERE id = ?1",
          arguments: [taskId.asString])) != nil
      if exists {
        throw ChangeError.staleVersion(taskId: taskId.asString)
      }
    }

    return ApplyResult(transition: transition, disableEffects: disableEffects)
  }

  /// Load the current recurrence state of a task from the database.
  /// Returns a fully-populated ``State`` (all `nil` columns surface as
  /// `nil`). Throws ``StoreError/notFound(entity:id:)`` when the row
  /// is missing.
  static func loadRecurrenceState(
    _ db: Database, taskId: TaskId
  ) throws -> State {
    guard
      let row = try Row.fetchOne(
        db,
        sql:
          "SELECT recurrence, recurrence_group_id, canonical_occurrence_date, "
          + "due_date FROM tasks WHERE id = ?1",
        arguments: [taskId.asString])
    else {
      throw StoreError.notFound(entity: EntityKind.task.rawValue, id: taskId.asString)
    }
    return State(
      recurrence: row[0],
      recurrenceGroupId: row[1],
      canonicalOccurrenceDate: row[2],
      dueDate: row[3])
  }

  private struct LoadedRolloverState {
    let status: TaskStatus
    let state: TaskRecurrenceRolloverState
    let successorId: String?
    let spawnedFrom: String?
  }

  private static func loadRolloverState(
    _ db: Database, taskId: TaskId
  ) throws -> LoadedRolloverState {
    guard
      let row = try Row.fetchOne(
        db,
        sql:
          "SELECT status, recurrence_rollover_state, recurrence_successor_id, "
          + "spawned_from FROM tasks WHERE id = ?1",
        arguments: [taskId.asString])
    else {
      throw StoreError.notFound(entity: EntityKind.task.rawValue, id: taskId.asString)
    }
    let rawStatus: String = row[0]
    guard let status = TaskStatus.parse(rawStatus) else {
      throw StoreError.invariant(
        "task \(taskId.asString) has invalid status \"\(rawStatus)\"")
    }
    let rawState: String = row[1]
    guard let state = TaskRecurrenceRolloverState(rawValue: rawState) else {
      throw StoreError.invariant(
        "task \(taskId.asString) has invalid recurrence_rollover_state \"\(rawState)\"")
    }
    return LoadedRolloverState(
      status: status, state: state, successorId: row[2], spawnedFrom: row[3])
  }
}
