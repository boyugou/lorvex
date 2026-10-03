import Foundation

/// Whether a task can start yet, given the tasks it waits on. The core refuses
/// to start a task while a task it waits on is unfinished
/// (`TaskLifecycleError.startBlockedByDependencies`); a surface that knows those
/// tasks offers Start only when none of them holds the task up, so the refusal
/// is never the first thing a person learns.
extension LorvexTask {
  /// Whether a task that waits on this one has to keep waiting: this task is
  /// still active (open, started, or Someday) and not in the Trash, the same
  /// test the core applies before it lets a dependent task start.
  public var holdsUpDependents: Bool {
    archivedAt == nil && status.isActive
  }

  /// Whether this task can be blocked at all: it is open or started and waits
  /// on another task. A surface asks the store which of its tasks are blocked
  /// only about these; a finished, Someday, or independent task never is.
  public var mayBeBlocked: Bool {
    status.isActionable && !dependsOn.isEmpty
  }

  /// Whether one of `dependencies` still holds this task up
  /// (``holdsUpDependents``), so it cannot start yet. Only tasks this task
  /// lists in ``dependsOn`` count. A dependency missing from `dependencies`,
  /// because it is not loaded or no longer exists, does not, matching the core,
  /// which ignores a dependency whose task is gone.
  public func isHeldUp(by dependencies: [LorvexTask]) -> Bool {
    dependencies.contains { dependsOn.contains($0.id) && $0.holdsUpDependents }
  }
}
