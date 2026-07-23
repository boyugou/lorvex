import Foundation
import GRDB
import LorvexDomain

/// Identity and content fields for a row of `tasks`.
///
/// `priority` is `nil` or one of `1...3`; the schema CHECK is the canonical
/// contract.
public struct TaskCore: Sendable, Equatable {
  public let id: String
  public let title: String
  public let body: String?
  public let rawInput: String?
  public let aiNotes: String?
  public let status: String
  public let listId: String
  public let priority: Int64?
  public let contentVersion: String
  public let version: String
  public let createdAt: String
  public let updatedAt: String
}

/// Scheduling fields for a row of `tasks` — when it is planned, deferred,
/// estimated. `dueDate` is the external deadline (the `tasks.due_date`
/// column, `nil` when unscheduled).
public struct TaskScheduling: Sendable, Equatable {
  public let dueDate: LorvexDate?
  public let estimatedMinutes: Int64?
  public let plannedDate: LorvexDate?
  /// Civil date before which the task is hidden from day surfaces
  /// (defer-until / hide-until). UTC-midnight anchored like `plannedDate`,
  /// so it survives timezone change. `nil` means "never hidden".
  public let availableFrom: LorvexDate?
  public let deferCount: Int64
  public let lastDeferredAt: String?
  public let lastDeferReason: String?
  public let scheduleVersion: String
}

/// Recurrence-related fields for a row of `tasks`.
///
/// `recurrenceExceptions` is the wire-form JSON array of `YYYY-MM-DD` strings
/// rebuilt by the SELECT projection from the `task_recurrence_exceptions`
/// child table (the column itself was retired in the schema). `nil` when no
/// exceptions exist.
public struct TaskRecurrenceState: Sendable, Equatable {
  public let recurrence: String?
  public let recurrenceExceptions: String?
  public let spawnedFrom: String?
  public let spawnedFromVersion: String?
  public let recurrenceGroupId: String?
  public let canonicalOccurrenceDate: LorvexDate?
  public let recurrenceInstanceKey: String?
}

/// Durable recurrence-rollover decision carried by the task lifecycle
/// register. The raw values are the canonical SQLite/sync vocabulary.
public enum TaskRecurrenceRolloverState: String, Sendable, Equatable {
  case none
  case authorized
  case revoked
  case ended
}

/// Lifecycle and archive state for a row of `tasks`.
///
/// `archivedAt` is the soft-delete / Trash marker. Non-`nil` means the row is
/// in Trash and must be hidden from every user-facing read path (lists,
/// stats, search, counts). `completedAt` is set by status transitions into
/// `completed`.
public struct TaskLifecycleState: Sendable, Equatable {
  public let completedAt: String?
  public let archivedAt: String?
  public let lifecycleVersion: String
  public let archiveVersion: String
  public let recurrenceRolloverState: TaskRecurrenceRolloverState
  public let recurrenceSuccessorId: String?
}

/// One row read from the `tasks` table, with the recurrence-exceptions JSON
/// column synthesized from `task_recurrence_exceptions` via the canonical
/// SELECT projection.
///
/// Decomposed into four sub-structs by lifecycle role
/// (``TaskCore`` / ``TaskScheduling`` / ``TaskRecurrenceState`` /
/// ``TaskLifecycleState``) — every reader in this module returns
/// ``TaskRow`` regardless of which child concern it queries.
public struct TaskRow: Sendable, Equatable {
  public let core: TaskCore
  public let scheduling: TaskScheduling
  public let recurrence: TaskRecurrenceState
  public let lifecycle: TaskLifecycleState
}

/// `tasks`-table read/write operations.
///
/// Static methods only; nest read/write sides under sibling namespaces
/// (``Read``, ...) so call sites read as `TaskRepo.Read.getTask(...)`. New
/// sub-namespaces land alongside the existing ones as the cluster ports
/// in.
public enum TaskRepo {

  // ---------------------------------------------------------------------
  // Canonical SELECT projection
  // ---------------------------------------------------------------------

  /// Canonical SELECT column projection for `tasks`. The
  /// `recurrence_exceptions` slot is a correlated subquery against
  /// `task_recurrence_exceptions` rebuilt as a JSON array of
  /// `YYYY-MM-DD` exception dates, matching the canonical wire form.
  ///
  /// Index order matches ``rowToTaskRow(_:)``:
  ///
  ///  0 id  1 title  2 body  3 raw_input  4 ai_notes
  ///  5 status  6 list_id  7 priority  8 due_date
  ///  9 estimated_minutes  10 recurrence
  ///  11 recurrence_exceptions  12 spawned_from  13 recurrence_group_id
  ///  14 canonical_occurrence_date  15 version  16 created_at  17 updated_at
  ///  18 completed_at  19 last_deferred_at  20 last_defer_reason
  ///  21 planned_date  22 defer_count  23 recurrence_instance_key
  ///  24 archived_at  25 available_from  26 content_version
  ///  27 schedule_version  28 lifecycle_version  29 archive_version
  ///  30 recurrence_rollover_state  31 recurrence_successor_id
  ///  32 spawned_from_version
  public static let taskColumns: String =
    "id, title, body, raw_input, ai_notes, "
    + "status, list_id, priority, due_date, "
    + "estimated_minutes, recurrence, "
    + "(SELECT NULLIF(json_group_array(exception_date), '[]') "
    + "FROM (SELECT exception_date FROM task_recurrence_exceptions WHERE task_id = tasks.id ORDER BY exception_date)) AS recurrence_exceptions"
    + ", spawned_from, recurrence_group_id, canonical_occurrence_date, "
    + "version, created_at, updated_at, completed_at, last_deferred_at, "
    + "last_defer_reason, planned_date, defer_count, recurrence_instance_key, "
    + "archived_at, available_from, content_version, schedule_version, "
    + "lifecycle_version, archive_version, recurrence_rollover_state, "
    + "recurrence_successor_id, spawned_from_version"

  /// Build the same projection as ``taskColumns`` with every plain
  /// column prefixed with `<alias>.` and the `recurrence_exceptions`
  /// correlated subquery rewired against `<alias>.id` rather than
  /// `tasks.id`. Used by JOIN-shaped queries (e.g. tag-scoped reads)
  /// that need the projection over an aliased table.
  public static func taskColumnsQualified(_ alias: String) -> String {
    let qualified = #"""
      \#(alias).id, \#(alias).title, \#(alias).body, \#(alias).raw_input, \#(alias).ai_notes, \#(alias).status, \#(alias).list_id, \#(alias).priority, \#(alias).due_date, \#(alias).estimated_minutes, \#(alias).recurrence, (SELECT NULLIF(json_group_array(exception_date), '[]') FROM (SELECT exception_date FROM task_recurrence_exceptions WHERE task_id = \#(alias).id ORDER BY exception_date)) AS recurrence_exceptions, \#(alias).spawned_from, \#(alias).recurrence_group_id, \#(alias).canonical_occurrence_date, \#(alias).version, \#(alias).created_at, \#(alias).updated_at, \#(alias).completed_at, \#(alias).last_deferred_at, \#(alias).last_defer_reason, \#(alias).planned_date, \#(alias).defer_count, \#(alias).recurrence_instance_key, \#(alias).archived_at, \#(alias).available_from, \#(alias).content_version, \#(alias).schedule_version, \#(alias).lifecycle_version, \#(alias).archive_version, \#(alias).recurrence_rollover_state, \#(alias).recurrence_successor_id, \#(alias).spawned_from_version
      """#
    return qualified
  }

  /// Canonical ORDER BY clause for task list queries.
  ///
  /// Must be paired with a `SELECT ... FROM tasks` using the
  /// `priority_effective` virtual column. `id ASC` is the deterministic
  /// tiebreaker required for stable OFFSET pagination — never substitute
  /// `created_at DESC`, which is not stable across HLC advancement or
  /// sync-apply rewrites.
  public static let taskOrderBy: String =
    "priority_effective ASC, due_date ASC NULLS LAST, id ASC"

  /// ``taskOrderBy`` with every leading column prefixed with the given
  /// table alias (e.g. `t.priority_effective ASC, ...`). Used by
  /// JOIN-shaped queries that need the canonical ordering over an
  /// aliased table.
  public static func taskOrderByQualified(_ alias: String) -> String {
    "\(alias).priority_effective ASC, \(alias).due_date ASC NULLS LAST, \(alias).id ASC"
  }

  // ---------------------------------------------------------------------
  // Row mapping
  // ---------------------------------------------------------------------

  /// Map one GRDB ``Row`` produced by a SELECT over ``taskColumns`` into a
  /// ``TaskRow``. Surfaces a malformed persisted `due_date` — a non-canonical
  /// `YYYY-MM-DD` value — as a `DatabaseError` at the row boundary.
  static func rowToTaskRow(_ row: Row) throws -> TaskRow {
    let dueDateRaw: String? = row[8]
    let dueDate = try parseOptionalDate(dueDateRaw, column: "due_date")

    let plannedDateRaw: String? = row[21]
    let plannedDate = try parseOptionalDate(plannedDateRaw, column: "planned_date")

    let availableFromRaw: String? = row[25]
    let availableFrom = try parseOptionalDate(availableFromRaw, column: "available_from")

    let canonicalOccurrenceRaw: String? = row[14]
    let canonicalOccurrenceDate = try parseOptionalDate(
      canonicalOccurrenceRaw, column: "canonical_occurrence_date")

    let rolloverRaw: String = row[30]
    guard let rolloverState = TaskRecurrenceRolloverState(rawValue: rolloverRaw) else {
      throw DatabaseError(
        resultCode: .SQLITE_MISMATCH,
        message: "tasks.recurrence_rollover_state has unknown value: \(rolloverRaw)")
    }

    return TaskRow(
      core: TaskCore(
        id: row[0],
        title: row[1],
        body: row[2],
        rawInput: row[3],
        aiNotes: row[4],
        status: row[5],
        listId: row[6],
        priority: row[7],
        contentVersion: row[26],
        version: row[15],
        createdAt: row[16],
        updatedAt: row[17]),
      scheduling: TaskScheduling(
        dueDate: dueDate,
        estimatedMinutes: row[9],
        plannedDate: plannedDate,
        availableFrom: availableFrom,
        deferCount: row[22],
        lastDeferredAt: row[19],
        lastDeferReason: row[20],
        scheduleVersion: row[27]),
      recurrence: TaskRecurrenceState(
        recurrence: row[10],
        recurrenceExceptions: row[11],
        spawnedFrom: row[12],
        spawnedFromVersion: row[32],
        recurrenceGroupId: row[13],
        canonicalOccurrenceDate: canonicalOccurrenceDate,
        recurrenceInstanceKey: row[23]),
      lifecycle: TaskLifecycleState(
        completedAt: row[18],
        archivedAt: row[24],
        lifecycleVersion: row[28],
        archiveVersion: row[29],
        recurrenceRolloverState: rolloverState,
        recurrenceSuccessorId: row[31]))
  }

  static func parseOptionalDate(_ raw: String?, column: String) throws -> LorvexDate? {
    guard let raw else { return nil }
    switch LorvexDate.parse(raw) {
    case let .success(date):
      return date
    case let .failure(error):
      throw DatabaseError(
        resultCode: .SQLITE_MISMATCH,
        message: "tasks.\(column) is not a canonical YYYY-MM-DD date: \(error.description)")
    }
  }
}
