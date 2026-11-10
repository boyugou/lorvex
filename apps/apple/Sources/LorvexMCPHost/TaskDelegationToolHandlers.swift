import MCP

extension ToolRegistry {
  func delegateTaskResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let id: String
    switch requiredTrimmedString(
      "id", from: arguments, message: "A task id is required.", toolName: "delegate_task")
    {
    case .value(let value): id = value
    case .error(let result): return result
    }
    let request = try StrictScalarArguments.optionalString(arguments["request"], field: "request")

    let value = try await coreBridge.delegateTask(id: id, request: request)
    let title = value.objectValue?["title"]?.stringValue ?? id
    return successResult(text: "Handed to the assistant: \(title)", value: value)
  }

  func returnTaskResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let id: String
    switch requiredTrimmedString(
      "id", from: arguments, message: "A task id is required.", toolName: "return_task")
    {
    case .value(let value): id = value
    case .error(let result): return result
    }
    let result = try StrictScalarArguments.optionalString(arguments["result"], field: "result")

    let value = try await coreBridge.returnDelegatedTask(id: id, result: result)
    let title = value.objectValue?["title"]?.stringValue ?? id
    return successResult(text: "Handed back to the user: \(title)", value: value)
  }

  func clearTaskDelegationResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let id: String
    switch requiredTrimmedString(
      "id", from: arguments, message: "A task id is required.", toolName: "clear_task_delegation")
    {
    case .value(let value): id = value
    case .error(let result): return result
    }

    let value = try await coreBridge.clearTaskDelegation(id: id)
    let title = value.objectValue?["title"]?.stringValue ?? id
    return successResult(text: "Took back from the assistant: \(title)", value: value)
  }
}
