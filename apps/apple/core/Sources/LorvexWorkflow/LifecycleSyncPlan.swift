import Foundation

/// Shared sync fan-out inventory for lifecycle transitions.
///
/// The workflow layer owns the semantic side-effect result. Runtime surfaces
/// (MCP host, app, sync apply) still own their outbox writer, undo hold,
/// changelog, and response contracts, but they should not rediscover which
/// related entities a lifecycle transition touched. `LifecycleSyncPlan` is
/// the narrow bridge: each surface adapter consumes the same buckets so
/// per-surface code stays identical at the fan-out boundary.
///
/// Deliberately out of scope: direct checklist-item / reminder CRUD and
/// permanent-delete cascades. Those paths own their primary entity mutation
/// at an entity-specific boundary, not as a lifecycle status transition
/// result.

/// Reminder/dependency side effects produced by a status transition.
public struct StatusSideEffectSyncPlan: Sendable, Equatable {
  public let cancelledReminderIds: [String]
  public let affectedDependentIds: [String]
  public let deletedDependencyEdges: [DeletedDependencyEdge]

  public init(
    cancelledReminderIds: [String] = [],
    affectedDependentIds: [String] = [],
    deletedDependencyEdges: [DeletedDependencyEdge] = []
  ) {
    self.cancelledReminderIds = cancelledReminderIds
    self.affectedDependentIds = affectedDependentIds
    self.deletedDependencyEdges = deletedDependencyEdges
  }

  public static let empty = StatusSideEffectSyncPlan()

  /// Projection from the data-layer side-effect result returned by
  /// `StatusSideEffects.applyStatusTransitionSideEffects`.
  public static func from(statusEffects: StatusSideEffects.Result) -> StatusSideEffectSyncPlan {
    StatusSideEffectSyncPlan(
      cancelledReminderIds: statusEffects.cancelledReminderIds,
      affectedDependentIds: statusEffects.affectedDependentIds,
      deletedDependencyEdges: statusEffects.deletedDependencyEdges)
  }

  public static func from(
    successorCancel: SuccessorCancelSideEffects
  ) -> StatusSideEffectSyncPlan {
    StatusSideEffectSyncPlan(
      cancelledReminderIds: successorCancel.cancelledReminderIds,
      affectedDependentIds: successorCancel.affectedDependentIds,
      deletedDependencyEdges: successorCancel.deletedDependencyEdges)
  }

  public static func from(cancel: CancelLifecycleTransitionResult) -> StatusSideEffectSyncPlan {
    StatusSideEffectSyncPlan(
      cancelledReminderIds: cancel.cancelledReminderIds,
      affectedDependentIds: cancel.affectedDependentIds,
      deletedDependencyEdges: cancel.deletedDependencyEdges)
  }
}

/// Complete related-entity sync inventory for a lifecycle transition. Every
/// per-surface adapter (MCP host, app, sync apply) consumes this in the same
/// shape, so the fan-out enqueue logic stays identical across surfaces.
public struct LifecycleSyncPlan: Sendable, Equatable {
  public let status: StatusSideEffectSyncPlan
  public let reopenedReminderIds: [String]
  public let spawnedSuccessorId: String?
  public let spawnedSuccessorTagEdges: [CopiedTagEdge]
  public let spawnedSuccessorChecklistItemIds: [String]
  public let spawnedSuccessorReminderIds: [String]
  public let cancelledSuccessorIds: [String]
  public let successorCancel: StatusSideEffectSyncPlan
  public let rewiredFocusScheduleDates: [String]
  public let rewiredCurrentFocusDates: [String]

  public init(
    status: StatusSideEffectSyncPlan = .empty,
    reopenedReminderIds: [String] = [],
    spawnedSuccessorId: String? = nil,
    spawnedSuccessorTagEdges: [CopiedTagEdge] = [],
    spawnedSuccessorChecklistItemIds: [String] = [],
    spawnedSuccessorReminderIds: [String] = [],
    cancelledSuccessorIds: [String] = [],
    successorCancel: StatusSideEffectSyncPlan = .empty,
    rewiredFocusScheduleDates: [String] = [],
    rewiredCurrentFocusDates: [String] = []
  ) {
    self.status = status
    self.reopenedReminderIds = reopenedReminderIds
    self.spawnedSuccessorId = spawnedSuccessorId
    self.spawnedSuccessorTagEdges = spawnedSuccessorTagEdges
    self.spawnedSuccessorChecklistItemIds = spawnedSuccessorChecklistItemIds
    self.spawnedSuccessorReminderIds = spawnedSuccessorReminderIds
    self.cancelledSuccessorIds = cancelledSuccessorIds
    self.successorCancel = successorCancel
    self.rewiredFocusScheduleDates = rewiredFocusScheduleDates
    self.rewiredCurrentFocusDates = rewiredCurrentFocusDates
  }

  public static let empty = LifecycleSyncPlan()

  public static func from(
    completion result: CompletionLifecycleTransitionResult
  ) -> LifecycleSyncPlan {
    LifecycleSyncPlan(
      status: StatusSideEffectSyncPlan(
        cancelledReminderIds: result.cancelledReminderIds,
        affectedDependentIds: [],
        deletedDependencyEdges: []),
      spawnedSuccessorId: result.spawnedSuccessorId,
      spawnedSuccessorTagEdges: result.spawnedSuccessorTagEdges,
      spawnedSuccessorChecklistItemIds: result.spawnedSuccessorChecklistItemIds,
      spawnedSuccessorReminderIds: result.spawnedSuccessorReminderIds,
      rewiredFocusScheduleDates: result.rewiredFocusScheduleDates,
      rewiredCurrentFocusDates: result.rewiredCurrentFocusDates)
  }

  public static func from(cancel result: CancelLifecycleTransitionResult) -> LifecycleSyncPlan {
    LifecycleSyncPlan(
      status: .from(cancel: result),
      spawnedSuccessorId: result.spawnedSuccessorId,
      spawnedSuccessorTagEdges: result.spawnedSuccessorTagEdges,
      spawnedSuccessorChecklistItemIds: result.spawnedSuccessorChecklistItemIds,
      spawnedSuccessorReminderIds: result.spawnedSuccessorReminderIds,
      rewiredFocusScheduleDates: result.rewiredFocusScheduleDates,
      rewiredCurrentFocusDates: result.rewiredCurrentFocusDates)
  }

  public static func from(transition result: LifecycleTransitionResult) -> LifecycleSyncPlan {
    LifecycleSyncPlan(
      status: .from(statusEffects: result.sideEffects),
      reopenedReminderIds: [],
      spawnedSuccessorId: result.spawnedSuccessorId,
      spawnedSuccessorTagEdges: result.spawnedSuccessorTagEdges,
      spawnedSuccessorChecklistItemIds: result.spawnedSuccessorChecklistItemIds,
      spawnedSuccessorReminderIds: result.spawnedSuccessorReminderIds,
      cancelledSuccessorIds: result.cancelledSuccessorIds,
      successorCancel: .from(successorCancel: result.successorCancelSideEffects),
      rewiredFocusScheduleDates: result.rewiredFocusScheduleDates,
      rewiredCurrentFocusDates: result.rewiredCurrentFocusDates)
  }

  public static func from(reopen result: ReopenLifecycleTransitionResult) -> LifecycleSyncPlan {
    let base = LifecycleSyncPlan.from(transition: result.transition)
    return LifecycleSyncPlan(
      status: base.status,
      reopenedReminderIds: result.reopenedReminderIds,
      spawnedSuccessorId: base.spawnedSuccessorId,
      spawnedSuccessorTagEdges: base.spawnedSuccessorTagEdges,
      spawnedSuccessorChecklistItemIds: base.spawnedSuccessorChecklistItemIds,
      spawnedSuccessorReminderIds: base.spawnedSuccessorReminderIds,
      cancelledSuccessorIds: base.cancelledSuccessorIds,
      successorCancel: base.successorCancel,
      rewiredFocusScheduleDates: base.rewiredFocusScheduleDates,
      rewiredCurrentFocusDates: base.rewiredCurrentFocusDates)
  }
}
