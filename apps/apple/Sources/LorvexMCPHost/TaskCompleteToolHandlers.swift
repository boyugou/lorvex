import MCP

extension ToolRegistry {
  func completeTaskResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let id: String
    switch requiredTrimmedString("id", from: arguments, message: "A task id is required.", toolName: "complete_task") {
    case .value(let value): id = value
    case .error(let result): return result
    }

    let value: Value
    do {
      value = try await completeTaskPayload(id: id)
    } catch let error as TaskMutationToolStoreError {
      return notFoundResult(error, toolName: "complete_task")
    }

    let title = value.objectValue?["title"]?.stringValue ?? id
    return successResult(text: "Completed task: \(title)", value: value)
  }
}
