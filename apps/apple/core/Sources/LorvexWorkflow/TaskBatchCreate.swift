import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Multi-task create:
///
/// 1. Pre-flight guards: non-empty input, batch cap of
///    ``batchCreateTasksLimit`` (500), and — when a caller-supplied
///    `ids` array is provided — equal length + uniqueness.
/// 2. Pass 1: for each (task, id) pair, run
///    ``TaskCreatePrepared/prepareTaskInsert(_:hlc:id:now:input:deviceId:)``,
///    execute the row INSERT, then insert tag + reminder children.
/// 3. Pass 2: insert the dependency edges for every row (after every
///    row exists, so intra-batch deps can resolve sibling rows).
/// 4. Pass 3: run the completion lifecycle for any row that set
///    `completed: true` — same cascade as the single-row
///    ``TaskCreate/createTask(_:hlc:input:deviceId:recurrenceHandler:)``.
///
/// Per-row error handling: fail-fast. The first row's throw aborts the
/// batch and unwinds the surrounding transaction the caller is expected
/// to own.
///
/// Sync effects: flattened ``BatchCreateSyncEffects`` envelope —
/// per-row vectors concatenated in row order.
public enum TaskBatchCreate {
  /// Hard cap on the number of tasks accepted in a single call.
  public static let batchCreateTasksLimit: Int = 500

  public static func batchCreateTasks(
    _ db: Database,
    hlc: HlcSession,
    input: BatchCreateTasksInput,
    recurrenceHandler: RecurrenceSpawnHandler = LifecycleRecurrenceSpawnHandler()
  ) throws -> BatchCreateTasksResult {
    let tasks = input.tasks
    let includeAdvice = input.includeAdvice
    if tasks.isEmpty {
      throw StoreError.validation("tasks must contain at least one item")
    }
    if tasks.count > batchCreateTasksLimit {
      throw StoreError.validation(
        "batch_create_tasks supports at most \(batchCreateTasksLimit) items, got \(tasks.count)"
      )
    }
    let ids: [String]
    if let provided = input.ids {
      if provided.count != tasks.count {
        throw StoreError.validation(
          "batch_create_tasks expected \(tasks.count) pre-generated ids, got \(provided.count)"
        )
      }
      var seen = Set<String>()
      for id in provided {
        if !seen.insert(id).inserted {
          throw StoreError.validation(
            "batch_create_tasks pre-generated ids must be unique; duplicate id '\(id)'"
          )
        }
      }
      ids = provided
    } else {
      ids = (0..<tasks.count).map { _ in EntityID.newEntityIDString() }
    }

    let now = SyncTimestampFormat.syncTimestampNow()
    var createdIds: [String] = []
    createdIds.reserveCapacity(tasks.count)
    var prepared: [PreparedTaskInsert] = []
    prepared.reserveCapacity(tasks.count)
    var completeIds: [String] = []
    var syncEffects = BatchCreateSyncEffects()

    for (task, id) in zip(tasks, ids) {
      let shouldComplete = task.completed ?? false
      let reminders = task.reminders
      let row = try TaskCreatePrepared.prepareTaskInsert(
        db, hlc: hlc, id: id, now: now, input: task)
      try row.executeInsert(db)
      let typed = TaskId(trusted: id)
      let tagEffects = try TaskCreateChildInserts.insertTaskTags(
        db, hlc: hlc, taskId: typed, tags: row.tags)
      syncEffects.tagUpsertIds.append(contentsOf: tagEffects.tagUpsertIds)
      syncEffects.taskTagEdgeUpsertIds.append(
        contentsOf: tagEffects.taskTagEdgeUpsertIds)
      let reminderIds = try TaskCreateChildInserts.insertTaskReminders(
        db, hlc: hlc, taskId: id, reminders: reminders)
      syncEffects.reminderUpsertIds.append(contentsOf: reminderIds)
      if shouldComplete { completeIds.append(id) }
      syncEffects.taskUpsertIds.append(id)
      createdIds.append(id)
      prepared.append(row)
    }

    for (idx, row) in prepared.enumerated() {
      let typed = TaskId(trusted: createdIds[idx])
      let edgeIds = try TaskCreateChildInserts.insertDependencyEdges(
        db, hlc: hlc, taskId: typed, dependsOn: row.dependsOn)
      syncEffects.dependencyEdgeUpsertIds.append(contentsOf: edgeIds)
    }

    var nextOccurrences: [JSONValue] = []
    for createdId in completeIds {
      let typed = TaskId(trusted: createdId)
      let reminderVersion = hlc.nextVersionString()
      let completion = try LifecycleTransitions.applyCompletionTransition(
        db, taskId: typed, now: now,
        reminderVersion: reminderVersion,
        handler: recurrenceHandler)
      syncEffects.cancelledReminderIds.append(
        contentsOf: completion.cancelledReminderIds)
      if let successorIdString = completion.spawnedSuccessorId {
        let successorTyped = TaskId(trusted: successorIdString)
        syncEffects.focusRewireAudits.append(
          BatchCreateFocusRewireAudit(
            parentTaskId: typed,
            successorId: successorTyped,
            focusScheduleDates: completion.rewiredFocusScheduleDates,
            currentFocusDates: completion.rewiredCurrentFocusDates))
        let successor = try TaskResponse.loadEnrichedTaskJSON(
          db, taskId: successorTyped)
        syncEffects.spawnedSuccessors.append(
          BatchCreateSpawnedSuccessor(
            successorId: successorTyped,
            summary:
              "Spawned recurrence successor from pre-completed batch create",
            afterTask: successor))
        nextOccurrences.append(successor)
      }
      syncEffects.spawnedSuccessorTagEdges.append(
        contentsOf: completion.spawnedSuccessorTagEdges)
      syncEffects.spawnedSuccessorChecklistItemIds.append(
        contentsOf: completion.spawnedSuccessorChecklistItemIds)
      syncEffects.spawnedSuccessorReminderIds.append(
        contentsOf: completion.spawnedSuccessorReminderIds)
      syncEffects.rewiredFocusScheduleDates.append(
        contentsOf: completion.rewiredFocusScheduleDates)
      syncEffects.rewiredCurrentFocusDates.append(
        contentsOf: completion.rewiredCurrentFocusDates)
    }

    let createdTasks = try TaskResponse.loadEnrichedTasksJSON(
      db, taskIds: createdIds)
    var advice: [JSONValue] = []
    if includeAdvice {
      for task in createdTasks {
        guard case .object(let fields) = task,
          case .string(let taskId) = fields["id"] ?? .null
        else {
          throw StoreError.invariant(
            "batch_create_tasks: just-inserted task is missing string `id` "
              + "for advice envelope")
        }
        let inner = try TaskCreateAdvice.buildTaskIntakeAdvice(db, task: task)
        advice.append(
          .object([
            "task_id": .string(taskId),
            "advice": .array(inner),
          ]))
      }
    }
    let titles = prepared.map { "'\($0.title)'" }.joined(separator: ", ")
    let summary =
      "Created \(createdIds.count) task\(pluralS(createdIds.count)): \(titles)"
    let payload: JSONValue = .object([
      "created_count": .int(Int64(createdTasks.count)),
      "tasks": .array(createdTasks),
      "next_occurrences": .array(nextOccurrences),
      "advice": .array(advice),
    ])

    return BatchCreateTasksResult(
      createdIds: createdIds,
      createdTasks: createdTasks,
      payload: payload,
      summary: summary,
      syncEffects: syncEffects)
  }

  private static func pluralS(_ count: Int) -> String {
    count == 1 ? "" : "s"
  }
}

/// Input envelope for ``TaskBatchCreate/batchCreateTasks``.
public struct BatchCreateTasksInput: Sendable {
  /// Optional caller-supplied ids. When `nil`, fresh UUIDs are minted.
  /// When provided, must have the same length as `tasks` and contain no
  /// duplicates.
  public var ids: [String]?
  public var tasks: [TaskCreateInput]
  public var includeAdvice: Bool

  public init(
    ids: [String]? = nil,
    tasks: [TaskCreateInput],
    includeAdvice: Bool = false
  ) {
    self.ids = ids
    self.tasks = tasks
    self.includeAdvice = includeAdvice
  }
}

/// Recurrence successor spawned by a pre-completed row in a batch
/// create.
public struct BatchCreateSpawnedSuccessor: Sendable {
  public let successorId: TaskId
  public let summary: String
  public let afterTask: JSONValue
  public init(successorId: TaskId, summary: String, afterTask: JSONValue) {
    self.successorId = successorId
    self.summary = summary
    self.afterTask = afterTask
  }
}

/// Per-row focus-rewire audit emitted by a pre-completed batch row.
public struct BatchCreateFocusRewireAudit: Sendable {
  public let parentTaskId: TaskId
  public let successorId: TaskId
  public let focusScheduleDates: [String]
  public let currentFocusDates: [String]
  public init(
    parentTaskId: TaskId,
    successorId: TaskId,
    focusScheduleDates: [String],
    currentFocusDates: [String]
  ) {
    self.parentTaskId = parentTaskId
    self.successorId = successorId
    self.focusScheduleDates = focusScheduleDates
    self.currentFocusDates = currentFocusDates
  }
}

/// Flattened sync-effect envelope aggregating every per-row effect a
/// batch create produces.
public struct BatchCreateSyncEffects: Sendable {
  public var taskUpsertIds: [String] = []
  public var reminderUpsertIds: [String] = []
  public var cancelledReminderIds: [String] = []
  public var dependencyEdgeUpsertIds: [String] = []
  public var tagUpsertIds: [String] = []
  public var taskTagEdgeUpsertIds: [String] = []
  public var affectedDependentIds: [String] = []
  public var deletedDependencyEdges: [DeletedDependencyEdge] = []
  public var spawnedSuccessors: [BatchCreateSpawnedSuccessor] = []
  public var spawnedSuccessorTagEdges: [CopiedTagEdge] = []
  public var spawnedSuccessorChecklistItemIds: [String] = []
  public var spawnedSuccessorReminderIds: [String] = []
  public var focusRewireAudits: [BatchCreateFocusRewireAudit] = []
  public var rewiredFocusScheduleDates: [String] = []
  public var rewiredCurrentFocusDates: [String] = []
  public init() {}
}

/// Result envelope of ``TaskBatchCreate/batchCreateTasks``.
public struct BatchCreateTasksResult: Sendable {
  public let createdIds: [String]
  public let createdTasks: [JSONValue]
  public let payload: JSONValue
  public let summary: String
  public let syncEffects: BatchCreateSyncEffects
}
