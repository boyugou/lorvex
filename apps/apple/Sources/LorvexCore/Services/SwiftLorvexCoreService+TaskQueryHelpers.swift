import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import LorvexWorkflow

extension SwiftLorvexCoreService {
  /// Enrich a list of already-fetched `TaskRow`s (tags / depends_on /
  /// checklist / lateness / reminders) and map each enriched task object onto
  /// `LorvexTask` via `SwiftLorvexTaskDeserializers.task`.
  ///
  /// Routes through `TaskResponse.loadEnrichedTasksJSON(_:rows:)`, the batch
  /// primitive: one `computeEnrichments` pass and one batched reminder scan
  /// over all rows, equivalent to enriching each row's id
  /// individually but without the per-row re-`getTask`.
  static func enrich(_ db: Database, rows: [TaskRow]) throws -> [LorvexTask] {
    let enriched = try TaskResponse.loadEnrichedTasksJSON(db, rows: rows)
    return try enriched.map(SwiftLorvexTaskDeserializers.task)
  }

  static func reminderWithTask(_ row: TaskRepo.Reminders.ReminderRow) -> TaskReminderWithTask {
    TaskReminderWithTask(
      id: row.id,
      taskID: row.taskId,
      reminderAt: row.reminderAt.asString,
      dismissedAt: row.dismissedAt?.asString,
      cancelledAt: row.cancelledAt?.asString,
      deliveryState: row.deliveryState,
      taskTitle: row.taskTitle,
      taskStatus: row.taskStatus,
      taskDueDate: row.taskDueDate?.asString,
      taskPlannedDate: row.taskPlannedDate?.asString,
      taskPriority: row.taskPriority.map(Int.init))
  }

  static func pageResult(
    tasks: [LorvexTask], totalMatching: Int, limit: Int, offset: Int
  ) -> TaskPageResult {
    let meta = pagination(
      returned: tasks.count, totalMatching: totalMatching, limit: limit, offset: offset)
    return TaskPageResult(
      tasks: tasks,
      totalMatching: totalMatching,
      returned: meta.returned,
      limit: limit,
      offset: offset,
      nextOffset: meta.nextOffset,
      truncated: meta.truncated)
  }

  /// Map the wire `status` string onto the core list filter. Supported:
  /// `all`, `open`, `in_progress`, `actionable` (the `open` + `in_progress`
  /// working set), `completed`, `cancelled`, `someday`. Anything else defaults
  /// to `open`.
  static func statusListFilter(_ status: String) -> TaskRepo.TaskStatusListFilter {
    switch status {
    case "all": return .all
    case "in_progress": return .inProgress
    case LorvexTask.Status.actionableFilter: return .actionable
    case "completed": return .completed
    case "cancelled": return .cancelled
    case "someday": return .someday
    default: return .open
    }
  }

  /// Map the wire `status` string onto a search status filter array.
  /// `all` applies no status predicate (nil); `actionable` expands to the
  /// `open` + `in_progress` working set; anything unrecognized defaults to
  /// `open`.
  static func statusSearchFilter(_ status: String) -> [String]? {
    switch status {
    case "all": return nil
    case "in_progress": return ["in_progress"]
    case LorvexTask.Status.actionableFilter: return ["open", "in_progress"]
    case "completed": return ["completed"]
    case "cancelled": return ["cancelled"]
    case "someday": return ["someday"]
    default: return ["open"]
    }
  }

  static func range(from: String?, to: String?) -> TaskRepo.TaskDateRange? {
    let normalizedFrom = from.trimmedNilIfEmpty
    let normalizedTo = to.trimmedNilIfEmpty
    guard normalizedFrom != nil || normalizedTo != nil else { return nil }
    return TaskRepo.TaskDateRange(from: normalizedFrom, to: normalizedTo)
  }

  static func dateFilter(_ value: String?) -> TaskRepo.DateFilter {
    switch value.trimmedNilIfEmpty {
    case "present": return .present
    case "absent": return .absent
    default: return .any
    }
  }

  /// Map the MCP `availability` argument to the store's defer-until filter.
  /// Unknown / nil / `all` lowers to `.all` (no `available_from` predicate).
  static func availabilityFilter(_ value: String?) -> TaskRepo.TaskAvailabilityFilter {
    switch value.trimmedNilIfEmpty?.lowercased() {
    case "visible": return .visible
    case "hidden": return .hidden
    default: return .all
    }
  }

  static func taskListSortBy(_ value: String) -> TaskRepo.TaskListSortBy {
    switch value {
    case "due_date": return .dueDate
    case "planned_date": return .plannedDate
    case "updated_at": return .updatedAt
    case "created_at": return .createdAt
    case "title": return .title
    default: return .priorityDue
    }
  }

  static func sortDirection(_ value: String) -> TaskRepo.SortDirection {
    value == "desc" ? .desc : .asc
  }
}
