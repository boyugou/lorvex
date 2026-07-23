import MCP

extension ToolRegistry {
  func permanentDeleteTaskResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let id: String
    switch requiredTrimmedString("id", from: arguments, message: "id is required.", toolName: "permanent_delete_task") {
    case .value(let value): id = value
    case .error(let result): return result
    }
    do {
      let value = try await permanentDeleteTaskPayload(taskID: id)
      return CallTool.Result(
        content: [
          .text(
            text: "Permanently deleted task '\(id)'.", annotations: nil, _meta: nil)
        ],
        structuredContent: Optional.some(value),
        isError: false
      )
    } catch {
      return Self.errorResult(
        code: "conflict",
        message: "Could not permanently delete task '\(id)': \(error.localizedDescription)",
        toolName: "permanent_delete_task"
      )
    }
  }
}
