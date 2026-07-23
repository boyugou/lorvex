import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Canonical task-deferral SQL mutations.
///
/// `defer_task` increments `defer_count`, stamps `last_deferred_at`,
/// optionally writes `planned_date`, `ai_notes`, and `last_defer_reason`
/// in a single LWW-gated UPDATE. When the planned date changes, pending
/// reminders (not dismissed, not cancelled, not yet fired) for the task
/// are shifted by the same calendar-day delta, so a deferred task carries
/// its pending reminders with it. The reminder HLC stamps come from the caller via
/// the `nextReminderVersion` closure because each runtime owns its HLC
/// session.
///
/// Each entry returns `updated == false` when the LWW gate or status
/// filter rejects the write — callers re-stamp the HLC and retry.
public enum TaskDeferral {
  public struct DeferralPatch: Sendable {
    public var plannedDate: String?
    public var aiNotes: String?
    public var lastDeferReason: String?

    public init(
      plannedDate: String? = nil,
      aiNotes: String? = nil,
      lastDeferReason: String? = nil
    ) {
      self.plannedDate = plannedDate
      self.aiNotes = aiNotes
      self.lastDeferReason = lastDeferReason
    }
  }

  public struct DeferralResult: Sendable, Equatable {
    public var updated: Bool
    public var shiftedReminderIds: [String]

    public init(updated: Bool = false, shiftedReminderIds: [String] = []) {
      self.updated = updated
      self.shiftedReminderIds = shiftedReminderIds
    }
  }

  /// Multi-field snapshot of the pre-mutation deferral state that
  /// `restoreTaskDeferral` stamps back onto the row.
  public struct DeferralSnapshot: Sendable {
    public var plannedDate: String?
    public var deferCount: Int64
    public var lastDeferredAt: String?
    public var lastDeferReason: String?

    public init(
      plannedDate: String? = nil,
      deferCount: Int64 = 0,
      lastDeferredAt: String? = nil,
      lastDeferReason: String? = nil
    ) {
      self.plannedDate = plannedDate
      self.deferCount = deferCount
      self.lastDeferredAt = lastDeferredAt
      self.lastDeferReason = lastDeferReason
    }
  }

  /// Apply a single task deferral atomically inside a SAVEPOINT named
  /// `task_deferral`. Returns `updated == false` when the LWW gate
  /// rejects the stamp or the status filter excludes the row
  /// (`completed`, `cancelled`, or non-existent).
  public static func deferTask(
    _ db: Database,
    taskId: TaskId,
    patch: DeferralPatch,
    version: String,
    now: String,
    nextReminderVersion: () throws -> String
  ) throws -> DeferralResult {
    // `last_defer_reason` must be one of the canonical `DeferReason` categories.
    // Validating here — the single core write path every surface funnels through
    // (MCP, batch, intents) — means no caller can reach the raw
    // `CHECK (last_defer_reason IN (...))` and surface an opaque
    // `SQLITE_CONSTRAINT`; a bad category fails with a typed validation error.
    if let reason = patch.lastDeferReason, DeferReason.parse(reason) == nil {
      throw StoreError.validation(
        "last_defer_reason \"\(reason)\" is not a recognized defer reason "
          + "(expected one of: \(DeferReasonName.allDeferReasons.joined(separator: ", ")))")
    }
    try db.execute(sql: "SAVEPOINT task_deferral")
    do {
      let result = try deferTaskInner(
        db, taskId: taskId, patch: patch, version: version, now: now,
        nextReminderVersion: nextReminderVersion)
      try db.execute(sql: "RELEASE SAVEPOINT task_deferral")
      return result
    } catch {
      try? db.execute(sql: "ROLLBACK TO SAVEPOINT task_deferral")
      try? db.execute(sql: "RELEASE SAVEPOINT task_deferral")
      throw error
    }
  }

  private static func deferTaskInner(
    _ db: Database,
    taskId: TaskId,
    patch: DeferralPatch,
    version: String,
    now: String,
    nextReminderVersion: () throws -> String
  ) throws -> DeferralResult {
    let reminderShift: ReminderShiftContext?
    if let newPlanned = patch.plannedDate {
      reminderShift = try loadReminderShiftContext(
        db, taskId: taskId, newPlannedDate: newPlanned)
    } else {
      reminderShift = nil
    }

    var setClauses: [String] = [
      "defer_count = MIN(defer_count + 1, 9223372036854775807)"
    ]
    var args: [(any DatabaseValueConvertible)?] = []

    if let date = patch.plannedDate {
      args.append(date)
      setClauses.append("planned_date = ?\(args.count)")
    }
    if let notes = patch.aiNotes {
      args.append(notes)
      setClauses.append("ai_notes = ?\(args.count)")
    }
    if let reason = patch.lastDeferReason {
      args.append(reason)
      setClauses.append("last_defer_reason = ?\(args.count)")
    }

    args.append(now)
    let nowIdx = args.count
    setClauses.append("last_deferred_at = ?\(nowIdx)")
    setClauses.append("updated_at = ?\(nowIdx)")

    args.append(version)
    let versionIdx = args.count
    setClauses.append("schedule_version = ?\(versionIdx)")
    if patch.aiNotes != nil {
      setClauses.append("content_version = ?\(versionIdx)")
    }
    setClauses.append("version = ?\(versionIdx)")

    args.append(taskId.rawValue)
    let idIdx = args.count

    let sql =
      "UPDATE tasks SET \(setClauses.joined(separator: ", ")) "
      + "WHERE id = ?\(idIdx) AND status NOT IN ('completed', 'cancelled') "
      + "AND ?\(versionIdx) > version"

    try db.execute(sql: sql, arguments: StatementArguments(args))
    if db.changesCount == 0 {
      return DeferralResult()
    }

    let shiftedIds: [String]
    if let ctx = reminderShift {
      shiftedIds = try shiftPendingRemindersToNewPlannedDate(
        db, taskId: taskId, context: ctx, now: now,
        nextReminderVersion: nextReminderVersion)
    } else {
      shiftedIds = []
    }

    return DeferralResult(updated: true, shiftedReminderIds: shiftedIds)
  }

  /// Reset task deferral state: clear `planned_date`, `last_deferred_at`,
  /// `last_defer_reason`, and reset `defer_count` to 0. Returns `false`
  /// when the LWW gate rejects or the row is terminal / missing.
  public static func resetTaskDeferral(
    _ db: Database,
    taskId: TaskId,
    version: String,
    now: String
  ) throws -> Bool {
    try db.execute(
      sql:
        "UPDATE tasks SET "
        + "planned_date = NULL, "
        + "last_deferred_at = NULL, "
        + "last_defer_reason = NULL, "
        + "defer_count = 0, "
        + "schedule_version = ?, "
        + "version = ?, "
        + "updated_at = ? "
        + "WHERE id = ? AND status NOT IN ('completed', 'cancelled') "
        + "AND ? > version",
      arguments: [version, version, now, taskId.rawValue, version])
    return db.changesCount > 0
  }

  /// Restore the exact pre-defer deferral state captured in `snapshot`.
  /// Used by the single-action "Undo" toast path. LWW-gated; returns
  /// `false` when the gate rejects the stamp.
  public static func restoreTaskDeferral(
    _ db: Database,
    taskId: TaskId,
    snapshot: DeferralSnapshot,
    version: String,
    now: String
  ) throws -> Bool {
    try db.execute(
      sql:
        "UPDATE tasks SET "
        + "planned_date = ?, "
        + "defer_count = ?, "
        + "last_deferred_at = ?, "
        + "last_defer_reason = ?, "
        + "schedule_version = ?, "
        + "version = ?, "
        + "updated_at = ? "
        + "WHERE id = ? AND status NOT IN ('completed', 'cancelled') "
        + "AND ? > version",
      arguments: [
        snapshot.plannedDate, snapshot.deferCount, snapshot.lastDeferredAt,
        snapshot.lastDeferReason, version, version, now, taskId.rawValue, version,
      ])
    return db.changesCount > 0
  }

  // MARK: - Reminder shift

  private struct ReminderShiftContext {
    let oldReferenceDate: String
    let newPlannedDate: String
  }

  private static func loadReminderShiftContext(
    _ db: Database, taskId: TaskId, newPlannedDate: String
  ) throws -> ReminderShiftContext? {
    let row = try Row.fetchOne(
      db,
      sql: "SELECT COALESCE(planned_date, due_date) FROM tasks WHERE id = ?",
      arguments: [taskId.rawValue])
    guard let row else { return nil }
    let old: String? = row[0]
    guard let old else { return nil }
    return ReminderShiftContext(
      oldReferenceDate: old, newPlannedDate: newPlannedDate)
  }

  /// Walk all future pending reminders for the task and rewrite each
  /// `reminder_at` by the calendar-day delta between the old
  /// planned-or-due reference date and the new planned date. Each rewrite
  /// stamps a fresh HLC version pulled from the caller.
  ///
  /// Both reference dates come from validated write paths, so a parse
  /// failure implies on-disk corruption — surfaced as
  /// ``StoreError/validation`` so the deferral fails loudly rather than
  /// silently leaving stale reminders.
  private static func shiftPendingRemindersToNewPlannedDate(
    _ db: Database,
    taskId: TaskId,
    context: ReminderShiftContext,
    now: String,
    nextReminderVersion: () throws -> String
  ) throws -> [String] {
    let oldDate = try parseYMD(
      context.oldReferenceDate, label: "old_reference_date")
    let newDate = try parseYMD(
      context.newPlannedDate, label: "new_planned_date")
    let deltaDays = IsoDate.dayNumber(newDate) - IsoDate.dayNumber(oldDate)
    if deltaDays == 0 { return [] }

    // Shift reminders by calendar days in the user's anchored timezone so they
    // keep their local wall-clock time across a DST boundary.
    let reminderTimezone =
      TimeZone(identifier: try WorkflowTimezone.anchoredTimezoneName(db))
      ?? TimeZone(secondsFromGMT: 0)!

    let rows = try Row.fetchAll(
      db,
      sql:
        "SELECT id, reminder_at FROM task_reminders "
        + "WHERE task_id = ? AND dismissed_at IS NULL AND cancelled_at IS NULL "
        + "AND reminder_at > ?",
      arguments: [taskId.rawValue, now])

    var shifted: [String] = []
    for row in rows {
      let reminderId: String = row[0]
      let reminderAt: String = row[1]
      let shiftedAt = try shiftRFC3339(reminderAt, byDays: deltaDays,
        timezone: reminderTimezone, reminderId: reminderId)
      let reminderVersion = try nextReminderVersion()
      try db.execute(
        sql:
          "UPDATE task_reminders SET reminder_at = ?, version = ? "
          + "WHERE id = ? AND ? > version",
        arguments: [shiftedAt, reminderVersion, reminderId, reminderVersion])
      if db.changesCount > 0 {
        shifted.append(reminderId)
      }
    }
    return shifted
  }

  // MARK: - Date helpers

  /// Parse a canonical `YYYY-MM-DD` string into a validated calendar date via
  /// the shared ``IsoDate/parse(_:)``. Throws ``StoreError/validation`` on
  /// malformed input.
  private static func parseYMD(_ s: String, label: String) throws -> IsoDate.YMD {
    guard let ymd = IsoDate.parse(s) else {
      throw StoreError.validation(
        "shift_pending_reminders: corrupt \(label) \"\(s)\""
      )
    }
    return ymd
  }

  /// Shift an RFC3339 timestamp by `days` calendar days in `timezone`,
  /// preserving the fractional-second / `Z` sync-timestamp formatting.
  ///
  /// Advancing by *calendar* days in the user's timezone (rather than a fixed
  /// `days * 86400` seconds) keeps the reminder's local wall-clock time across a
  /// DST transition — otherwise a 09:00 reminder deferred across spring-forward
  /// would re-fire at 10:00.
  private static func shiftRFC3339(
    _ timestamp: String, byDays days: Int, timezone: TimeZone, reminderId: String
  ) throws -> String {
    guard let parsed = ReminderAnchor.parseRfc3339ToDate(timestamp) else {
      throw StoreError.validation(
        "shift_pending_reminders: corrupt stored reminder_at \"\(timestamp)\" for reminder \(reminderId)"
      )
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timezone
    guard let shifted = calendar.date(byAdding: .day, value: days, to: parsed) else {
      throw StoreError.validation(
        "shift_pending_reminders: could not shift reminder_at \"\(timestamp)\" by \(days) days for reminder \(reminderId)"
      )
    }
    return SyncTimestampFormat.formatSyncTimestamp(shifted)
  }
}
