import Foundation

/// Uncapped canonical task data the widget projection uses for its numeric
/// stats, decoupled from the day pool (``TodaySnapshot/tasks``) that drives
/// the rendered Today lists.
///
/// - ``actionableTasks``: the full open + in_progress set, as the few facts the
///   counts read (``WidgetStatsTask``), so the widget's overdue / due-today /
///   per-list open counts and the app badge reflect the whole workload, not
///   only the tasks that claim today, without loading every task in full.
/// - ``completedTodayTasks``: the exact, uncapped completion-day window from
///   which the projector counts today's completions by completion instant. The dashboard pool is
///   actionable-only and never contains a completed task, so without this the
///   widget's completed-today count is structurally zero. Today's calm state
///   lists them, so they are full tasks.
public struct WidgetStatsSource: Sendable, Equatable {
  public var actionableTasks: [WidgetStatsTask]
  public var completedTodayTasks: [LorvexTask]

  public init(
    actionableTasks: [WidgetStatsTask] = [],
    completedTodayTasks: [LorvexTask] = []
  ) {
    self.actionableTasks = actionableTasks
    self.completedTodayTasks = completedTodayTasks
  }
}

/// What a glance count reads about a task: its status, its list, and the days
/// it is due and planned. ``LorvexTask`` has them all; the stats read only these
/// columns (``WidgetStatsTask``).
public protocol LorvexTaskCountFacts: Sendable {
  var id: String { get }
  var status: LorvexTask.Status { get }
  var listID: LorvexList.ID? { get }
  var dueDate: Date? { get }
  var plannedDate: Date? { get }
}

extension LorvexTask: LorvexTaskCountFacts {}

/// One actionable task as the glance counts see it (``LorvexTaskCountFacts``):
/// no title, text, tags, or checklist, so counting thousands of open tasks
/// stays small in a widget or Focus filter extension. Never rendered.
public struct WidgetStatsTask: LorvexTaskCountFacts, Sendable, Equatable {
  public let id: String
  public let status: LorvexTask.Status
  public let listID: LorvexList.ID?
  public let dueDate: Date?
  public let plannedDate: Date?

  public init(
    id: String, status: LorvexTask.Status, listID: LorvexList.ID?, dueDate: Date?,
    plannedDate: Date?
  ) {
    self.id = id
    self.status = status
    self.listID = listID
    self.dueDate = dueDate
    self.plannedDate = plannedDate
  }

  public init(_ task: LorvexTask) {
    self.init(
      id: task.id, status: task.status, listID: task.listID, dueDate: task.dueDate,
      plannedDate: task.plannedDate)
  }
}
