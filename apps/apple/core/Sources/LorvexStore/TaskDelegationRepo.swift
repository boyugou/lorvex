import Foundation
import GRDB
import LorvexDomain

/// Reads of `task_delegations`: the tasks handed to an assignee.
public enum TaskDelegationRepo {
  private static let columns = "task_id, assignee, state, request, created_at, updated_at"

  private static func record(_ row: Row) throws -> TaskDelegationRecord {
    let rawState: String = row["state"]
    guard let state = TaskDelegationState(rawValue: rawState) else {
      throw StoreError.invariant("task_delegations.state holds '\(rawState)'")
    }
    return TaskDelegationRecord(
      taskId: row["task_id"], assignee: row["assignee"], state: state, request: row["request"],
      createdAt: row["created_at"], updatedAt: row["updated_at"])
  }

  /// The delegation of `taskId` to `assignee`, or nil when the task is not
  /// handed to them.
  public static func delegation(
    _ db: Database, taskId: String, assignee: String
  ) throws -> TaskDelegationRecord? {
    try Row.fetchOne(
      db, sql: "SELECT \(columns) FROM task_delegations WHERE task_id = ? AND assignee = ?",
      arguments: [taskId, assignee]
    ).map(record)
  }

  /// Every task handed to `assignee`, keyed by task id. The table holds one
  /// row per delegated task, so a caller that decorates a page of tasks reads
  /// it whole instead of binding the page's ids.
  public static func delegations(
    _ db: Database, assignee: String
  ) throws -> [String: TaskDelegationRecord] {
    var out: [String: TaskDelegationRecord] = [:]
    for row in try Row.fetchAll(
      db, sql: "SELECT \(columns) FROM task_delegations WHERE assignee = ?",
      arguments: [assignee])
    {
      let record = try record(row)
      out[record.taskId] = record
    }
    return out
  }

  /// How many tasks `assignee` holds (`state`), counting only tasks that are
  /// still actionable and not in the Trash: a finished or deleted task is
  /// nobody's to work on.
  public static func count(
    _ db: Database, assignee: String, state: TaskDelegationState
  ) throws -> Int {
    try Int.fetchOne(
      db,
      sql: """
        SELECT COUNT(*) FROM task_delegations d
        JOIN tasks t ON t.id = d.task_id
        WHERE d.assignee = ? AND d.state = ?
          AND t.archived_at IS NULL AND t.status IN ('open', 'in_progress')
        """,
      arguments: [assignee, state.rawValue]) ?? 0
  }
}
