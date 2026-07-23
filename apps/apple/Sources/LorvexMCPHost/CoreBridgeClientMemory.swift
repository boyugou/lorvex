import Foundation
import LorvexCore
import MCP

extension CoreBridgeClient {
  func loadMemory() async throws -> [Value] {
    try await service.loadMemory().entries.map(Self.memoryValue(from:))
  }

  func upsertMemory(key: String, content: String) async throws -> Value {
    Self.memoryValue(from: try await service.upsertMemory(key: key, content: content))
  }

  func renameMemory(oldKey: String, newKey: String, content: String?) async throws -> Value {
    Self.memoryValue(
      from: try await service.renameMemory(oldKey: oldKey, newKey: newKey, content: content))
  }

  func deleteMemory(key: String) async throws -> (deleted: Bool, previous: Value?) {
    let receipt = try await mcpMutations.deleteMemoryForMcp(key: key)
    return (receipt.deleted, receipt.previous.map(Self.memoryValue(from:)))
  }
}
