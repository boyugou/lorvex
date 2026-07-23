import MCP

extension ToolRegistry {
  func taskDetailResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let id: String
    switch requiredTrimmedString("id", from: arguments, message: "A task id is required.", toolName: "get_task") {
    case .value(let value): id = value
    case .error(let result): return result
    }

    let value = try await coreBridge.loadTask(id: id)

    return fencedReadResult(text: "Loaded task: \(id)", value: value)
  }
}
