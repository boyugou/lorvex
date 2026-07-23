import MCP

extension ToolRegistry {
  func appendToTaskBodyPayload(taskID: String, text: String) async throws -> Value {
    try await coreBridge.appendToTaskBody(taskID: taskID, text: text)
  }

  func setTaskRemindersPayload(taskID: String, reminders: [String]) async throws -> Value {
    try await coreBridge.setTaskReminders(taskID: taskID, reminders: reminders)
  }
}
