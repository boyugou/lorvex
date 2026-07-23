import MCP

extension ToolRegistry {
  func addTaskReminderPayload(taskID: String, reminderAt: String) async throws -> Value {
    try await coreBridge.addTaskReminder(taskID: taskID, reminderAt: reminderAt)
  }

  func removeTaskReminderPayload(taskID: String, reminderID: String) async throws -> Value {
    try await coreBridge.removeTaskReminder(taskID: taskID, reminderID: reminderID)
  }
}
