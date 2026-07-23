import Foundation
import MCP

extension ToolRegistry {
  func searchTasksResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard
      let query = arguments["query"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    else {
      return Self.errorResult(
        code: "validation", message: "A query value is required.", toolName: "search_tasks")
    }

    let status = try StrictScalarArguments.string(
      arguments["status"], field: "status", default: "all")
    let limit = min(
      max(try StrictScalarArguments.int(arguments["limit"], field: "limit", default: 50), 1),
      500)
    let offset = max(
      try StrictScalarArguments.int(arguments["offset"], field: "offset", default: 0), 0)
    let outputOptions = try TaskValueOptions.from(arguments: arguments, defaultShape: .compact)

    let value = try await searchTasksPayload(
      query: query, status: status, limit: limit, offset: offset, outputOptions: outputOptions)

    return fencedReadResult(text: "Searched tasks for \(query).", value: value)
  }

}
