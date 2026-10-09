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
      // A task that does not exist is a lookup miss; every other refusal (a task
      // that is not in the Trash yet) is a state conflict.
      let code = Self.errorCode(for: error)
      return Self.errorResult(
        code: code == "not_found" ? code : "conflict",
        message: "Could not permanently delete task '\(id)': \(error.localizedDescription)",
        toolName: "permanent_delete_task"
      )
    }
  }
}
