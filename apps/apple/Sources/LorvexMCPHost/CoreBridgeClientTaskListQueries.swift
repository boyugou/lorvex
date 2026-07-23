import Foundation
import LorvexCore
import MCP

extension CoreBridgeClient {
  func listTasks(
    query: TaskListQueryRequest,
    outputOptions: TaskValueOptions
  ) async throws -> Value {
    let page = try await service.listTasks(query: query)
    return Self.pagedTasksValue(from: page, options: outputOptions)
  }

  func loadDeferredTasks(
    listID: String?, limit: Int, offset: Int, outputOptions: TaskValueOptions = .full
  ) async throws -> Value {
    let normalizedListID = (listID?.isEmpty ?? true) ? nil : listID
    let page = try await service.getDeferredTasks(
      listID: normalizedListID, limit: limit, offset: offset)
    return Self.pagedTasksValue(from: page, options: outputOptions)
  }
}
