import MCP

extension ToolRegistry {
  func batchCompleteTasksPayload(taskIDs: [String]) async throws -> Value {
    try await coreBridge.batchCompleteTasks(taskIDs: taskIDs)
  }

  func batchReopenTasksPayload(taskIDs: [String]) async throws -> Value {
    try await coreBridge.batchReopenTasks(taskIDs: taskIDs)
  }

  func batchMoveTasksPayload(taskIDs: [String], listID: String) async throws -> Value {
    try await coreBridge.batchMoveTasks(taskIDs: taskIDs, listID: listID)
  }

  func batchCancelTasksPayload(taskIDs: [String], cancelSeries: Bool) async throws -> Value {
    try await coreBridge.batchCancelTasks(taskIDs: taskIDs, cancelSeries: cancelSeries)
  }
}

extension ToolRegistry {
  func batchCancelTasksInListPayload(
    listID: String, statuses: [String]?, cancelSeries: Bool
  ) async throws -> Value {
    try await coreBridge.batchCancelTasksInList(
      listID: listID, statuses: statuses, cancelSeries: cancelSeries)
  }
}
