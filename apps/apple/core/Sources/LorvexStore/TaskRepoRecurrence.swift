import Foundation
import GRDB
import LorvexDomain

extension TaskRepo {
  /// Recurrence-exception (EXDATE) add/remove operations for `tasks`.
  ///
  /// Delegates to ``RecurrenceExceptionsCommon`` for the shared validation,
  /// transaction, and LWW-gated UPDATE pipeline; this enum only declares the
  /// per-table config.
  public enum Recurrence {

    static let config = RecurrenceExceptionsCommon.ExceptionTableConfig(
      entity: EntityName.task,
      entityNoun: "Task",
      anchorLabel: "task canonical occurrence date",
      selectAnchorSQL: """
        SELECT recurrence, \
        (SELECT NULLIF(json_group_array(exception_date), '[]') \
         FROM (SELECT exception_date FROM task_recurrence_exceptions WHERE task_id = tasks.id ORDER BY exception_date)), \
        canonical_occurrence_date \
        FROM tasks WHERE id = ?
        """,
      bumpVersionSQL: """
        UPDATE tasks SET schedule_version = :version, version = :version, updated_at = :now \
        WHERE id = :id AND :version > version
        """)

    /// Add a recurrence exception date to a task.
    ///
    /// Validates: task exists, task is recurring, date is valid YYYY-MM-DD,
    /// date >= canonical_occurrence_date, date is an actual occurrence of the
    /// recurrence rule, and date is not already in the exceptions list.
    /// Returns the updated exceptions JSON string.
    @discardableResult
    public static func addTaskRecurrenceException(
      _ writer: any DatabaseWriter, taskId: TaskId,
      exceptionDate: String, version: String, now: String
    ) throws -> String {
      try RecurrenceExceptionsCommon.addException(
        writer, config, id: taskId.rawValue,
        exceptionDate: exceptionDate, version: version, now: now)
    }

    /// Remove a recurrence exception date from a task.
    ///
    /// Validates: task exists, date is valid YYYY-MM-DD, and date is in the
    /// current exceptions list. Returns the updated exceptions JSON string,
    /// or `nil` if the list is now empty.
    @discardableResult
    public static func removeTaskRecurrenceException(
      _ writer: any DatabaseWriter, taskId: TaskId,
      exceptionDate: String, version: String, now: String
    ) throws -> String? {
      try RecurrenceExceptionsCommon.removeException(
        writer, config, id: taskId.rawValue,
        exceptionDate: exceptionDate, version: version, now: now)
    }

    /// Replace the complete recurrence-exception set inside the caller's
    /// transaction and stamp the owning task's schedule register at the same
    /// version. This is the low-level boundary for import/restore surfaces that
    /// already validated and normalized the whole set; interactive single-date
    /// edits should use the add/remove operations above.
    public static func replaceTaskRecurrenceExceptionsInTx(
      _ db: Database,
      taskId: TaskId,
      dates: [String],
      version: String,
      now: String
    ) throws {
      try RecurrenceExceptionsRepo.validateLocalExceptionCount(dates.count)
      try db.execute(
        sql: config.bumpVersionSQL,
        arguments: ["version": version, "now": now, "id": taskId.rawValue])
      if db.changesCount == 0 {
        let exists = try Int.fetchOne(
          db,
          sql: "SELECT 1 FROM tasks WHERE id = ?1",
          arguments: [taskId.rawValue]) != nil
        if exists {
          throw StoreError.staleVersion(entity: EntityName.task, id: taskId.asString)
        }
        throw StoreError.notFound(entity: EntityName.task, id: taskId.asString)
      }
      try RecurrenceExceptionsRepo.replaceTaskExceptions(
        db, taskId: taskId.asString, dates: dates)
    }
  }
}
