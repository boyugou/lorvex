import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Low-level status state-machine primitives that flip a single
/// `tasks.status` row (plus its transition metadata columns) and run
/// the bounded per-row side effects:
///
/// - ``completeTask(_:taskId:now:reminderVersion:)``: cancel active
///   reminders.
/// - ``cancelTask(_:taskId:now:reminderVersion:)``: cancel active
///   reminders + detach dependency edges.
/// - ``reopenTask(_:taskId:now:reminderVersion:)``: restore the task to
///   open without reviving cancelled reminders.
///
/// The transition orchestrators in ``LifecycleTransitions`` layer
/// recurrence-spawn / successor-cancel / changelog snapshotting on top
/// of these primitives.
public enum LifecycleStatus {
  /// Reject the impossible terminal→terminal transition path
  /// (`completed → cancelled`, `cancelled → completed`).
  static func rejectTerminalToTerminal(
    taskId: TaskId, oldStatus: TaskStatus, newStatus: TaskStatus
  ) throws {
    if oldStatus != newStatus && oldStatus.isTerminal && newStatus.isTerminal {
      throw StoreError.validation(
        "Cannot transition task \(taskId.asString) from \(oldStatus) to \(newStatus); reopen it first"
      )
    }
  }

  /// Reject starting (`→ in_progress`) a task whose dependencies are not yet
  /// resolved.
  ///
  /// A task is start-blocked when it `depends_on` at least one non-archived
  /// blocker still active (`open` / `in_progress` / `someday`); a `completed`
  /// or `cancelled` blocker no longer blocks. Throws ``StoreError/validation(_:)``
  /// naming the blocker ids — the same error taxonomy the other lifecycle
  /// guards use — so `start_task`, the create-path status route, and any
  /// status-update path reject a blocked start identically. No force-override.
  static func rejectStartWhenDependencyBlocked(
    _ db: Database, taskId: TaskId
  ) throws {
    let blockers: [String] = try String.fetchAll(
      db,
      sql:
        "SELECT td.depends_on_task_id FROM task_dependencies td "
        + "JOIN tasks blocker ON blocker.id = td.depends_on_task_id "
        + "WHERE td.task_id = ?1 "
        + "  AND blocker.archived_at IS NULL "
        + "  AND blocker.status IN (\(StatusName.activeStatusSqlList)) "
        + "ORDER BY td.depends_on_task_id ASC",
      arguments: [taskId.asString])
    guard blockers.isEmpty else {
      throw StoreError.validation(
        "Cannot start task \(taskId.asString): blocked by unfinished "
          + "dependencies [\(blockers.joined(separator: ", "))]. "
          + "Complete or cancel them first.")
    }
  }

  static func invalidPersistedTaskStatus(taskId: TaskId, raw: String) -> StoreError {
    .invariant(
      "task \(taskId.asString) has invalid persisted status \"\(raw)\"; expected one of: open, in_progress, completed, cancelled, someday"
    )
  }

  /// Decode a `tasks.status` value read back from the store, or throw the
  /// canonical invariant error. The column is CHECK-constrained to the five
  /// `TaskStatus` cases, so a failure here means genuine corruption (or a value
  /// from a schema this build predates) — surfacing it beats silently coercing
  /// to a guessed status. The single source of truth for service-layer status
  /// decode, so lifecycle ops never fork on an ad-hoc `?? .open` / `?? .completed`.
  public static func parsePersistedTaskStatus(taskId: TaskId, raw: String) throws -> TaskStatus {
    guard let status = TaskStatus.parse(raw) else {
      throw invalidPersistedTaskStatus(taskId: taskId, raw: raw)
    }
    return status
  }

  /// Read the current status. Returns `nil` when the row is missing.
  static func readTaskStatus(
    _ db: Database, taskId: TaskId
  ) throws -> TaskStatus? {
    let raw: String? = try String.fetchOne(
      db,
      sql: "SELECT status FROM tasks WHERE id = ?1",
      arguments: [taskId.asString])
    guard let raw = raw else { return nil }
    return try parsePersistedTaskStatus(taskId: taskId, raw: raw)
  }

  /// Complete a task: set status to `completed`, apply status-transition
  /// metadata columns, and cancel active reminders. Returns
  /// `updated: false` when the task is already completed or missing.
  /// Surfaces ``StoreError/staleVersion`` when the LWW gate rejects
  /// the write.
  public static func completeTask(
    _ db: Database, taskId: TaskId, now: String, reminderVersion: String
  ) throws -> CompleteTaskResult {
    guard let oldStatus = try readTaskStatus(db, taskId: taskId) else {
      return CompleteTaskResult(updated: false, cancelledReminderIds: [])
    }
    try rejectTerminalToTerminal(
      taskId: taskId, oldStatus: oldStatus, newStatus: .completed)
    if oldStatus == .completed {
      return CompleteTaskResult(updated: false, cancelledReminderIds: [])
    }

    let rows = try LifecycleWriteStatus.writeStatusAndMetadata(
      db, taskId: taskId,
      oldStatus: oldStatus, newStatus: .completed,
      now: now, version: reminderVersion)
    if rows == 0 {
      throw StoreError.staleVersion(entity: "task", id: taskId.asString)
    }

    let cancelled = try LifecycleReminders.cancelActiveReminders(
      db, taskId: taskId, now: now, version: reminderVersion)
    return CompleteTaskResult(updated: true, cancelledReminderIds: cancelled)
  }

  /// Cancel a task: set status to `cancelled`, apply transition metadata,
  /// cancel active reminders, and detach every dependency edge. Returns
  /// `updated: false` when the task is already cancelled or missing.
  /// Surfaces ``StoreError/staleVersion`` when the LWW gate rejects.
  public static func cancelTask(
    _ db: Database, taskId: TaskId, now: String, reminderVersion: String
  ) throws -> CancelTaskResult {
    guard let oldStatus = try readTaskStatus(db, taskId: taskId) else {
      return CancelTaskResult(
        updated: false,
        affectedDependentIds: [],
        cancelledReminderIds: [],
        deletedDependencyEdges: [])
    }
    try rejectTerminalToTerminal(
      taskId: taskId, oldStatus: oldStatus, newStatus: .cancelled)
    if oldStatus == .cancelled {
      return CancelTaskResult(
        updated: false,
        affectedDependentIds: [],
        cancelledReminderIds: [],
        deletedDependencyEdges: [])
    }

    let rows = try LifecycleWriteStatus.writeStatusAndMetadata(
      db, taskId: taskId,
      oldStatus: oldStatus, newStatus: .cancelled,
      now: now, version: reminderVersion)
    if rows == 0 {
      throw StoreError.staleVersion(entity: "task", id: taskId.asString)
    }

    let cancelledReminderIds = try LifecycleReminders.cancelActiveReminders(
      db, taskId: taskId, now: now, version: reminderVersion)
    let (affected, deleted) = try LifecycleDependencies.detachTaskDependencyEdges(
      db, taskId: taskId)

    return CancelTaskResult(
      updated: true,
      affectedDependentIds: affected,
      cancelledReminderIds: cancelledReminderIds,
      deletedDependencyEdges: deleted)
  }

  /// Cancel the still-active direct successor invalidated by reopening its
  /// parent. This is deliberately not a normal recurring-task cancellation:
  /// it must not authorize another occurrence. The row remains available for
  /// same-ID revival if the parent is completed again.
  static func cancelRecurrenceSuccessorForReopen(
    _ db: Database,
    taskId: TaskId,
    oldStatus: TaskStatus,
    now: String,
    version: String
  ) throws -> CancelTaskResult {
    guard oldStatus.isActive else {
      throw StoreError.validation(
        "Cannot rewind recurrence successor \(taskId.asString): it has already advanced")
    }

    var setClauses: [String] = [
      "status = 'cancelled'", "completed_at = NULL",
      // The successor remains a recurring terminal row. `ended` is the
      // durable statement that this occurrence did not authorize another
      // child; the predecessor's `revoked` register retains the stable id
      // needed to revive this exact row on re-completion.
      "recurrence_rollover_state = 'ended'", "recurrence_successor_id = NULL",
      "lifecycle_version = ?", "schedule_version = ?",
      "version = ?", "updated_at = ?",
    ]
    var arguments: [DatabaseValueConvertible] = [version, version, version, now]
    for action in statusTransitionColumns(
      oldStatus: oldStatus, newStatus: .cancelled, now: now)
    {
      switch action {
      case .setText(let column, let value):
        if column == "completed_at" { continue }
        setClauses.append(StatusTransitionSql.setValueFragment(column))
        arguments.append(value)
      case .setNull(let column):
        if column == "completed_at" { continue }
        setClauses.append(StatusTransitionSql.setNullFragment(column))
      case .setInt(let column, let value):
        setClauses.append(StatusTransitionSql.setValueFragment(column))
        arguments.append(value)
      }
    }
    arguments.append(taskId.asString)
    arguments.append(version)
    try db.execute(
      sql:
        "UPDATE tasks SET \(setClauses.joined(separator: ", ")) "
        + "WHERE id = ? AND ? > version",
      arguments: StatementArguments(arguments))
    guard db.changesCount == 1 else {
      throw StoreError.staleVersion(entity: EntityName.task, id: taskId.asString)
    }

    let cancelledReminderIds = try LifecycleReminders.cancelActiveReminders(
      db, taskId: taskId, now: now, version: version)
    let (affected, deleted) = try LifecycleDependencies.detachTaskDependencyEdges(
      db, taskId: taskId)
    return CancelTaskResult(
      updated: true,
      affectedDependentIds: affected,
      cancelledReminderIds: cancelledReminderIds,
      deletedDependencyEdges: deleted)
  }

  /// Reopen a non-open task: set status to `open` and clear completion /
  /// deferral metadata. Cancelled reminders stay cancelled; users can add new
  /// reminders explicitly after reopening.
  /// Returns `updated: false` when the task is already open or missing.
  /// Surfaces ``StoreError/staleVersion`` when the LWW gate rejects.
  public static func reopenTask(
    _ db: Database, taskId: TaskId, now: String, reminderVersion: String
  ) throws -> ReopenTaskResult {
    guard let oldStatus = try readTaskStatus(db, taskId: taskId) else {
      return ReopenTaskResult(updated: false, reopenedReminderIds: [])
    }
    if oldStatus == .open {
      return ReopenTaskResult(updated: false, reopenedReminderIds: [])
    }

    let rows = try LifecycleWriteStatus.writeStatusAndMetadata(
      db, taskId: taskId,
      oldStatus: oldStatus, newStatus: .open,
      now: now, version: reminderVersion)
    if rows == 0 {
      throw StoreError.staleVersion(entity: "task", id: taskId.asString)
    }

    return ReopenTaskResult(updated: true, reopenedReminderIds: [])
  }
}
