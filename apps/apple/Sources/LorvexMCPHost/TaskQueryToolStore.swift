import LorvexCore
import MCP

extension ToolRegistry {
  func listTasksPayload(
    query: TaskListQueryRequest,
    outputOptions: TaskValueOptions
  ) async throws -> Value {
    try await coreBridge.listTasks(query: query, outputOptions: outputOptions)
  }

  func deferredTasksPayload(
    listID: String?,
    limit: Int,
    offset: Int,
    outputOptions: TaskValueOptions
  ) async throws -> Value {
    try await coreBridge.loadDeferredTasks(
      listID: listID, limit: limit, offset: offset, outputOptions: outputOptions)
  }

  func searchTasksPayload(
    query: String,
    status: String,
    limit: Int,
    offset: Int,
    outputOptions: TaskValueOptions
  ) async throws -> Value {
    try await coreBridge.searchTasks(
      query: query, status: status, limit: limit, offset: offset, outputOptions: outputOptions)
  }
}
