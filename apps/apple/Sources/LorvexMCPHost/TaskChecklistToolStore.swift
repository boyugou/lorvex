import MCP

extension ToolRegistry {
  func addTaskChecklistItemPayload(taskID: String, text: String) async throws -> Value {
    try await coreBridge.addTaskChecklistItem(taskID: taskID, text: text)
  }

  func toggleTaskChecklistItemPayload(itemID: String, completed: Bool) async throws -> Value {
    try await coreBridge.toggleTaskChecklistItem(itemID: itemID, completed: completed)
  }

  func updateTaskChecklistItemPayload(itemID: String, text: String) async throws -> Value {
    try await coreBridge.updateTaskChecklistItem(itemID: itemID, text: text)
  }

  func removeTaskChecklistItemPayload(itemID: String) async throws -> Value {
    try await coreBridge.removeTaskChecklistItem(itemID: itemID)
  }

  func reorderTaskChecklistItemsPayload(taskID: String, itemIDs: [String]) async throws -> Value {
    try await coreBridge.reorderTaskChecklistItems(taskID: taskID, itemIDs: itemIDs)
  }
}
