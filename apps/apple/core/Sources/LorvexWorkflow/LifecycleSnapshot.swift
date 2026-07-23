import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Pre-mutation snapshot of the task fields the lifecycle orchestrator
/// needs.
///
/// Read directly from the DB rather than threaded through adapter-specific
/// types so the same orchestrator works for every caller.
public struct LifecycleTaskSnapshot: Sendable, Equatable {
  public let recurrence: String?
  public let recurrenceExceptions: String?
  public let recurrenceGroupId: String?
  public let dueDate: String?
  public let plannedDate: String?
  public let availableFrom: String?
  public let canonicalOccurrenceDate: String?
  public let lifecycleVersion: String
  public let recurrenceRolloverState: TaskRecurrenceRolloverState
  public let recurrenceSuccessorId: String?

  public init(
    recurrence: String?,
    recurrenceExceptions: String?,
    recurrenceGroupId: String?,
    dueDate: String?,
    plannedDate: String?,
    availableFrom: String?,
    canonicalOccurrenceDate: String?,
    lifecycleVersion: String,
    recurrenceRolloverState: TaskRecurrenceRolloverState,
    recurrenceSuccessorId: String?
  ) {
    self.recurrence = recurrence
    self.recurrenceExceptions = recurrenceExceptions
    self.recurrenceGroupId = recurrenceGroupId
    self.dueDate = dueDate
    self.plannedDate = plannedDate
    self.availableFrom = availableFrom
    self.canonicalOccurrenceDate = canonicalOccurrenceDate
    self.lifecycleVersion = lifecycleVersion
    self.recurrenceRolloverState = recurrenceRolloverState
    self.recurrenceSuccessorId = recurrenceSuccessorId
  }
}

/// Lifecycle pre-transition read helpers.
public enum LifecycleSnapshot {
  /// Read the active reminders' `reminder_at` strings for `taskId`,
  /// ordered by row `id`. Active = `dismissed_at IS NULL AND cancelled_at
  /// IS NULL`.
  public static func readActiveTaskReminderTimes(
    _ db: Database, taskId: TaskId
  ) throws -> [String] {
    try String.fetchAll(
      db,
      sql:
        "SELECT reminder_at FROM task_reminders "
        + "WHERE task_id = ?1 AND dismissed_at IS NULL AND cancelled_at IS NULL "
        + "ORDER BY id ASC",
      arguments: [taskId.asString])
  }

  /// Read the recurrence / date columns the lifecycle orchestrator needs
  /// before the row's `status` is flipped. Returns `nil` when the row is
  /// missing.
  public static func readTaskSnapshot(
    _ db: Database, taskId: TaskId
  ) throws -> LifecycleTaskSnapshot? {
    let row = try Row.fetchOne(
      db,
      sql:
        "SELECT recurrence, "
        + "(SELECT NULLIF(json_group_array(exception_date), '[]') "
        + " FROM (SELECT exception_date FROM task_recurrence_exceptions WHERE task_id = tasks.id ORDER BY exception_date)), "
        + "recurrence_group_id, due_date, planned_date, available_from, canonical_occurrence_date "
        + ", lifecycle_version, recurrence_rollover_state, recurrence_successor_id "
        + "FROM tasks WHERE id = ?1",
      arguments: [taskId.asString])
    guard let row = row else { return nil }
    let rolloverRaw: String = row[8]
    guard let rolloverState = TaskRecurrenceRolloverState(rawValue: rolloverRaw) else {
      throw StoreError.invariant(
        "task \(taskId.asString) has invalid recurrence_rollover_state \"\(rolloverRaw)\"")
    }
    return LifecycleTaskSnapshot(
      recurrence: row[0],
      recurrenceExceptions: row[1],
      recurrenceGroupId: row[2],
      dueDate: row[3],
      plannedDate: row[4],
      availableFrom: row[5],
      canonicalOccurrenceDate: row[6],
      lifecycleVersion: row[7],
      recurrenceRolloverState: rolloverState,
      recurrenceSuccessorId: row[9])
  }
}
