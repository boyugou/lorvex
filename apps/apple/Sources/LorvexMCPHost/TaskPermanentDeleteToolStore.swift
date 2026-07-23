import MCP

extension ToolRegistry {
  func permanentDeleteTaskPayload(taskID: String) async throws -> Value {
    try await coreBridge.permanentDeleteTask(taskID: taskID)
  }
}
