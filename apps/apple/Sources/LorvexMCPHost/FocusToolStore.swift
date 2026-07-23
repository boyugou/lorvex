import MCP

extension ToolRegistry {
  func currentFocusPayload(date: String) async throws -> Value {
    try await coreBridge.loadCurrentFocus(date: date) ?? emptyCurrentFocusPayload(date: date)
  }

  func setCurrentFocusPayload(
    date: String,
    taskIDs: [String],
    briefing: Value,
    timezone: String
  ) async throws -> Value {
    try await coreBridge.setCurrentFocus(
      date: date,
      taskIDs: taskIDs,
      briefing: briefing.stringValue,
      timezone: timezone
    )
  }

  func addToCurrentFocusPayload(
    date: String,
    taskIDs: [String],
    briefing: Value,
    timezone: String
  ) async throws -> Value {
    try await coreBridge.addToCurrentFocus(
      date: date,
      taskIDs: taskIDs,
      briefing: briefing.stringValue,
      timezone: timezone
    )
  }

  func removeFromCurrentFocusPayload(date: String, taskID: String) async throws -> Value {
    try await coreBridge.removeFromCurrentFocus(date: date, taskID: taskID)
  }

  func clearCurrentFocusPayload(date: String) async throws -> Value {
    try await coreBridge.clearCurrentFocus(date: date)
  }

  private func emptyCurrentFocusPayload(date: String) -> Value {
    .object([
      "date": .string(date),
      "task_count": .int(0),
      "task_ids": .array([]),
      "tasks": .array([]),
      "current": .null,
    ])
  }
}
