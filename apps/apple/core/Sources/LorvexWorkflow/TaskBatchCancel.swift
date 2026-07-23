import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Multi-task cancel against a list's open / someday backlog.
///
/// The input is a **list id + status filter**, not a flat task-id list:
///
/// 1. Validate the list exists.
/// 2. Load `tasks` rows with `list_id == listId AND archived_at IS NULL
///    AND status IN (...)`, ordered `created_at ASC, id ASC`.
/// 3. Empty result short-circuits to an empty payload.
/// 4. Hard cap of ``maxInListCancel`` (500) on the candidate set.
/// 5. For each candidate task,
///    ``LifecycleTransitions/applyCancelTransition(_:taskId:now:reminderVersion:cancelSeries:seriesClearVersion:handler:)``
///    runs the cancel cascade (status mutation + reminder cancel +
///    dependency-edge cleanup + optional recurrence-successor spawn).
/// 6. `affected_dependent_ids` from each cascade are filtered to ids
///    *outside* the in-list cancellation set and deduped — the tasks
///    being cancelled in the same call must not show up as "external"
///    dependents.
///
/// Per-row error handling: fail-fast (`try` propagation aborts the
/// batch). The caller's transaction unwinds and any prior row's writes
/// roll back together.
///
/// Sync effects: flattened ``BatchCancelSyncEffects`` envelope — a
/// subset of the batch-create surface (no tag adds, no successor
/// cancels, no per-rewire audit rows).
public enum TaskBatchCancel {
  /// Hard cap on candidate set size.
  public static let maxInListCancel: Int = 500

  public static func batchCancelTasksInList(
    _ db: Database,
    hlc: HlcSession,
    input: BatchCancelInListInput,
    recurrenceHandler: RecurrenceSpawnHandler = LifecycleRecurrenceSpawnHandler()
  ) throws -> BatchCancelInListResult {
    let listId = input.listId
    let cancelSeries = input.cancelSeries
    try TaskClassification.validateTaskListExists(db, listId: listId)

    let targetStatuses =
      input.statuses ?? [.open, .inProgress, .someday]
    let targetLabels = targetStatuses.map { $0.asString }
    let beforeTasks = try loadCandidates(db, listId: listId, statuses: targetLabels)

    if beforeTasks.isEmpty {
      let payload: JSONValue = .object([
        "cancelled_count": .int(0),
        "cancelled": .array([]),
        "next_occurrences": .array([]),
        "list_id": .string(listId.rawValue),
        "statuses": .array(targetLabels.map { .string($0) }),
      ])
      return BatchCancelInListResult(
        listId: listId,
        taskIds: [],
        beforeTasks: beforeTasks,
        afterTasks: [],
        payload: payload,
        summary: nil,
        syncEffects: BatchCancelSyncEffects())
    }

    if beforeTasks.count > maxInListCancel {
      throw StoreError.validation(
        "batch_cancel_tasks_in_list supports at most \(maxInListCancel) "
          + "matching tasks per call; list '\(listId.rawValue)' has "
          + "\(beforeTasks.count) matching tasks. Narrow the `statuses` "
          + "filter or call batch_cancel_tasks with explicit ids in chunks.")
    }

    let ids: [TaskId] = try beforeTasks.map { try taskIdFromJSON($0) }
    let idStrings = ids.map { $0.asString }
    let idsSet = Set(idStrings)
    let now = SyncTimestampFormat.syncTimestampNow()
    var syncEffects = BatchCancelSyncEffects()
    syncEffects.taskUpsertIds = idStrings
    var affectedSeen = Set<String>()
    var nextOccurrences: [JSONValue] = []

    for taskId in ids {
      let beforeTitle = beforeTasks
        .first { jsonStringField($0, "id") == taskId.asString }
        .map(taskTitle) ?? "unknown"
      let reminderVersion = hlc.nextVersionString()
      let seriesClearVersion: String? = cancelSeries ? hlc.nextVersionString() : nil
      let result = try LifecycleTransitions.applyCancelTransition(
        db, taskId: taskId, now: now,
        reminderVersion: reminderVersion,
        cancelSeries: cancelSeries,
        seriesClearVersion: seriesClearVersion,
        handler: recurrenceHandler)

      syncEffects.cancelledReminderIds.append(contentsOf: result.cancelledReminderIds)
      syncEffects.deletedDependencyEdges.append(
        contentsOf: result.deletedDependencyEdges)
      for depId in result.affectedDependentIds where !idsSet.contains(depId) {
        if affectedSeen.insert(depId).inserted {
          syncEffects.affectedDependentIds.append(depId)
        }
      }
      if let successorIdString = result.spawnedSuccessorId {
        let successorTyped = TaskId(trusted: successorIdString)
        let successorTask = try TaskResponse.loadEnrichedTaskJSON(
          db, taskId: successorTyped)
        let summary =
          "Spawned recurrence successor of '\(beforeTitle)' (skip-cancel in list)"
        syncEffects.spawnedSuccessors.append(
          BatchCancelSpawnedSuccessor(
            successorId: successorTyped,
            summary: summary,
            afterTask: successorTask))
        nextOccurrences.append(successorTask)
      }
      syncEffects.spawnedSuccessorTagEdges.append(
        contentsOf: result.spawnedSuccessorTagEdges)
      syncEffects.spawnedSuccessorChecklistItemIds.append(
        contentsOf: result.spawnedSuccessorChecklistItemIds)
      syncEffects.spawnedSuccessorReminderIds.append(
        contentsOf: result.spawnedSuccessorReminderIds)
      syncEffects.rewiredFocusScheduleDates.append(
        contentsOf: result.rewiredFocusScheduleDates)
      syncEffects.rewiredCurrentFocusDates.append(
        contentsOf: result.rewiredCurrentFocusDates)
    }

    let afterTasks = try loadEnrichedTasksExisting(db, ids: ids)
    let name = try listName(db, listId: listId)
    let summary = "Cancelled \(ids.count) task\(pluralS(ids.count)) in \(name)"
    let payload: JSONValue = .object([
      "cancelled_count": .int(Int64(ids.count)),
      "cancelled": .array(afterTasks),
      "next_occurrences": .array(nextOccurrences),
      "list_id": .string(listId.rawValue),
      "statuses": .array(targetLabels.map { .string($0) }),
    ])

    return BatchCancelInListResult(
      listId: listId,
      taskIds: ids,
      beforeTasks: beforeTasks,
      afterTasks: afterTasks,
      payload: payload,
      summary: summary,
      syncEffects: syncEffects)
  }

  /// Projection from a ``BatchCancelSyncEffects`` to the cross-effect
  /// ``StatusSideEffectSyncPlan`` consumed by per-surface flush
  /// sequencers.
  public static func statusSideEffectPlan(
    _ effects: BatchCancelSyncEffects
  ) -> StatusSideEffectSyncPlan {
    StatusSideEffectSyncPlan(
      cancelledReminderIds: effects.cancelledReminderIds,
      affectedDependentIds: effects.affectedDependentIds,
      deletedDependencyEdges: effects.deletedDependencyEdges)
  }

  // MARK: - helpers

  private static func loadCandidates(
    _ db: Database, listId: ListId, statuses: [String]
  ) throws -> [JSONValue] {
    let placeholders = Sql.sqlCsvPlaceholders(statuses.count)
    let sql =
      "SELECT id FROM tasks "
      + "WHERE list_id = ? AND archived_at IS NULL AND status IN (\(placeholders)) "
      + "ORDER BY created_at ASC, id ASC"
    var args: [DatabaseValueConvertible] = [listId.rawValue]
    args.append(contentsOf: statuses)
    let ids = try String.fetchAll(
      db, sql: sql, arguments: StatementArguments(args))
    var out: [JSONValue] = []
    out.reserveCapacity(ids.count)
    for id in ids {
      // Tolerant load: if any row vanishes between the
      // SELECT and the enrich load, skip it rather than abort.
      if let task = try? TaskResponse.loadEnrichedTaskJSON(
        db, taskId: TaskId(trusted: id))
      {
        out.append(task)
      }
    }
    return out
  }

  private static func loadEnrichedTasksExisting(
    _ db: Database, ids: [TaskId]
  ) throws -> [JSONValue] {
    var out: [JSONValue] = []
    out.reserveCapacity(ids.count)
    for id in ids {
      if let task = try? TaskResponse.loadEnrichedTaskJSON(db, taskId: id) {
        out.append(task)
      }
    }
    return out
  }

  private static func listName(
    _ db: Database, listId: ListId
  ) throws -> String {
    if let name = try String.fetchOne(
      db, sql: "SELECT name FROM lists WHERE id = ?1",
      arguments: [listId.rawValue])
    {
      return name
    }
    return listId.rawValue
  }

  private static func taskIdFromJSON(_ task: JSONValue) throws -> TaskId {
    guard let s = jsonStringField(task, "id") else {
      throw StoreError.invariant("batch cancel task row missing id")
    }
    return TaskId(trusted: s)
  }

  private static func jsonStringField(_ value: JSONValue, _ key: String) -> String? {
    guard case .object(let obj) = value else { return nil }
    if case .string(let s) = obj[key] ?? .null { return s }
    return nil
  }

  private static func taskTitle(_ value: JSONValue) -> String {
    jsonStringField(value, "title") ?? "unknown"
  }

  private static func pluralS(_ count: Int) -> String {
    count == 1 ? "" : "s"
  }
}

/// Status filter for ``TaskBatchCancel/batchCancelTasksInList``.
public enum BatchCancelStatus: Sendable, Equatable {
  case open
  case inProgress
  case completed
  case cancelled
  case someday

  public var asString: String {
    switch self {
    case .open: return StatusName.open
    case .inProgress: return StatusName.inProgress
    case .completed: return StatusName.completed
    case .cancelled: return StatusName.cancelled
    case .someday: return StatusName.someday
    }
  }

  public static func parse(_ raw: String) throws -> BatchCancelStatus {
    switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case StatusName.open: return .open
    case StatusName.inProgress: return .inProgress
    case StatusName.completed: return .completed
    case StatusName.cancelled: return .cancelled
    case StatusName.someday: return .someday
    default:
      throw StoreError.validation(
        "status must be one of \(StatusName.open), \(StatusName.inProgress), "
          + "\(StatusName.completed), \(StatusName.cancelled), \(StatusName.someday)")
    }
  }
}

/// Input envelope for ``TaskBatchCancel/batchCancelTasksInList``.
public struct BatchCancelInListInput: Sendable {
  public var listId: ListId
  /// `nil` defaults to the actionable-plus-parked working set
  /// `[.open, .inProgress, .someday]` — a started task is cancelled by default
  /// alongside open and someday work.
  public var statuses: [BatchCancelStatus]?
  public var cancelSeries: Bool

  public init(
    listId: ListId,
    statuses: [BatchCancelStatus]? = nil,
    cancelSeries: Bool = false
  ) {
    self.listId = listId
    self.statuses = statuses
    self.cancelSeries = cancelSeries
  }
}

/// Recurrence successor spawned by a single skip-cancel inside a list
/// cancel.
public struct BatchCancelSpawnedSuccessor: Sendable {
  public let successorId: TaskId
  public let summary: String
  public let afterTask: JSONValue
  public init(successorId: TaskId, summary: String, afterTask: JSONValue) {
    self.successorId = successorId
    self.summary = summary
    self.afterTask = afterTask
  }
}

/// Flattened sync-effect envelope aggregating per-row cancel effects.
public struct BatchCancelSyncEffects: Sendable {
  public var taskUpsertIds: [String] = []
  public var cancelledReminderIds: [String] = []
  public var deletedDependencyEdges: [DeletedDependencyEdge] = []
  /// IDs of tasks whose dependency edges were touched by a cancel
  /// cascade and that are NOT themselves in the cancelled set.
  public var affectedDependentIds: [String] = []
  public var spawnedSuccessors: [BatchCancelSpawnedSuccessor] = []
  public var spawnedSuccessorTagEdges: [CopiedTagEdge] = []
  public var spawnedSuccessorChecklistItemIds: [String] = []
  public var spawnedSuccessorReminderIds: [String] = []
  public var rewiredFocusScheduleDates: [String] = []
  public var rewiredCurrentFocusDates: [String] = []
  public init() {}
}

/// Result envelope of ``TaskBatchCancel/batchCancelTasksInList``.
public struct BatchCancelInListResult: Sendable {
  public let listId: ListId
  public let taskIds: [TaskId]
  public let beforeTasks: [JSONValue]
  public let afterTasks: [JSONValue]
  public let payload: JSONValue
  /// `nil` when no candidates matched the filter.
  public let summary: String?
  public let syncEffects: BatchCancelSyncEffects
}
