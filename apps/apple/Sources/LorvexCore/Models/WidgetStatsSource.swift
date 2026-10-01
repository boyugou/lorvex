import Foundation

/// Uncapped canonical task data the widget projection uses for its numeric
/// stats, decoupled from the day pool (``TodaySnapshot/tasks``) that drives
/// the rendered Today lists.
///
/// - ``actionableTasks``: the full open + in_progress set in canonical order —
///   so the widget's overdue / due-today / per-list open counts reflect the
///   whole workload, not only the tasks that claim today.
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
