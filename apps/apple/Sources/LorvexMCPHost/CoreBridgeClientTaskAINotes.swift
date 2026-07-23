import MCP
import LorvexCore

extension CoreBridgeClient {
  func setTaskAINotes(taskID: String, notes: String) async throws -> Value {
    taskValue(try await service.setTaskAINotes(taskID: taskID, notes: notes))
  }
}
