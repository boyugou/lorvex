import MCP

extension ToolRegistry {
  /// Move a task to the Trash, stamping `archived_at`.
  func archiveTaskPayload(id: String) async throws -> Value {
    try await coreBridge.archiveTask(id: id)
  }

  func unarchiveTaskPayload(id: String) async throws -> Value {
    try await coreBridge.unarchiveTask(id: id)
  }
}
