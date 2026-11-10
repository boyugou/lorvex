import LorvexCore
import MCP

extension CoreBridgeClient {
  func delegateTask(id: String, request: String?) async throws -> Value {
    taskValue(try await service.delegateTask(id: id, request: request))
  }

  func returnDelegatedTask(id: String, result: String?) async throws -> Value {
    taskValue(try await service.returnDelegatedTask(id: id, result: result))
  }

  func clearTaskDelegation(id: String) async throws -> Value {
    taskValue(try await service.clearTaskDelegation(id: id))
  }
}
