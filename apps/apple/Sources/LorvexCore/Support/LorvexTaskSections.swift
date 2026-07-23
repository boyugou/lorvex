import Foundation

/// Canonical in-memory projection of an already-loaded task pool into the
/// display sections every read surface shares (macOS Today, iOS/visionOS
/// Today). Pure and synchronous: it never touches the store, so the paginated
/// reads (`taskWorkspacePage`) stay the single source for large lists — this
/// only classifies tasks already held in memory.
///
/// The section rules live here, in one place, so no surface can drift:
/// - **open**: an `open` task with no planned work day. A task that carries a
///   `plannedDate` (the surface stand-in for "deferred") is excluded here and
///   surfaces in ``lorvexDeferredSection`` instead, so the two groups stay
///   mutually exclusive.
/// - **deferred**: an `open` task that carries a `plannedDate`.
/// - **scheduled**: any task with a planned-or-due action date
///   (`plannedDate ?? dueDate`), sorted by that date then title — the
///   calendar-lane projection mirroring the core's `getScheduledTasks`.
/// - **focus**: see ``LorvexTaskSections/focus(order:resolve:)``.
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
  /// Focus-plan tasks resolved from `taskIDs` in plan order (duplicate ids
  /// dropped), passing each id through `resolve` and discarding ids that don't
  /// resolve to a task. Order-preserving by construction: a surface must resolve
  /// the plan's id order rather than filter a task pool by focus membership,
  /// which would reorder the plan to the pool's order.
  ///
  /// `resolve` is a closure so each surface can supply its own lookup pool —
  /// macOS spans several loaded caches, the mobile snapshot resolves within the
  /// Today pool — while the ordering and de-duplication stay identical.
  public static func focus(
    order taskIDs: [LorvexTask.ID],
    resolve: (LorvexTask.ID) -> LorvexTask?
  ) -> [LorvexTask] {
    var seen = Set<LorvexTask.ID>()
    var result: [LorvexTask] = []
    for id in taskIDs where seen.insert(id).inserted {
      if let task = resolve(id) { result.append(task) }
    }
    return result
  }
}
