import Foundation
import LorvexDomain

/// Per-task tag-edge tombstone payload accumulated by `update_task`
/// (and the eventual batch variant) and consumed by the surface
/// adapter's flush sequencer.
public struct TaskTagEdgeDelete: Sendable {
  public let taskId: String
  public let tagId: String
  public let version: String
  public let createdAt: String
  public init(taskId: String, tagId: String, version: String, createdAt: String) {
    self.taskId = taskId
    self.tagId = tagId
    self.version = version
    self.createdAt = createdAt
  }
}

/// Newly-spawned recurrence successor observed by a single-row
/// update.
public struct UpdateTaskSpawnedSuccessor: Sendable {
  public let successorId: String
  public let summary: String
  public let afterTask: JSONValue
  public init(successorId: String, summary: String, afterTask: JSONValue) {
    self.successorId = successorId
    self.summary = summary
    self.afterTask = afterTask
  }
}

/// Successor cancelled by a recurrence-config change.
public struct UpdateTaskCancelledSuccessor: Sendable {
  public let successorId: String
  public let summary: String
  public let afterTask: JSONValue
  public init(successorId: String, summary: String, afterTask: JSONValue) {
    self.successorId = successorId
    self.summary = summary
    self.afterTask = afterTask
  }
}

/// Focus rewire audit row recording which parent→successor rewire
/// produced a focus-aggregate bump on a specific date.
public struct UpdateTaskFocusRewireAudit: Sendable {
  public let parentTaskId: String
  public let successorId: String
  public let focusScheduleDates: [String]
  public let currentFocusDates: [String]
  public init(
    parentTaskId: String,
    successorId: String,
    focusScheduleDates: [String],
    currentFocusDates: [String]
  ) {
    self.parentTaskId = parentTaskId
    self.successorId = successorId
    self.focusScheduleDates = focusScheduleDates
    self.currentFocusDates = currentFocusDates
  }
}

/// Aggregated sync side-effects from one or more single-row updates.
/// Used by both `update_task` (single-element vectors) and the
/// eventual `batch_update_tasks` (multi-row aggregation). The surface
/// adapter's flush sequencer walks this in a fixed order.
public struct TaskUpdateSyncEffects: Sendable {
  public var taskUpsertIds: [String]
  public var reminderUpsertIds: [String]
  public var dependencyEdgeUpsertIds: [String]
  public var deletedDependencyEdges: [DeletedDependencyEdge]
  public var affectedDependentIds: [String]
  public var tagUpsertIds: [String]
  public var taskTagEdgeUpsertIds: [String]
  public var taskTagEdgeDeleteIds: [String]
  public var deletedTaskTagEdges: [TaskTagEdgeDelete]
  public var spawnedSuccessors: [UpdateTaskSpawnedSuccessor]
  public var cancelledSuccessors: [UpdateTaskCancelledSuccessor]
  /// Successors whose generated lineage was removed because a register newer
  /// than the recurrence-disable decision must survive as an independent task.
  /// Their outbound task upsert carries a schedule-register write, not a
  /// lifecycle write.
  public var rerootedSuccessorIds: [String]
  public var spawnedSuccessorTagEdges: [CopiedTagEdge]
  public var spawnedSuccessorChecklistItemIds: [String]
  public var spawnedSuccessorReminderIds: [String]
  public var focusRewireAudits: [UpdateTaskFocusRewireAudit]
  public var rewiredFocusScheduleDates: [String]
  public var rewiredCurrentFocusDates: [String]

  public init(
    taskUpsertIds: [String] = [],
    reminderUpsertIds: [String] = [],
    dependencyEdgeUpsertIds: [String] = [],
    deletedDependencyEdges: [DeletedDependencyEdge] = [],
    affectedDependentIds: [String] = [],
    tagUpsertIds: [String] = [],
    taskTagEdgeUpsertIds: [String] = [],
    taskTagEdgeDeleteIds: [String] = [],
    deletedTaskTagEdges: [TaskTagEdgeDelete] = [],
    spawnedSuccessors: [UpdateTaskSpawnedSuccessor] = [],
    cancelledSuccessors: [UpdateTaskCancelledSuccessor] = [],
    rerootedSuccessorIds: [String] = [],
    spawnedSuccessorTagEdges: [CopiedTagEdge] = [],
    spawnedSuccessorChecklistItemIds: [String] = [],
    spawnedSuccessorReminderIds: [String] = [],
    focusRewireAudits: [UpdateTaskFocusRewireAudit] = [],
    rewiredFocusScheduleDates: [String] = [],
    rewiredCurrentFocusDates: [String] = []
  ) {
    self.taskUpsertIds = taskUpsertIds
    self.reminderUpsertIds = reminderUpsertIds
    self.dependencyEdgeUpsertIds = dependencyEdgeUpsertIds
    self.deletedDependencyEdges = deletedDependencyEdges
    self.affectedDependentIds = affectedDependentIds
    self.tagUpsertIds = tagUpsertIds
    self.taskTagEdgeUpsertIds = taskTagEdgeUpsertIds
    self.taskTagEdgeDeleteIds = taskTagEdgeDeleteIds
    self.deletedTaskTagEdges = deletedTaskTagEdges
    self.spawnedSuccessors = spawnedSuccessors
    self.cancelledSuccessors = cancelledSuccessors
    self.rerootedSuccessorIds = rerootedSuccessorIds
    self.spawnedSuccessorTagEdges = spawnedSuccessorTagEdges
    self.spawnedSuccessorChecklistItemIds = spawnedSuccessorChecklistItemIds
    self.spawnedSuccessorReminderIds = spawnedSuccessorReminderIds
    self.focusRewireAudits = focusRewireAudits
    self.rewiredFocusScheduleDates = rewiredFocusScheduleDates
    self.rewiredCurrentFocusDates = rewiredCurrentFocusDates
  }
}

/// Namespace for the `update_task` orchestrator and its outcome shape.
/// The orchestrator entry point is
/// ``TaskUpdate/updateTask(_:hlc:input:deviceId:recurrenceHandler:)``;
/// the per-effect modules ``TaskUpdatePreparation``,
/// ``TaskUpdateRow``, ``TaskUpdateRecurrence``, ``TaskUpdateStatus``,
/// ``TaskUpdateDependencies``, and ``TaskUpdateTags`` live in sibling
/// files.
public enum TaskUpdate {
  /// Outcome shape constructed
  /// by ``updateTask(_:hlc:input:deviceId:recurrenceHandler:)``.
  public struct UpdatedTaskOutcome: Sendable {
    public let taskId: String
    public let beforeTask: JSONValue
    public let updatedTask: JSONValue
    public let payload: JSONValue
    public let summary: String
    public let syncEffects: TaskUpdateSyncEffects
    public init(
      taskId: String,
      beforeTask: JSONValue,
      updatedTask: JSONValue,
      payload: JSONValue,
      summary: String,
      syncEffects: TaskUpdateSyncEffects
    ) {
      self.taskId = taskId
      self.beforeTask = beforeTask
      self.updatedTask = updatedTask
      self.payload = payload
      self.summary = summary
      self.syncEffects = syncEffects
    }
  }
}
