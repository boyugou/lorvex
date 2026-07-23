import Foundation

/// Uncapped canonical task data the widget projection uses for its numeric
/// stats, decoupled from the priority-capped top-N dashboard pool
/// (``TodaySnapshot/tasks``) that still drives the rendered focus/today lists.
///
/// - ``actionableTasks``: the full open + in_progress set in canonical order,
///   with no top-N cap — so the widget's overdue / due-today / focus / per-list
///   open counts reflect the whole workload, and a started task ranked below the
///   dashboard cap is still counted.
/// - ``completedTodayTasks``: the exact, uncapped completion-day window from
///   which the projector counts today's completions by completion instant. The dashboard pool is
///   actionable-only and never contains a completed task, so without this the
///   widget's completed-today count is structurally zero.
public struct WidgetStatsSource: Sendable, Equatable {
  public var actionableTasks: [LorvexTask]
  public var completedTodayTasks: [LorvexTask]

  public init(
    actionableTasks: [LorvexTask] = [],
    completedTodayTasks: [LorvexTask] = []
  ) {
    self.actionableTasks = actionableTasks
    self.completedTodayTasks = completedTodayTasks
  }
}
