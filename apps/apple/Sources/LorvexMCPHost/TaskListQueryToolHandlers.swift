import Foundation
import LorvexCore
import MCP

extension ToolRegistry {
  func listTasksResult(arguments: [String: Value]) async throws -> CallTool.Result {
    func string(_ key: String) throws -> String? {
      try StrictScalarArguments.optionalString(arguments[key], field: key)
    }
    let limit = min(
      max(try StrictScalarArguments.int(arguments["limit"], field: "limit", default: 100), 1),
      500)
    let offset = max(
      try StrictScalarArguments.int(arguments["offset"], field: "offset", default: 0), 0)
    let text = try string("text").flatMap(\.trimmedNilIfEmpty)
    let outputOptions = try TaskValueOptions.from(arguments: arguments, defaultShape: .compact)
    let tags = try StrictArgumentArray.requiredStrings(arguments["tags"], field: "tags")
    let query = TaskListQueryRequest(
      status: try StrictScalarArguments.string(
        arguments["status"], field: "status", default: "actionable"),
      listID: try string("list_id").flatMap(\.trimmedNilIfEmpty),
      priority: try StrictScalarArguments.optionalInt(arguments["priority"], field: "priority"),
      text: text,
      tags: tags,
      dueFrom: try string("due_from").flatMap(\.trimmedNilIfEmpty),
      dueTo: try string("due_to").flatMap(\.trimmedNilIfEmpty),
      plannedFrom: try string("planned_from").flatMap(\.trimmedNilIfEmpty),
      plannedTo: try string("planned_to").flatMap(\.trimmedNilIfEmpty),
      availableFromFrom: try string("available_from_from").flatMap(\.trimmedNilIfEmpty),
      availableFromTo: try string("available_from_to").flatMap(\.trimmedNilIfEmpty),
      availability: try string("availability").flatMap(\.trimmedNilIfEmpty),
      scheduledFrom: try string("scheduled_from").flatMap(\.trimmedNilIfEmpty),
      scheduledTo: try string("scheduled_to").flatMap(\.trimmedNilIfEmpty),
      completedFrom: try string("completed_from").flatMap(\.trimmedNilIfEmpty),
      completedTo: try string("completed_to").flatMap(\.trimmedNilIfEmpty),
      createdFrom: try string("created_from").flatMap(\.trimmedNilIfEmpty),
      createdTo: try string("created_to").flatMap(\.trimmedNilIfEmpty),
      updatedFrom: try string("updated_from").flatMap(\.trimmedNilIfEmpty),
      updatedTo: try string("updated_to").flatMap(\.trimmedNilIfEmpty),
      duePresence: try string("due_presence"),
      plannedPresence: try string("planned_presence"),
      blockedOnly: try StrictScalarArguments.bool(
        arguments["blocked_only"], field: "blocked_only", default: false),
      blockingOthers: try StrictScalarArguments.bool(
        arguments["blocking_others"], field: "blocking_others", default: false),
      sortBy: try StrictScalarArguments.string(
        arguments["sort_by"], field: "sort_by", default: "priority_due"),
      sortDirection: try StrictScalarArguments.string(
        arguments["sort_direction"], field: "sort_direction", default: "asc"),
      limit: limit,
      offset: offset)

    let value = try await listTasksPayload(query: query, outputOptions: outputOptions)

    return fencedReadResult(text: "Loaded task list.", value: value)
  }

  func deferredTasksResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let limit = min(
      max(try StrictScalarArguments.int(arguments["limit"], field: "limit", default: 100), 1),
      500)
    let offset = max(
      try StrictScalarArguments.int(arguments["offset"], field: "offset", default: 0), 0)
    let listID = try StrictScalarArguments.optionalString(
      arguments["list_id"], field: "list_id")
    let outputOptions = try TaskValueOptions.from(arguments: arguments, defaultShape: .compact)

    let value = try await deferredTasksPayload(
      listID: listID, limit: limit, offset: offset, outputOptions: outputOptions)

    return fencedReadResult(text: "Loaded deferred tasks.", value: value)
  }
}
