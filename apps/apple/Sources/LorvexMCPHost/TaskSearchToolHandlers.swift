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
    let limit = try PagingArguments.limit(arguments, default: 50, maximum: 500)
    let offset = try PagingArguments.offset(arguments)
    let outputOptions = try TaskValueOptions.from(arguments: arguments, defaultShape: .compact)

    let value = try await searchTasksPayload(
      query: query, status: status, limit: limit, offset: offset, outputOptions: outputOptions)

    return fencedReadResult(text: "Searched tasks for \(query).", value: value)
  }

}
