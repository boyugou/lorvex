import Foundation

/// Status transition metadata rules for tasks.
///
/// When a task's status changes, certain metadata columns must be cleared
/// or set. ``statusTransitionColumns(oldStatus:newStatus:now:)`` returns
/// the column assignments callers fold into their UPDATE statement.

/// A column assignment to apply during a status transition.
public enum ColumnAction: Equatable, Sendable {
  /// Set column to the given string value.
  case setText(column: String, value: String)
  /// Set column to NULL.
  case setNull(column: String)
  /// Set column to an integer value.
  case setInt(column: String, value: Int64)
}

/// Compute the column assignments needed for a task status transition.
///
/// Returns the metadata columns that must be changed when transitioning
/// from `oldStatus` to `newStatus`. The `now` timestamp is used for
/// `completed_at` when transitioning to completed.
///
/// The status pair is typed by the caller before entering this
/// function so an unknown wire-format status surfaces at the parse
/// boundary instead of silently falling through every guard.
public func statusTransitionColumns(
  oldStatus: TaskStatus,
  newStatus: TaskStatus,
  now: String
) -> [ColumnAction] {
  var actions: [ColumnAction] = []

  if newStatus == .completed && oldStatus != .completed {
    actions.append(.setText(column: "completed_at", value: now))
    actions.append(.setNull(column: "last_deferred_at"))
    actions.append(.setNull(column: "last_defer_reason"))
  }
  if newStatus != .completed && oldStatus == .completed {
    actions.append(.setNull(column: "completed_at"))
  }
  if newStatus == .cancelled && oldStatus != .cancelled {
    actions.append(.setNull(column: "completed_at"))
    actions.append(.setNull(column: "last_deferred_at"))
    actions.append(.setNull(column: "last_defer_reason"))
  }
  // Revival reset: returning a cancelled or someday task to `open` is a fresh
  // start. Its planned date, the time planned on it, and its deferral history
  // were decided before the task was set aside, so they are cleared.
  // Un-completing (`completed → open`) and pausing (`in_progress → open`) are
  // the reverse of a single tap, usually a mis-tap, and restore the task where
  // it was: its planned date, time, and `defer_count` stay, so it returns to
  // the same day and the same place on that day's grid.
  if newStatus == .open && (oldStatus == .cancelled || oldStatus == .someday) {
    actions.append(.setNull(column: "completed_at"))
    actions.append(.setNull(column: "planned_date"))
    actions.append(.setNull(column: "planned_start_minutes"))
    actions.append(.setNull(column: "planned_end_minutes"))
    actions.append(.setNull(column: "last_deferred_at"))
    actions.append(.setNull(column: "last_defer_reason"))
    actions.append(.setInt(column: "defer_count", value: 0))
  }

  return actions
}
