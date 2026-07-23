import Foundation
import LorvexCore
import MCP

extension CoreBridgeClient {
  func searchTasks(
    query: String,
    status: String,
    limit: Int,
    offset: Int,
    outputOptions: TaskValueOptions = .full
  ) async throws -> Value {
    let result = try await service.searchTasks(
      query: query, status: status, limit: limit, offset: offset)
    return Self.searchTasksValue(from: result, options: outputOptions)
  }
}
