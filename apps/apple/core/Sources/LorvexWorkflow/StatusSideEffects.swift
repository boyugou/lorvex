import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Data-layer side effects of a task status transition that every status-
/// changing write surface must apply.
public enum StatusSideEffects {
  /// What changed as a side effect of the transition. Callers translate
  /// each list into their own sync-outbox envelopes.
  public struct Result: Sendable, Equatable {
    /// IDs of reminders that were cancelled.
    public let cancelledReminderIds: [String]
    /// IDs of tasks whose dependency sets changed (now unblocked).
    public let affectedDependentIds: [String]
    /// Pre-delete snapshots of the removed dependency edges.
    public let deletedDependencyEdges: [DeletedDependencyEdge]

    public init(
      cancelledReminderIds: [String], affectedDependentIds: [String],
      deletedDependencyEdges: [DeletedDependencyEdge]
    ) {
      self.cancelledReminderIds = cancelledReminderIds
      self.affectedDependentIds = affectedDependentIds
      self.deletedDependencyEdges = deletedDependencyEdges
    }
  }

  /// Apply the data-layer side effects of a status transition. Call this
  /// after the row's `status` column has already been updated.
  ///
  /// - **→ completed**: cancel active reminders.
  /// - **→ cancelled**: cancel active reminders + remove from dependency graph.
  /// - **→ open**: no data-layer side effects (recurrence / successor
  ///   handling is adapter-specific due to differing task-type systems).
  /// - **same status**: no-op.
  public static func applyStatusTransitionSideEffects(
    _ db: Database, taskId: TaskId,
    oldStatus: TaskStatus, newStatus: TaskStatus,
    now: String, reminderVersion: String
  ) throws -> Result {
    var cancelledReminderIds: [String] = []
    var affectedDependentIds: [String] = []
    var deletedDependencyEdges: [DeletedDependencyEdge] = []

    let becameCompleted = newStatus == .completed && oldStatus != .completed
    let becameCancelled = newStatus == .cancelled && oldStatus != .cancelled

    if becameCompleted || becameCancelled {
      cancelledReminderIds = try LifecycleReminders.cancelActiveReminders(
        db, taskId: taskId, now: now, version: reminderVersion)
    }

    if becameCancelled {
      let (affected, deleted) = try LifecycleDependencies.detachTaskDependencyEdges(
        db, taskId: taskId)
      affectedDependentIds = affected
      deletedDependencyEdges = deleted
    }

    return Result(
      cancelledReminderIds: cancelledReminderIds,
      affectedDependentIds: affectedDependentIds,
      deletedDependencyEdges: deletedDependencyEdges)
  }
}
