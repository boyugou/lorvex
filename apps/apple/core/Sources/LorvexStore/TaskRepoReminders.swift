import Foundation
import GRDB
import LorvexDomain

extension TaskRepo {
  /// Shared reminder query repository — due and upcoming task reminders.
  ///
  /// Joins `task_reminder_delivery_state` to filter by
  /// `delivery_state = 'pending'` (the authoritative device-local delivery
  /// gate).
  public enum Reminders {

    /// A single reminder row joined with its parent task's key fields and
    /// device-local delivery state.
    ///
    /// Timestamp fields are typed ``SyncTimestamp``; task dates are typed
    /// ``LorvexDate`` (`YYYY-MM-DD`).
    public struct ReminderRow: Sendable, Equatable {
      public let id: String
      public let taskId: String
      public let reminderAt: SyncTimestamp
      public let dismissedAt: SyncTimestamp?
      public let cancelledAt: SyncTimestamp?
      public let createdAt: SyncTimestamp
      public let deliveryState: String
      public let taskTitle: String
      public let taskStatus: String
      public let taskDueDate: LorvexDate?
      public let taskPlannedDate: LorvexDate?
      public let taskPriority: Int64?
    }

    /// Result envelope for reminder queries, including pagination metadata.
    ///
    /// `totalMatching` is the count of matching rows, or the sentinel `-1`
    /// when the result was truncated (the LIMIT+1 probe found at least one
    /// more row than the caller asked for).
    public struct ReminderQueryResult: Sendable, Equatable {
      public let rows: [ReminderRow]
      public let totalMatching: Int64
    }

    static func reminderFromRow(_ row: Row) throws -> ReminderRow {
      func parseTs(_ idx: Int, _ column: String) throws -> SyncTimestamp {
        let raw: String = row[idx]
        guard let ts = SyncTimestamp.parse(raw) else {
          throw DatabaseError(
            resultCode: .SQLITE_MISMATCH,
            message: "task_reminders.\(column) is not a canonical sync timestamp: \(raw)")
        }
        return ts
      }
      func parseOptTs(_ idx: Int, _ column: String) throws -> SyncTimestamp? {
        let raw: String? = row[idx]
        guard let raw else { return nil }
        guard let ts = SyncTimestamp.parse(raw) else {
          throw DatabaseError(
            resultCode: .SQLITE_MISMATCH,
            message: "task_reminders.\(column) is not a canonical sync timestamp: \(raw)")
        }
        return ts
      }

      let dueRaw: String? = row[9]
      let dueDate = try TaskRepo.parseOptionalDate(dueRaw, column: "due_date")
      let plannedRaw: String? = row[10]
      let plannedDate = try TaskRepo.parseOptionalDate(plannedRaw, column: "planned_date")

      return ReminderRow(
        id: row[0],
        taskId: row[1],
        reminderAt: try parseTs(2, "reminder_at"),
        dismissedAt: try parseOptTs(3, "dismissed_at"),
        cancelledAt: try parseOptTs(4, "cancelled_at"),
        createdAt: try parseTs(5, "created_at"),
        deliveryState: row[6],
        taskTitle: row[7],
        taskStatus: row[8],
        taskDueDate: dueDate,
        taskPlannedDate: plannedDate,
        taskPriority: row[11])
    }

    /// Reminders currently due (`reminder_at <= now`) for open, non-archived
    /// tasks that are not dismissed, cancelled, or already delivered/snoozed.
    public static func getDueTaskReminders(
      _ db: Database, now: String, limit: UInt32
    ) throws -> ReminderQueryResult {
      let fetchLimit = Int64(limit) + 1
      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT tr.id, tr.task_id, tr.reminder_at, tr.dismissed_at, tr.cancelled_at, \
                 tr.created_at, \
                 COALESCE(ds.delivery_state, 'pending') AS delivery_state, \
                 t.title, t.status, t.due_date, t.planned_date, t.priority \
          FROM task_reminders tr \
          JOIN tasks t ON tr.task_id = t.id \
          LEFT JOIN task_reminder_delivery_state ds ON ds.reminder_id = tr.id \
          WHERE t.status IN (\(StatusName.actionableStatusSqlList)) \
            AND t.archived_at IS NULL \
            AND tr.cancelled_at IS NULL \
            AND tr.dismissed_at IS NULL \
            AND COALESCE(ds.delivery_state, 'pending') = 'pending' \
            AND tr.reminder_at <= ?1 \
          ORDER BY tr.reminder_at ASC, tr.id ASC \
          LIMIT ?2
          """,
        arguments: [now, fetchLimit])
      return try truncateResult(rows, limit: limit)
    }

    /// Mark every currently-due reminder that was actually armed as delivered —
    /// the device-local "the OS has already shown this" stamp that stops
    /// ``getDueTaskReminders`` from re-surfacing it. A reminder qualifies once
    /// `reminder_at <= now` for a live (open, non-archived) task whose reminder
    /// is neither cancelled nor dismissed, not already delivered, AND whose
    /// notification request was actually submitted to the OS (its
    /// `last_armed_at` stamp is present, written by ``replaceRemindersArmed``
    /// after ``TaskReminderScheduling`` armed it). Returns how many rows were
    /// newly marked; idempotent (a second call with the same `now` marks
    /// nothing).
    ///
    /// The deterministic analog of an OS delivery callback: Apple pre-schedules
    /// notifications to the system, which fires them with no reliable delegate
    /// callback, so "delivered" is derived from the scheduled time elapsing —
    /// but only for a request that was truly armed. A reminder that was budgeted
    /// out of the pending-notification cap, dropped because authorization was
    /// denied, or lost to an `add` failure has no `last_armed_at` stamp and
    /// therefore stays `pending`, so a genuine miss is never recorded as a
    /// delivery and remains visible to assistant/MCP due queries.
    @discardableResult
    public static func markDueRemindersDelivered(
      _ db: Database, now: String
    ) throws -> Int {
      try db.execute(
        sql: """
          INSERT INTO task_reminder_delivery_state \
              (reminder_id, last_delivered_at, delivery_state, updated_at) \
          SELECT tr.id, ?1, 'delivered', ?1 \
          FROM task_reminders tr \
          JOIN tasks t ON tr.task_id = t.id \
          JOIN task_reminder_delivery_state ds ON ds.reminder_id = tr.id \
          WHERE t.status IN (\(StatusName.actionableStatusSqlList)) \
            AND t.archived_at IS NULL \
            AND tr.cancelled_at IS NULL \
            AND tr.dismissed_at IS NULL \
            AND tr.reminder_at <= ?1 \
            AND ds.last_armed_at IS NOT NULL \
            AND ds.delivery_state = 'pending' \
          ON CONFLICT(reminder_id) DO UPDATE SET \
            delivery_state = 'delivered', \
            last_delivered_at = excluded.last_delivered_at, \
            updated_at = excluded.updated_at
          """,
        arguments: [now])
      return db.changesCount
    }

    /// Replace the device's armed-reminder record with exactly the reminder
    /// ids the scheduler reported as armed this pass (the earliest-due subset
    /// that fit the shared budget and cleared authorization).
    ///
    /// Two writes keep `last_armed_at` a mirror of the currently pending
    /// `UNUserNotificationCenter` request set, which every reschedule pass
    /// rebuilds from scratch:
    /// - each armed id is stamped with `armedAt` (fresh rows start `pending`);
    /// - every still-`pending` row NOT in the armed set has `last_armed_at`
    ///   cleared back to NULL, because the replace pass just removed its OS
    ///   request (budgeted out, permission denied, or add failed).
    ///
    /// ``markDueRemindersDelivered`` requires a non-NULL `last_armed_at`
    /// before it will ever transition a reminder to `delivered`, so clearing
    /// keeps a dropped request visible as `pending` instead of letting a stale
    /// armed stamp record a phantom delivery. Rows already `delivered` keep
    /// their historical stamp.
    public static func replaceRemindersArmed(
      _ db: Database, armedReminderIDs: [String], armedAt: String
    ) throws {
      let placeholders = Array(
        repeating: "?", count: armedReminderIDs.count
      ).joined(separator: ", ")
      let notInClause =
        armedReminderIDs.isEmpty ? "" : "AND reminder_id NOT IN (\(placeholders)) "
      try db.execute(
        sql: """
          UPDATE task_reminder_delivery_state SET \
            last_armed_at = NULL, \
            updated_at = ?1 \
          WHERE delivery_state = 'pending' \
            AND last_armed_at IS NOT NULL \
            \(notInClause)
          """,
        arguments: StatementArguments([armedAt] + armedReminderIDs))
      for reminderID in armedReminderIDs {
        try db.execute(
          sql: """
            INSERT INTO task_reminder_delivery_state \
                (reminder_id, last_armed_at, delivery_state, updated_at) \
            VALUES (?1, ?2, 'pending', ?2) \
            ON CONFLICT(reminder_id) DO UPDATE SET \
              last_armed_at = excluded.last_armed_at, \
              updated_at = excluded.updated_at
            """,
          arguments: [reminderID, armedAt])
      }
    }

    /// Reminders due within an exact timestamp window
    /// (`now < reminder_at <= horizon`) for open, non-archived, undelivered
    /// tasks.
    public static func getUpcomingTaskRemindersUntil(
      _ db: Database, now: String, horizon: String, limit: UInt32
    ) throws -> ReminderQueryResult {
      let fetchLimit = Int64(limit) + 1
      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT tr.id, tr.task_id, tr.reminder_at, tr.dismissed_at, tr.cancelled_at, \
                 tr.created_at, \
                 COALESCE(ds.delivery_state, 'pending') AS delivery_state, \
                 t.title, t.status, t.due_date, t.planned_date, t.priority \
          FROM task_reminders tr \
          JOIN tasks t ON tr.task_id = t.id \
          LEFT JOIN task_reminder_delivery_state ds ON ds.reminder_id = tr.id \
          WHERE t.status IN (\(StatusName.actionableStatusSqlList)) \
            AND t.archived_at IS NULL \
            AND tr.cancelled_at IS NULL \
            AND tr.dismissed_at IS NULL \
            AND COALESCE(ds.delivery_state, 'pending') = 'pending' \
            AND tr.reminder_at > ?1 \
            AND tr.reminder_at <= ?2 \
          ORDER BY tr.reminder_at ASC, tr.id ASC \
          LIMIT ?3
          """,
        arguments: [now, horizon, fetchLimit])
      return try truncateResult(rows, limit: limit)
    }

    /// Apply the LIMIT+1 truncation-detection: if more rows came back than
    /// `limit`, drop the surplus and signal truncation with
    /// `total_matching = -1`; otherwise `total_matching` is the exact count.
    private static func truncateResult(
      _ rows: [Row], limit: UInt32
    ) throws -> ReminderQueryResult {
      var mapped = try rows.map(reminderFromRow)
      let truncated = mapped.count > Int(limit)
      if truncated {
        mapped = Array(mapped.prefix(Int(limit)))
      }
      let totalMatching: Int64 = truncated ? -1 : Int64(mapped.count)
      return ReminderQueryResult(rows: mapped, totalMatching: totalMatching)
    }
  }
}
