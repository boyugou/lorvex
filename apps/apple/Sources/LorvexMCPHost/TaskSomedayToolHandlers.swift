import MCP

extension ToolRegistry {
  /// Parks a task in the GTD Someday/Maybe bucket (`status = someday`). One
  /// tool per lifecycle transition, mirroring complete/cancel/reopen. Returns
  /// the full updated task; the user-controlled fields it echoes back match the
  /// fencing posture of the sibling lifecycle write tools.
  func setTaskSomedayResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let id: String
    switch requiredTrimmedString("id", from: arguments, message: "A task id is required.", toolName: "set_task_someday") {
    case .value(let value): id = value
    case .error(let result): return result
    }

    let value: Value
    do {
      value = try await setTaskSomedayPayload(id: id)
    } catch let error as TaskMutationToolStoreError {
      return notFoundResult(error, toolName: "set_task_someday")
    }

    let title = value.objectValue?["title"]?.stringValue ?? id
    return successResult(text: "Set someday: \(title)", value: value)
  }
}
