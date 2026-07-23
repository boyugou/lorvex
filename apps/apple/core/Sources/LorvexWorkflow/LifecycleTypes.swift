import Foundation

/// Public result types returned by lifecycle primitives and the transition
/// orchestrator. Each type carries the side-effect inventory the caller (MCP
/// host, app, sync apply) needs to enqueue sync envelopes, format API
/// responses, and drive UI invalidation. Neither the primitives nor the
/// orchestrator enqueue sync events themselves — they return the *what
/// changed* and let each surface translate that into its own outbound
/// contract.
///
/// `DeletedDependencyEdge` lives in `LifecycleDependencies.swift` (the leaf
/// primitive owns its own pre-delete snapshot type so the dependency-detach
/// helper can be consumed without pulling in the full lifecycle surface).

// MARK: - Primitive result types
// Returned by the low-level mutators (complete_task / cancel_task /
// reopen_task) and reused by the transition orchestrators.

public struct CompleteTaskResult: Sendable, Equatable {
  /// Whether the task was actually updated (false if already completed).
  public let updated: Bool
  /// IDs of reminders whose `cancelled_at` was set. Callers must enqueue
  /// sync upserts for these to propagate cancellation cross-device.
  public let cancelledReminderIds: [String]

  public init(updated: Bool, cancelledReminderIds: [String]) {
    self.updated = updated
    self.cancelledReminderIds = cancelledReminderIds
  }
}

public struct CancelTaskResult: Sendable, Equatable {
  /// Whether the task was actually updated.
  public let updated: Bool
  /// IDs of tasks whose dependency sets were affected by this cancellation.
  public let affectedDependentIds: [String]
  /// IDs of reminders whose `cancelled_at` was set. Callers must enqueue
  /// sync upserts for these to propagate cancellation cross-device.
  public let cancelledReminderIds: [String]
  /// Deleted dependency edges. Callers must enqueue
  /// `EDGE_TASK_DEPENDENCY` delete syncs for each to propagate edge removal
  /// cross-device.
  public let deletedDependencyEdges: [DeletedDependencyEdge]

  public init(
    updated: Bool,
    affectedDependentIds: [String],
    cancelledReminderIds: [String],
    deletedDependencyEdges: [DeletedDependencyEdge]
  ) {
    self.updated = updated
    self.affectedDependentIds = affectedDependentIds
    self.cancelledReminderIds = cancelledReminderIds
    self.deletedDependencyEdges = deletedDependencyEdges
  }
}

public struct ReopenTaskResult: Sendable, Equatable {
  /// Whether the task was actually updated (false if already open).
  public let updated: Bool
  /// Historical side-effect inventory. Reopen no longer revives cancelled
  /// reminders, so this is always empty.
  public let reopenedReminderIds: [String]

  public init(updated: Bool, reopenedReminderIds: [String]) {
    self.updated = updated
    self.reopenedReminderIds = reopenedReminderIds
  }
}

// MARK: - Aggregated side-effect carriers

/// Aggregated sync side effects from cancelling one or more successor tasks.
/// Callers must enqueue sync events for all fields.
public struct SuccessorCancelSideEffects: Sendable, Equatable {
  public let cancelledReminderIds: [String]
  public let deletedDependencyEdges: [DeletedDependencyEdge]
  public let affectedDependentIds: [String]
  public let rewiredFocusScheduleDates: [String]
  public let rewiredCurrentFocusDates: [String]

  public init(
    cancelledReminderIds: [String],
    deletedDependencyEdges: [DeletedDependencyEdge],
    affectedDependentIds: [String],
    rewiredFocusScheduleDates: [String] = [],
    rewiredCurrentFocusDates: [String] = []
  ) {
    self.cancelledReminderIds = cancelledReminderIds
    self.deletedDependencyEdges = deletedDependencyEdges
    self.affectedDependentIds = affectedDependentIds
    self.rewiredFocusScheduleDates = rewiredFocusScheduleDates
    self.rewiredCurrentFocusDates = rewiredCurrentFocusDates
  }

  public static let empty = SuccessorCancelSideEffects(
    cancelledReminderIds: [], deletedDependencyEdges: [], affectedDependentIds: [],
    rewiredFocusScheduleDates: [], rewiredCurrentFocusDates: [])
}

/// A tag edge copied from parent to spawned successor.
public struct CopiedTagEdge: Sendable, Equatable {
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

// MARK: - Transition orchestrator result types

/// Result of the generic `update_task(status=...)` lifecycle transition
/// orchestrator. Carries the data-layer side-effect inventory plus the
/// optional recurrence-spawn / successor-cancel inventory.
public struct LifecycleTransitionResult: Sendable, Equatable {
  /// Side effects from `status_side_effects` (reminders, deps, edges).
  public let sideEffects: StatusSideEffects.Result
  /// ID of a spawned recurrence successor (if completion triggered spawn).
  public let spawnedSuccessorId: String?
  /// Tag edges copied to the spawned successor. Callers must enqueue
  /// `EDGE_TASK_TAG` upsert syncs for each to propagate tag inheritance.
  public let spawnedSuccessorTagEdges: [CopiedTagEdge]
  /// IDs of checklist items copied to the spawned successor. Callers must
  /// enqueue `ENTITY_TASK_CHECKLIST_ITEM` upsert syncs for each.
  public let spawnedSuccessorChecklistItemIds: [String]
  /// IDs of reminders copied to the spawned successor. Callers must enqueue
  /// `ENTITY_TASK_REMINDER` upsert syncs for each.
  public let spawnedSuccessorReminderIds: [String]
  /// IDs of cancelled recurring successors (if reopen triggered cancel).
  public let cancelledSuccessorIds: [String]
  /// Aggregated sync side effects from all cancelled successors.
  public let successorCancelSideEffects: SuccessorCancelSideEffects
  /// Dates whose `focus_schedule_blocks` rows were rewired from the
  /// completed/cancelled parent to the spawned successor. Callers must
  /// enqueue an `ENTITY_FOCUS_SCHEDULE` upsert envelope per date.
  public let rewiredFocusScheduleDates: [String]
  /// Dates whose `current_focus_items` rows were rewired. Callers must
  /// enqueue an `ENTITY_CURRENT_FOCUS` upsert envelope per date.
  public let rewiredCurrentFocusDates: [String]

  public init(
    sideEffects: StatusSideEffects.Result,
    spawnedSuccessorId: String?,
    spawnedSuccessorTagEdges: [CopiedTagEdge],
    spawnedSuccessorChecklistItemIds: [String],
    spawnedSuccessorReminderIds: [String],
    cancelledSuccessorIds: [String],
    successorCancelSideEffects: SuccessorCancelSideEffects,
    rewiredFocusScheduleDates: [String],
    rewiredCurrentFocusDates: [String]
  ) {
    self.sideEffects = sideEffects
    self.spawnedSuccessorId = spawnedSuccessorId
    self.spawnedSuccessorTagEdges = spawnedSuccessorTagEdges
    self.spawnedSuccessorChecklistItemIds = spawnedSuccessorChecklistItemIds
    self.spawnedSuccessorReminderIds = spawnedSuccessorReminderIds
    self.cancelledSuccessorIds = cancelledSuccessorIds
    self.successorCancelSideEffects = successorCancelSideEffects
    self.rewiredFocusScheduleDates = rewiredFocusScheduleDates
    self.rewiredCurrentFocusDates = rewiredCurrentFocusDates
  }
}

/// Result of the dedicated reopen surface converged through the shared
/// lifecycle transition orchestrator.
public struct ReopenLifecycleTransitionResult: Sendable, Equatable {
  public let updated: Bool
  public let reopenedReminderIds: [String]
  public let transition: LifecycleTransitionResult

  public init(
    updated: Bool, reopenedReminderIds: [String], transition: LifecycleTransitionResult
  ) {
    self.updated = updated
    self.reopenedReminderIds = reopenedReminderIds
    self.transition = transition
  }
}

/// Result of the dedicated completion surface converged through the shared
/// lifecycle transition orchestrator.
public struct CompletionLifecycleTransitionResult: Sendable, Equatable {
  public let updated: Bool
  public let cancelledReminderIds: [String]
  public let spawnedSuccessorId: String?
  public let spawnedSuccessorTagEdges: [CopiedTagEdge]
  public let spawnedSuccessorChecklistItemIds: [String]
  public let spawnedSuccessorReminderIds: [String]
  public let rewiredFocusScheduleDates: [String]
  public let rewiredCurrentFocusDates: [String]

  public init(
    updated: Bool,
    cancelledReminderIds: [String],
    spawnedSuccessorId: String?,
    spawnedSuccessorTagEdges: [CopiedTagEdge],
    spawnedSuccessorChecklistItemIds: [String],
    spawnedSuccessorReminderIds: [String],
    rewiredFocusScheduleDates: [String],
    rewiredCurrentFocusDates: [String]
  ) {
    self.updated = updated
    self.cancelledReminderIds = cancelledReminderIds
    self.spawnedSuccessorId = spawnedSuccessorId
    self.spawnedSuccessorTagEdges = spawnedSuccessorTagEdges
    self.spawnedSuccessorChecklistItemIds = spawnedSuccessorChecklistItemIds
    self.spawnedSuccessorReminderIds = spawnedSuccessorReminderIds
    self.rewiredFocusScheduleDates = rewiredFocusScheduleDates
    self.rewiredCurrentFocusDates = rewiredCurrentFocusDates
  }
}

/// Result of the dedicated cancel surface converged through the shared
/// lifecycle transition orchestrator.
public struct CancelLifecycleTransitionResult: Sendable, Equatable {
  public let updated: Bool
  public let cancelledReminderIds: [String]
  public let affectedDependentIds: [String]
  public let deletedDependencyEdges: [DeletedDependencyEdge]
  /// ID of a spawned recurrence successor (set when `cancel_series=false`
  /// on a recurring task).
  public let spawnedSuccessorId: String?
  public let spawnedSuccessorTagEdges: [CopiedTagEdge]
  public let spawnedSuccessorChecklistItemIds: [String]
  public let spawnedSuccessorReminderIds: [String]
  public let rewiredFocusScheduleDates: [String]
  public let rewiredCurrentFocusDates: [String]

  public init(
    updated: Bool,
    cancelledReminderIds: [String],
    affectedDependentIds: [String],
    deletedDependencyEdges: [DeletedDependencyEdge],
    spawnedSuccessorId: String?,
    spawnedSuccessorTagEdges: [CopiedTagEdge],
    spawnedSuccessorChecklistItemIds: [String],
    spawnedSuccessorReminderIds: [String],
    rewiredFocusScheduleDates: [String],
    rewiredCurrentFocusDates: [String]
  ) {
    self.updated = updated
    self.cancelledReminderIds = cancelledReminderIds
    self.affectedDependentIds = affectedDependentIds
    self.deletedDependencyEdges = deletedDependencyEdges
    self.spawnedSuccessorId = spawnedSuccessorId
    self.spawnedSuccessorTagEdges = spawnedSuccessorTagEdges
    self.spawnedSuccessorChecklistItemIds = spawnedSuccessorChecklistItemIds
    self.spawnedSuccessorReminderIds = spawnedSuccessorReminderIds
    self.rewiredFocusScheduleDates = rewiredFocusScheduleDates
    self.rewiredCurrentFocusDates = rewiredCurrentFocusDates
  }
}
