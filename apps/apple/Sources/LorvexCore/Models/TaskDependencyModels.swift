import Foundation

// MARK: - Dependency Graph

/// A node in the task dependency graph, representing a single task.
public struct DependencyGraphNode: Equatable, Sendable {
  public let id: String
  public let title: String
  public let status: String
  public let priority: Int?
  public let dueDate: String?
  public let plannedDate: String?
  public let listID: String

  public init(
    id: String,
    title: String,
    status: String,
    priority: Int?,
    dueDate: String?,
    plannedDate: String?,
    listID: String
  ) {
    self.id = id
    self.title = title
    self.status = status
    self.priority = priority
    self.dueDate = dueDate
    self.plannedDate = plannedDate
    self.listID = listID
  }
}

/// A directed dependency edge: `from` depends on `to`.
public struct DependencyGraphEdge: Equatable, Sendable {
  /// The task that has the dependency.
  public let from: String
  /// The task that must be completed first.
  public let to: String

  public init(from: String, to: String) {
    self.from = from
    self.to = to
  }
}

/// The computed dependency graph for a set of tasks.
///
/// - `nodes`: all tasks included in the graph
/// - `edges`: directed dependency relationships (from depends on to)
/// - `roots`: task IDs with no dependencies of their own
/// - `blocked`: task IDs whose dependencies include unmet open/someday tasks
/// - `leafBlockers`: task IDs that block others but are not themselves blocked
/// - `truncated`: true when nodes or edges were capped by server-side limits
public struct DependencyGraph: Equatable, Sendable {
  public let nodes: [DependencyGraphNode]
  public let edges: [DependencyGraphEdge]
  public let roots: [String]
  public let blocked: [String]
  public let leafBlockers: [String]
  public let truncated: Bool

  public init(
    nodes: [DependencyGraphNode],
    edges: [DependencyGraphEdge],
    roots: [String],
    blocked: [String],
    leafBlockers: [String],
    truncated: Bool
  ) {
    self.nodes = nodes
    self.edges = edges
    self.roots = roots
    self.blocked = blocked
    self.leafBlockers = leafBlockers
    self.truncated = truncated
  }
}

// MARK: - Task Reminder With Task

/// A task reminder paired with key fields from its parent task.
public struct TaskReminderWithTask: Identifiable, Equatable, Sendable {
  public let id: String
  public let taskID: String
  public let reminderAt: String
  public let dismissedAt: String?
  public let cancelledAt: String?
  public let deliveryState: String
  public let taskTitle: String
  public let taskStatus: String
  public let taskDueDate: String?
  public let taskPlannedDate: String?
  public let taskPriority: Int?

  public init(
    id: String,
    taskID: String,
    reminderAt: String,
    dismissedAt: String?,
    cancelledAt: String?,
    deliveryState: String,
    taskTitle: String,
    taskStatus: String,
    taskDueDate: String?,
    taskPlannedDate: String? = nil,
    taskPriority: Int?
  ) {
    self.id = id
    self.taskID = taskID
    self.reminderAt = reminderAt
    self.dismissedAt = dismissedAt
    self.cancelledAt = cancelledAt
    self.deliveryState = deliveryState
    self.taskTitle = taskTitle
    self.taskStatus = taskStatus
    self.taskDueDate = taskDueDate
    self.taskPlannedDate = taskPlannedDate
    self.taskPriority = taskPriority
  }
}
