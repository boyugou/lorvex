import Foundation
import MCP

extension ToolRegistry {
  func memoryPayloads() async throws -> [Value] {
    try await coreBridge.loadMemory()
  }

  func upsertMemoryPayload(key: String, content: String) async throws -> Value {
    try await coreBridge.upsertMemory(key: key, content: content)
  }

  func renameMemoryPayload(oldKey: String, newKey: String, content: String?) async throws -> Value {
    try await coreBridge.renameMemory(oldKey: oldKey, newKey: newKey, content: content)
  }

  func deleteMemoryPayload(key: String) async throws -> (deleted: Bool, previous: Value?) {
    try await coreBridge.deleteMemory(key: key)
  }
}
