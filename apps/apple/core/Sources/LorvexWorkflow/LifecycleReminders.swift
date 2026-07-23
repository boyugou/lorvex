import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Reminder-side lifecycle primitives shared by `status_side_effects` and
/// the per-status mutators.
public enum LifecycleReminders {
  /// Cancel every active (non-dismissed, non-cancelled) reminder for `taskId`
  /// whose `version` is strictly less than `version`. Returns the IDs that
  /// were actually flipped — peers landing between the SELECT and the UPDATE
  /// (LWW losers) are trimmed from the result, so callers only enqueue
  /// outbox envelopes for rows this call actually mutated.
  ///
  /// The captured-ids ⇒ id-scoped UPDATE pattern closes the TOCTOU window
  /// that a shared `WHERE` body would leave open. The trim re-query keys on
  /// `version = ?` rather than `cancelled_at = ?` because HLC versions are
  /// globally unique per device suffix — no concurrent writer can produce
  /// the same string, regardless of timestamp-string formatting drift.
  public static func cancelActiveReminders(
    _ db: Database, taskId: TaskId, now: String, version: String
  ) throws -> [String] {
    let ids: [String] = try String.fetchAll(
      db,
      sql:
        "SELECT id FROM task_reminders "
        + "WHERE task_id = ?1 AND dismissed_at IS NULL AND cancelled_at IS NULL "
        + "  AND ?2 > version",
      arguments: [taskId.asString, version])

    if ids.isEmpty { return ids }

    let placeholders = Sql.sqlCsvPlaceholders(ids.count)
    var args: [DatabaseValueConvertible] = [now, version]
    args.append(contentsOf: ids)
    let updateSql =
      "UPDATE task_reminders SET cancelled_at = ?1, version = ?2 "
      + "WHERE id IN (\(placeholders)) AND ?2 > version"
    try db.execute(sql: updateSql, arguments: StatementArguments(args))
    // GRDB exposes `db.changesCount` for the most recent statement.
    let updated = db.changesCount

    if updated == ids.count {
      return ids
    }

    // LWW gate rejected some captured ids — trim the returned set by
    // re-querying on `version = ?` (HLC strings are globally unique).
    var trimmedArgs: [DatabaseValueConvertible] = ids.map { $0 }
    trimmedArgs.append(version)
    let trimmedSql =
      "SELECT id FROM task_reminders "
      + "WHERE id IN (\(placeholders)) AND version = ?"
    return try String.fetchAll(
      db, sql: trimmedSql, arguments: StatementArguments(trimmedArgs))
  }

}
