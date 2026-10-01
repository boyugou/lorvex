import Foundation

/// Canonical in-memory projection of an already-loaded task pool into the
/// display sections every read surface shares. Pure and synchronous: it never
/// touches the store, so the paginated reads (`taskWorkspacePage`) stay the
/// single source for large lists; this only classifies tasks already held in
/// memory.
///
/// The section rules live here, in one place, so no surface can drift:
/// - **open**: an `open` task with no planned work day. A task that carries a
///   `plannedDate` (the surface stand-in for "deferred") is excluded here and
///   surfaces in ``lorvexDeferredSection`` instead, so the two groups stay
///   mutually exclusive.
/// - **deferred**: an `open` task that carries a `plannedDate`.
/// - **scheduled**: any task with a planned-or-due action date
///   (`plannedDate ?? dueDate`), sorted by that date then title: the
///   calendar-lane projection mirroring the core's `getScheduledTasks`.
extension Collection where Element == LorvexTask {
  /// Open tasks with no planned work day; see the type-level rules.
  public var lorvexOpenSection: [LorvexTask] {
    filter { $0.status == .open && $0.plannedDate == nil }
  }

  /// Open tasks that carry a planned work day — the surface stand-in for
  /// "deferred" now that deferral pushes `planned_date` forward and leaves the
  /// status `open` (there is no `deferred` status). Mutually exclusive with
  /// ``lorvexOpenSection``.
  public var lorvexDeferredSection: [LorvexTask] {
    filter { $0.status == .open && $0.plannedDate != nil }
  }

  /// Calendar lane: tasks with a planned-first action date
  /// (`plannedDate ?? dueDate`), sorted by that date then title. A task
  /// surfaces on its planned work day, falling back to its deadline when
  /// unplanned; tasks with neither date are dropped.
  public var lorvexScheduledSection: [LorvexTask] {
    filter { ($0.plannedDate ?? $0.dueDate) != nil }
      .sorted { left, right in
        switch (left.plannedDate ?? left.dueDate, right.plannedDate ?? right.dueDate) {
        case (let leftDate?, let rightDate?):
          if leftDate == rightDate {
            return left.title.localizedStandardCompare(right.title) == .orderedAscending
          }
          return leftDate < rightDate
        case (_?, nil):
          return true
        case (nil, _?):
          return false
        case (nil, nil):
          return left.title.localizedStandardCompare(right.title) == .orderedAscending
        }
      }
  }
}

public enum LorvexTaskSections {
  /// True when `task` is unresolved and carries a deadline `logicalDay` has
  /// already passed; a completed or cancelled task is never overdue.
  ///
  /// Compares day strings in the storage frame: due dates are stored as UTC
  /// calendar days and `logicalDay` is the configured-timezone day the surface is
  /// showing, so a string compare is the same answer everywhere; no device
  /// calendar gets to disagree at a day boundary.
  public static func isOverdue(_ task: LorvexTask, logicalDay: String) -> Bool {
    guard task.status.isActive, let dueDate = task.dueDate else { return false }
    return LorvexDateFormatters.ymdUTC.string(from: dueDate) < logicalDay
  }
}
