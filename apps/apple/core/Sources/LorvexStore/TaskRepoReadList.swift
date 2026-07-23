import Foundation
import GRDB
import LorvexDomain

extension TaskRepo {

  // MARK: - Filter / sort vocabulary

  /// Status selector for ``TaskRepo/Read/listTasks(_:query:)``. `all` applies
  /// no `status` predicate; single-status cases bind `status = ?`; `actionable`
  /// emits `status IN (open, in_progress)` — the working-set lane shared by the
  /// Tasks-workspace open lane — from ``StatusName/actionableStatusSqlList``.
  public enum TaskStatusListFilter: Sendable, Equatable {
    case open
    case inProgress
    case completed
    case cancelled
    case someday
    /// The working set — `open` + `in_progress` — so a started task stays in the
    /// same lane as `open` work instead of vanishing.
    case actionable
    case all

    /// The single status literal to bind for a `status = ?` predicate, or `nil`
    /// for the multi-status (`actionable`) and no-predicate (`all`) cases, which
    /// ``TaskRepo/Read`` emits directly.
    var sqlValue: String? {
      switch self {
      case .open: return "open"
      case .inProgress: return "in_progress"
      case .completed: return "completed"
      case .cancelled: return "cancelled"
      case .someday: return "someday"
      case .actionable, .all: return nil
      }
    }
  }

  /// Defer-until (`available_from`) visibility selector for the OPEN lane of
  /// ``TaskRepo/Read/listTasks(_:query:)``. Applied only when
  /// `status == .open` and ``ListTasksQuery/today`` is set, so non-open lanes
  /// (someday / completed / cancelled / all) and callers that leave `today`
  /// nil are never silently truncated.
  ///
  /// - `all`: no `available_from` predicate — every matching row surfaces.
  /// - `visible`: exclude hidden tasks (overdue-wins) — the default OPEN list lane.
  /// - `hidden`: only tasks hidden by a future `available_from` and not overdue
  ///   — the Scheduled section.
  public enum TaskAvailabilityFilter: Sendable, Equatable {
    case all
    case visible
    case hidden
  }

  /// Sort axis for the list query. The emitted ORDER BY also carries a
  /// deterministic `id ASC` final tiebreaker for stable OFFSET pagination.
  public enum TaskListSortBy: Sendable, Equatable {
    case priorityDue
    case dueDate
    case plannedDate
    case updatedAt
    case createdAt
    case title
  }

  /// Sort direction applied to the leading axis of ``TaskListSortBy``.
  public enum SortDirection: Sendable, Equatable {
    case asc
    case desc

    var sql: String { self == .asc ? "ASC" : "DESC" }
  }

  /// Inclusive `[from, to]` range over a date or datetime column. Either
  /// bound is optional; an open-ended range omits the corresponding
  /// predicate.
  public struct TaskDateRange: Sendable, Equatable {
    public var from: String?
    public var to: String?

    public init(from: String? = nil, to: String? = nil) {
      self.from = from
      self.to = to
    }
  }

  /// Tri-state presence filter for a nullable date column.
  public enum DateFilter: Sendable, Equatable {
    /// No constraint — match rows regardless of NULL/NOT NULL status.
    case any
    /// Match rows where the column IS NOT NULL.
    case present
    /// Match rows where the column IS NULL.
    case absent
  }

  /// Adjacency-edge presence filter over `task_dependencies`. The four valid
  /// `(blocked, blocking)` combos collapsed into one closed enum so consumers
  /// route through one exhaustive switch.
  public enum BlockingFilter: Sendable, Equatable {
    /// No dependency-graph constraint.
    case any
    /// Only tasks currently blocked by an open/someday blocker.
    case blockedOnly
    /// Only tasks that currently block at least one open/someday dependent.
    case blockingOthers
    /// Both — tasks that are simultaneously blocked AND blocking.
    case blockedAndBlocking

    /// Convenience constructor mirroring the `(blocked_only,
    /// blocking_others)` boolean pair so call-sites receiving raw flags from
    /// a wire format normalize once.
    public static func fromFlags(blockedOnly: Bool, blockingOthers: Bool) -> BlockingFilter {
      switch (blockedOnly, blockingOthers) {
      case (false, false): return .any
      case (true, false): return .blockedOnly
      case (false, true): return .blockingOthers
      case (true, true): return .blockedAndBlocking
      }
    }

    /// `true` if the filter requires tasks with at least one open blocker.
    var requiresBlocked: Bool {
      self == .blockedOnly || self == .blockedAndBlocking
    }

    /// `true` if the filter requires tasks that block at least one open dependent.
    var requiresBlockingOthers: Bool {
      self == .blockingOthers || self == .blockedAndBlocking
    }
  }

  /// All filters + sort + pagination for ``TaskRepo/Read/listTasks(_:query:)``.
  /// Defaults: `status = .open`,
  /// `sortBy = .priorityDue`, `sortDirection = .asc`, `limit = 100`,
  /// `offset = 0`, all ranges/presence/blocking unfiltered, no tags, no text.
  public struct ListTasksQuery: Sendable, Equatable {
    public var listId: String?
    public var status: TaskStatusListFilter
    /// Exact `priority` to match; `nil` applies no predicate. Schema CHECK
    /// constrains stored priority to `1...3`.
    public var priority: UInt8?
    public var dueRange: TaskDateRange?
    public var plannedRange: TaskDateRange?
    /// Window over the task's calendar day — `COALESCE(planned_date,
    /// due_date)`, the same planned-first/deadline-fallback day the reference
    /// product's calendar places tasks on. `NULL` on both sides never matches,
    /// so no separate presence filter is needed.
    public var scheduledRange: TaskDateRange?
    public var completedRange: TaskDateRange?
    public var createdRange: TaskDateRange?
    public var updatedRange: TaskDateRange?
    /// Inclusive window over `available_from`. Applied on any lane like the
    /// other range filters (independent of ``availability``).
    public var availableFromRange: TaskDateRange?
    public var duePresence: DateFilter
    public var plannedPresence: DateFilter
    /// Defer-until visibility. Effective only on the OPEN lane with ``today``
    /// set; otherwise no `available_from` visibility predicate is emitted.
    public var availability: TaskAvailabilityFilter
    /// Canonical `YYYY-MM-DD` reference for ``availability``. `nil` disables the
    /// visibility predicate (the lane is never silently truncated).
    public var today: String?
    public var tags: [String]
    public var text: String?
    public var blocking: BlockingFilter
    public var sortBy: TaskListSortBy
    public var sortDirection: SortDirection
    public var limit: UInt32
    public var offset: UInt32

    public init(
      listId: String? = nil,
      status: TaskStatusListFilter = .open,
      priority: UInt8? = nil,
      dueRange: TaskDateRange? = nil,
      plannedRange: TaskDateRange? = nil,
      scheduledRange: TaskDateRange? = nil,
      completedRange: TaskDateRange? = nil,
      createdRange: TaskDateRange? = nil,
      updatedRange: TaskDateRange? = nil,
      availableFromRange: TaskDateRange? = nil,
      duePresence: DateFilter = .any,
      plannedPresence: DateFilter = .any,
      availability: TaskAvailabilityFilter = .all,
      today: String? = nil,
      tags: [String] = [],
      text: String? = nil,
      blocking: BlockingFilter = .any,
      sortBy: TaskListSortBy = .priorityDue,
      sortDirection: SortDirection = .asc,
      limit: UInt32 = 100,
      offset: UInt32 = 0
    ) {
      self.listId = listId
      self.status = status
      self.priority = priority
      self.dueRange = dueRange
      self.plannedRange = plannedRange
      self.scheduledRange = scheduledRange
      self.completedRange = completedRange
      self.createdRange = createdRange
      self.updatedRange = updatedRange
      self.availableFromRange = availableFromRange
      self.duePresence = duePresence
      self.plannedPresence = plannedPresence
      self.availability = availability
      self.today = today
      self.tags = tags
      self.text = text
      self.blocking = blocking
      self.sortBy = sortBy
      self.sortDirection = sortDirection
      self.limit = limit
      self.offset = offset
    }
  }

  /// Result of ``TaskRepo/Read/listTasks(_:query:)`` — the windowed `rows`
  /// (trimmed to `limit`) plus `totalMatching`, the full predicate count for
  /// "showing N of M" / load-more affordances.
  public struct ListTasksResult: Sendable, Equatable {
    public let rows: [TaskRow]
    public let totalMatching: Int64
  }
}

extension TaskRepo.Read {

  /// Run the dynamic-WHERE list query: COUNT(*) for `totalMatching`, then a
  /// windowed SELECT of the canonical task projection ordered per
  /// `query.sortBy`/`sortDirection` and paged via `LIMIT`/`OFFSET`.
  ///
  /// The WHERE clause is composed predicate-by-predicate; bind parameters are
  /// pushed positionally in that exact order. COUNT and SELECT share the
  /// assembled WHERE; the SELECT
  /// appends `limit`/`offset` binds at the tail. `archived_at IS NULL` is
  /// always the leading predicate so Trash rows never surface.
  public static func listTasks(
    _ db: Database, query: TaskRepo.ListTasksQuery
  ) throws -> TaskRepo.ListTasksResult {
    var whereClause = ""
    var values: [DatabaseValueConvertible?] = []
    buildWhereClause(into: &whereClause, values: &values, query: query)

    let countSql = "SELECT COUNT(*) FROM tasks " + whereClause
    let totalMatching =
      try Int64.fetchOne(db, sql: countSql, arguments: StatementArguments(values)) ?? 0

    let orderBy = listTasksOrderBy(sortBy: query.sortBy, direction: query.sortDirection)
    let tasksSql =
      "SELECT \(TaskRepo.taskColumns) FROM tasks " + whereClause
      + " ORDER BY " + orderBy + " LIMIT ? OFFSET ?"

    var taskValues = values
    taskValues.append(Int64(query.limit))
    taskValues.append(Int64(query.offset))

    let rows = try Row.fetchAll(db, sql: tasksSql, arguments: StatementArguments(taskValues))
    return TaskRepo.ListTasksResult(
      rows: try rows.map(TaskRepo.rowToTaskRow), totalMatching: totalMatching)
  }

  // MARK: - WHERE composition

  /// Whether a range upper bound should be widened to the end-of-day
  /// timestamp.
  ///
  /// `date` callers pass plain `YYYY-MM-DD` columns where bare-string equality
  /// is the right inclusive semantic. `datetime` callers (e.g. `completed_at`)
  /// store millisecond `.mmmZ` timestamps (`SyncTimestamp`), so a bare
  /// `YYYY-MM-DD` upper bound widens to `T23:59:59.999Z` — the largest value
  /// the day can hold — so byte-comparison keeps every same-day row, including
  /// the final-millisecond `.999Z` one, inside the inclusive window. A finer
  /// cap such as `.999999Z` byte-sorts *before* `.999Z` (the row's `Z` at the
  /// fourth fractional position outranks the cap's extra `9`) and would wrongly
  /// drop that boundary row. A full RFC 3339 timestamp passes through verbatim.
  enum RangeUpperWidening {
    case date
    case datetime
  }

  private static func buildWhereClause(
    into out: inout String,
    values: inout [DatabaseValueConvertible?],
    query: TaskRepo.ListTasksQuery
  ) {
    out += "WHERE tasks.archived_at IS NULL"

    switch query.status {
    case .all:
      break
    case .actionable:
      out += " AND status IN (\(StatusName.actionableStatusSqlList))"
    case .open, .inProgress, .completed, .cancelled, .someday:
      if let status = query.status.sqlValue {
        out += " AND status = ?"
        values.append(status)
      }
    }

    if let listId = query.listId {
      out += " AND list_id = ?"
      values.append(listId)
    }

    if let priority = query.priority {
      out += " AND priority = ?"
      values.append(Int64(priority))
    }

    pushRange(into: &out, values: &values, column: "due_date", range: query.dueRange, widening: .date)
    pushRange(
      into: &out, values: &values, column: "planned_date", range: query.plannedRange,
      widening: .date)
    pushRange(
      into: &out, values: &values, column: "COALESCE(planned_date, due_date)",
      range: query.scheduledRange, widening: .date)
    pushRange(
      into: &out, values: &values, column: "completed_at", range: query.completedRange,
      widening: .datetime)
    pushRange(
      into: &out, values: &values, column: "created_at", range: query.createdRange,
      widening: .datetime)
    pushRange(
      into: &out, values: &values, column: "updated_at", range: query.updatedRange,
      widening: .datetime)
    pushRange(
      into: &out, values: &values, column: "available_from", range: query.availableFromRange,
      widening: .date)

    pushDatePresence(into: &out, column: "due_date", filter: query.duePresence)
    pushDatePresence(into: &out, column: "planned_date", filter: query.plannedPresence)

    // Defer-until visibility — the `open`/`actionable` working-set lanes only,
    // and only when `today` is set, so other lanes and today-less callers are
    // never silently truncated. The `actionable` lane shares the `open` lane's
    // hide-until semantics so a hidden task doesn't leak into the working set.
    if (query.status == .open || query.status == .actionable), let today = query.today {
      switch query.availability {
      case .all:
        break
      case .visible:
        out += " AND "
          + TaskReadBuckets.availableVisibilityPredicate(
            taskAlias: "tasks", datePlaceholder: "?")
        values.append(today)
        values.append(today)
      case .hidden:
        out += " AND "
          + TaskReadBuckets.hiddenScheduledPredicate(
            taskAlias: "tasks", datePlaceholder: "?")
        values.append(today)
        values.append(today)
      }
    }

    let trimmed = query.text?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let trimmed, !trimmed.isEmpty {
      out +=
        " AND (title LIKE ? ESCAPE '\\' OR body LIKE ? ESCAPE '\\' OR ai_notes LIKE ? ESCAPE '\\')"
      let pattern = "%\(Parsing.escapeLike(trimmed))%"
      values.append(pattern)
      values.append(pattern)
      values.append(pattern)
    }

    for tag in query.tags {
      out +=
        " AND EXISTS ("
        + "SELECT 1 FROM task_tags tt "
        + "JOIN tags tg ON tg.id = tt.tag_id "
        + "WHERE tt.task_id = tasks.id AND tg.lookup_key = ?"
        + ")"
      values.append(normalizeLookupKey(tag))
    }

    let activeList = StatusName.activeStatusSqlList
    if query.blocking.requiresBlocked {
      out +=
        " AND EXISTS ("
        + "SELECT 1 FROM task_dependencies td "
        + "JOIN tasks AS blocker ON blocker.id = td.depends_on_task_id "
        + "WHERE td.task_id = tasks.id "
        + "  AND blocker.status IN (\(activeList)) "
        + "  AND blocker.archived_at IS NULL"
        + ")"
    }

    if query.blocking.requiresBlockingOthers {
      out +=
        " AND EXISTS ("
        + "SELECT 1 FROM task_dependencies td "
        + "JOIN tasks AS dependent ON dependent.id = td.task_id "
        + "WHERE td.depends_on_task_id = tasks.id "
        + "  AND dependent.status IN (\(activeList)) "
        + "  AND dependent.archived_at IS NULL"
        + ")"
    }
  }

  private static func pushDatePresence(
    into out: inout String, column: String, filter: TaskRepo.DateFilter
  ) {
    switch filter {
    case .any: break
    case .present: out += " AND \(column) IS NOT NULL"
    case .absent: out += " AND \(column) IS NULL"
    }
  }

  static func pushRange(
    into out: inout String,
    values: inout [DatabaseValueConvertible?],
    column: String,
    range: TaskRepo.TaskDateRange?,
    widening: RangeUpperWidening
  ) {
    if let from = range?.from {
      out += " AND \(column) >= ?"
      values.append(from)
    }
    if let to = range?.to {
      out += " AND \(column) <= ?"
      let widened: String
      switch widening {
      case .datetime where isBareYmd(to):
        widened = "\(to)T23:59:59.999Z"
      case .date, .datetime:
        widened = to
      }
      values.append(widened)
    }
  }

  /// `true` if `s` is exactly `YYYY-MM-DD` (10 chars: ASCII digits with
  /// dashes at indices 4 and 7).
  static func isBareYmd(_ s: String) -> Bool {
    let bytes = Array(s.utf8)
    guard bytes.count == 10 else { return false }
    for (i, b) in bytes.enumerated() {
      let ok: Bool
      switch i {
      case 4, 7: ok = b == UInt8(ascii: "-")
      default: ok = b >= UInt8(ascii: "0") && b <= UInt8(ascii: "9")
      }
      if !ok { return false }
    }
    return true
  }

  // MARK: - ORDER BY

  /// Build the ORDER BY clause for the requested sort axis + direction.
  ///
  /// Priority-bearing sorts wrap `priority_effective` in `NULLIF(_, 4)` so the
  /// sentinel `4` (NULL priority from the VIRTUAL generated column) lifts back
  /// to NULL and `NULLS LAST` sweeps unprioritized rows to the tail under both
  /// ASC and DESC. Every axis carries `id ASC` as the deterministic
  /// pagination tiebreaker.
  static func listTasksOrderBy(
    sortBy: TaskRepo.TaskListSortBy, direction: TaskRepo.SortDirection
  ) -> String {
    let dir = direction.sql
    switch sortBy {
    case .priorityDue:
      return "NULLIF(priority_effective, 4) \(dir) NULLS LAST, "
        + "due_date \(dir) NULLS LAST, id ASC"
    case .dueDate:
      return "due_date \(dir) NULLS LAST, "
        + "NULLIF(priority_effective, 4) ASC NULLS LAST, id ASC"
    case .plannedDate:
      return "planned_date \(dir) NULLS LAST, "
        + "NULLIF(priority_effective, 4) ASC NULLS LAST, id ASC"
    case .updatedAt:
      return "updated_at \(dir), id ASC"
    case .createdAt:
      return "created_at \(dir), id ASC"
    case .title:
      return "LOWER(title) \(dir), id ASC"
    }
  }
}
