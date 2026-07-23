import MCP

extension ToolRegistry {
  func deferTaskResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let id: String
    switch requiredTrimmedString("id", from: arguments, message: "A task id is required.", toolName: "defer_task") {
    case .value(let value): id = value
    case .error(let result): return result
    }
    guard let untilDate = arguments["until_date"]?.stringValue, !untilDate.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "An until_date value is required.", toolName: "defer_task")
    }

    let value: Value
    do {
      value = try await deferTaskPayload(
        id: id, untilDate: untilDate,
        structuredReason: try StrictScalarArguments.optionalString(
          arguments["structured_reason"], field: "structured_reason"),
        reason: try StrictScalarArguments.optionalString(arguments["reason"], field: "reason"))
    } catch let error as TaskMutationToolStoreError {
      return notFoundResult(error, toolName: "defer_task")
    }

    let title = value.objectValue?["title"]?.stringValue ?? id
    return successResult(text: "Deferred task: \(title)", value: value)
  }
}
