import Foundation

/// Outcome of ``LorvexListTagServicing/deleteTag(name:)`` — the tag that was
/// removed and the tasks it was unlinked from. Rich return per Apple Core
/// Design Rule 7 (never a bare `{success: true}`).
public struct TagDeletionOutcome: Sendable, Equatable {
  /// The deleted tag's display name.
  public let tag: String
  /// How many tasks had the tag removed (its `task_tags` links deleted).
  public let tasksUpdated: Int
  /// IDs of the tasks the tag was removed from.
  public let taskIDs: [LorvexTask.ID]

  public init(tag: String, tasksUpdated: Int, taskIDs: [LorvexTask.ID]) {
    self.tag = tag
    self.tasksUpdated = tasksUpdated
    self.taskIDs = taskIDs
  }
}

/// Outcome of ``LorvexListTagServicing/mergeTags(source:target:)`` — the source
/// tag was folded into the target and deleted. Rich return per Apple Core
/// Design Rule 7.
public struct TagMergeOutcome: Sendable, Equatable {
  /// The merged-away (now-deleted) tag's name.
  public let source: String
  /// The surviving tag the links were re-pointed onto.
  public let target: String
  /// Total tasks that carried the source tag (the re-pointed set).
  public let tasksUpdated: Int
  /// Of ``tasksUpdated``, how many gained the target tag (did not already
  /// carry it).
  public let tasksMoved: Int
  /// Of ``tasksUpdated``, how many already carried the target tag, so the
  /// duplicate source link was dropped rather than added twice.
  public let tasksDeduped: Int
  /// IDs of the tasks that carried the source tag.
  public let taskIDs: [LorvexTask.ID]

  public init(
    source: String,
    target: String,
    tasksUpdated: Int,
    tasksMoved: Int,
    tasksDeduped: Int,
    taskIDs: [LorvexTask.ID]
  ) {
    self.source = source
    self.target = target
    self.tasksUpdated = tasksUpdated
    self.tasksMoved = tasksMoved
    self.tasksDeduped = tasksDeduped
    self.taskIDs = taskIDs
  }
}
