import MCP

extension ToolRegistry {
  func batchCreateTasksPayload(taskInputs: [Value], includeAdvice: Bool) async throws -> Value {
    try await coreBridge.batchCreateTasks(tasks: taskInputs, includeAdvice: includeAdvice)
  }

  func batchUpdateTasksPayload(updates: [Value]) async throws -> Value {
    try await coreBridge.batchUpdateTasks(updates: updates)
  }
}
