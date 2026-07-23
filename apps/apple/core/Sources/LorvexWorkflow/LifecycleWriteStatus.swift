import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// LWW-gated UPDATE that flips `tasks.status` plus the metadata columns
/// dictated by ``statusTransitionColumns(oldStatus:newStatus:now:)``.
public enum LifecycleWriteStatus {
  /// Returns the number of rows changed (0 or 1). Zero means either the
  /// row is missing or the caller's `version` lost the `?{n} > version`
  /// LWW comparison. Callers that pre-checked existence should treat
  /// `0` as ``StoreError/staleVersion`` and surface accordingly.
  public static func writeStatusAndMetadata(
    _ db: Database,
    taskId: TaskId,
    oldStatus: TaskStatus,
    newStatus: TaskStatus,
    now: String,
    version: String
  ) throws -> Int {
    let transitionActions = statusTransitionColumns(
      oldStatus: oldStatus, newStatus: newStatus, now: now)
    let touchesScheduleMetadata = transitionActions.contains { action in
      switch action {
      case .setText(let column, _), .setNull(let column), .setInt(let column, _):
        return column != "completed_at"
      }
    }

    var setClauses: [String] = [
      "status = ?", "updated_at = ?", "version = ?", "lifecycle_version = ?",
    ]
    var args: [DatabaseValueConvertible] = [
      newStatus.asString, now, version, version,
    ]

    if touchesScheduleMetadata {
      setClauses.append("schedule_version = ?")
      args.append(version)
    } else if oldStatus.isTerminal != newStatus.isTerminal {
      setClauses.append(
        "schedule_version = CASE WHEN recurrence IS NOT NULL THEN ? ELSE schedule_version END")
      args.append(version)
    }

    if newStatus.isTerminal {
      setClauses.append(
        "recurrence_rollover_state = CASE WHEN recurrence IS NULL THEN 'none' ELSE 'ended' END")
      setClauses.append("recurrence_successor_id = NULL")
    } else if oldStatus.isTerminal {
      setClauses.append(
        "recurrence_rollover_state = CASE "
          + "WHEN recurrence_rollover_state = 'authorized' THEN 'revoked' "
          + "WHEN recurrence_rollover_state = 'ended' THEN 'none' "
          + "ELSE recurrence_rollover_state END")
      setClauses.append(
        "recurrence_successor_id = CASE "
          + "WHEN recurrence_rollover_state = 'authorized' THEN recurrence_successor_id "
          + "WHEN recurrence_rollover_state = 'ended' THEN NULL "
          + "ELSE recurrence_successor_id END")
    }

    for action in transitionActions {
      switch action {
      case .setText(let col, let val):
        setClauses.append(StatusTransitionSql.setValueFragment(col))
        args.append(val)
      case .setNull(let col):
        setClauses.append(StatusTransitionSql.setNullFragment(col))
      case .setInt(let col, let val):
        setClauses.append(StatusTransitionSql.setValueFragment(col))
        args.append(val)
      }
    }

    args.append(taskId.asString)
    args.append(version)

    let sql =
      "UPDATE tasks SET \(setClauses.joined(separator: ", ")) "
      + "WHERE id = ? AND ? > version"
    try db.execute(sql: sql, arguments: StatementArguments(args))
    return db.changesCount
  }
}
