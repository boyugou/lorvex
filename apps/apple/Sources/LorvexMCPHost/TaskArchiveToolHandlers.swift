import MCP

extension ToolRegistry {
  func archiveTaskResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let id: String
    switch requiredTrimmedString("id", from: arguments, message: "id is required.", toolName: "archive_task") {
    case .value(let value): id = value
    case .error(let result): return result
    }
    // A core validation (e.g. "already in the Trash") or not-found surfaces
    // through the dispatch error boundary as a clean tool error.
    let value = try await archiveTaskPayload(id: id)
    return successResult(text: "Archived task '\(id)'.", value: value)
  }

  func unarchiveTaskResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let id: String
    switch requiredTrimmedString("id", from: arguments, message: "id is required.", toolName: "unarchive_task") {
    case .value(let value): id = value
    case .error(let result): return result
    }
    let value = try await unarchiveTaskPayload(id: id)
    return successResult(text: "Restored task '\(id)' from the Trash.", value: value)
  }
}
