import Foundation
import LorvexCore
import MCP

// MARK: - Dependency Graph + Upcoming Task Queries

extension CoreBridgeClient {
  func getDependencyGraph(
    taskID: String?,
    listID: String?,
    includeInactive: Bool
  ) async throws -> Value {
    let graph = try await service.getDependencyGraph(
      rootTaskID: (taskID?.isEmpty ?? true) ? nil : taskID,
      listID: (listID?.isEmpty ?? true) ? nil : listID,
      includeInactive: includeInactive
    )
    return Self.dependencyGraphValue(from: graph)
  }

  func getUpcomingTasks(
    days: Int,
    limit: Int,
    offset: Int,
    outputOptions: TaskValueOptions = .full
  ) async throws -> Value {
    let page = try await service.getUpcomingTaskPage(daysAhead: days, limit: limit, offset: offset)
    let logicalDay = try await service.getSessionContext().date
    return Self.upcomingTasksValue(
      from: page, logicalDay: logicalDay, days: days, outputOptions: outputOptions)
  }

  func getDueTaskReminders(asOf: String?, limit: Int, offset: Int) async throws -> Value {
    // Over-fetch one past the page so the envelope reports a real
    // `truncated`/`next_offset` and can page by offset.
    let rows = try await service.getDueTaskReminders(
      asOf: (asOf?.isEmpty ?? true) ? nil : asOf, limit: offset + limit + 1)
    return Self.reminderListValue(from: rows, limit: limit, offset: offset)
  }

  func getUpcomingTaskReminders(hours: Int, limit: Int, offset: Int) async throws -> Value {
    let rows = try await service.getUpcomingTaskReminders(
      hoursAhead: hours, limit: offset + limit + 1)
    return Self.reminderListValue(from: rows, limit: limit, offset: offset)
  }

  // MARK: - Value adapters

  static func dependencyGraphValue(from graph: DependencyGraph) -> Value {
    let nodes = graph.nodes.map(nodeValue(from:))
    let edges = graph.edges.map(edgeValue(from:))
    return .object([
      "node_count": .int(nodes.count),
      "edge_count": .int(edges.count),
      "nodes": .array(nodes),
      "edges": .array(edges),
      "roots": .array(graph.roots.map(Value.string)),
      "blocked": .array(graph.blocked.map(Value.string)),
      "leaf_blockers": .array(graph.leafBlockers.map(Value.string)),
      "truncated": .bool(graph.truncated),
    ])
  }

  private static func nodeValue(from node: DependencyGraphNode) -> Value {
    slimTaskSummaryValue(
      id: node.id, title: node.title, status: node.status,
      listID: node.listID, priority: node.priority, dueDate: node.dueDate,
      plannedDate: node.plannedDate)
  }

  private static func edgeValue(from edge: DependencyGraphEdge) -> Value {
    .object([
      "from": .string(edge.from),
      "to": .string(edge.to),
    ])
  }

  static func upcomingTasksValue(
    from page: TaskPageResult,
    logicalDay: String,
    days: Int,
    outputOptions: TaskValueOptions = .full
  )
    -> Value
  {
    // `tasks` is the flat page every other task-list read returns; `by_date`
    // groups those same rows for the week view. The envelope's paging fields
    // describe the flat array.
    var byDate: [String: [Value]] = [:]
    var flat: [Value] = []
    for task in page.tasks {
      let value = taskValue(from: task, options: outputOptions)
      let key = (task.plannedDate ?? task.dueDate).map { plannedDateFormatter.string(from: $0) } ?? ""
      byDate[key, default: []].append(value)
      flat.append(value)
    }
    let window = upcomingTaskWindow(logicalDay: logicalDay, days: days)
    return MCPPagination.object(
      domain: [
        "from": .string(window.from),
        "to": .string(window.to),
        "days_requested": .int(days),
        "tasks": .array(flat),
        "by_date": .object(byDate.mapValues(Value.array)),
      ],
      totalMatching: page.totalMatching, returned: page.returned, limit: page.limit,
      offset: page.offset, nextOffset: page.nextOffset, truncated: page.truncated)
  }

  private static func upcomingTaskWindow(
    logicalDay: String,
    days: Int
  ) -> (from: String, to: String) {
    let end = LorvexDateFormatters.ymdUTCAddingDays(logicalDay, days: max(days, 0))
      ?? logicalDay
    return (
      logicalDay,
      end
    )
  }

  /// Render a reminder page inside the shared pagination envelope. The caller
  /// over-fetches `offset + limit + 1` rows; after dropping `offset`, if more
  /// than `limit` remain the page is trimmed, `truncated` is true with a real
  /// `next_offset`, and `total_matching` is null (unknown, more exist) rather
  /// than a fabricated total equal to the page size.
  static func reminderListValue(
    from rows: [TaskReminderWithTask], limit: Int, offset: Int
  ) -> Value {
    let afterOffset = Array(rows.dropFirst(offset))
    let truncated = afterOffset.count > limit
    let page = Array(afterOffset.prefix(limit))
    return MCPPagination.object(
      domain: ["reminders": .array(page.map(reminderWithTaskValue(from:)))],
      totalMatching: truncated ? nil : offset + page.count, returned: page.count, limit: limit,
      offset: offset, nextOffset: truncated ? offset + page.count : nil, truncated: truncated)
  }

  /// A reminder row plus its parent-task context. The task context is the shared
  /// slim task-summary (`task`), not `task_`-prefixed flat fields, so a client
  /// reuses the same summary parser it uses for overview/dependency/weekly reads.
  /// The reminder model carries no list id, so the summary's `list_id` is null.
  private static func reminderWithTaskValue(from row: TaskReminderWithTask) -> Value {
    .object([
      "id": .string(row.id),
      "task_id": .string(row.taskID),
      "reminder_at": .string(row.reminderAt),
      "dismissed_at": row.dismissedAt.map(Value.string) ?? .null,
      "cancelled_at": row.cancelledAt.map(Value.string) ?? .null,
      "delivery_state": .string(row.deliveryState),
      "task": slimTaskSummaryValue(
        id: row.taskID, title: row.taskTitle, status: row.taskStatus,
        listID: nil, priority: row.taskPriority, dueDate: row.taskDueDate,
        plannedDate: row.taskPlannedDate),
    ])
  }
}
