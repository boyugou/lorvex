import MCP

extension ToolRegistry {
  func setTaskStatusResult(arguments: [String: Value], operation: TaskStatusOperation)
    async throws -> CallTool.Result
  {
    let toolName = operation.toolName
    let id: String
    switch requiredTrimmedString("id", from: arguments, message: "A task id is required.", toolName: toolName) {
    case .value(let value): id = value
    case .error(let result): return result
    }

    let value: Value
    do {
      value = try await setTaskStatusPayload(id: id, operation: operation)
    } catch let error as TaskMutationToolStoreError {
      return notFoundResult(error, toolName: toolName)
    }

    let title = value.objectValue?["title"]?.stringValue ?? id
    return CallTool.Result(
      content: [
        .text(text: "\(operation.verb) task: \(title)", annotations: nil, _meta: nil)
      ],
      structuredContent: Optional.some(value),
      isError: false
    )
  }
}
