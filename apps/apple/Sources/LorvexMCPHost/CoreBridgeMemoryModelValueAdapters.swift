import Foundation
import LorvexCore
import MCP

/// Maps the `LorvexCore` memory model types onto the MCP `Value` JSON shapes the
/// memory tool handlers return.
extension CoreBridgeClient {
  static func memoryValue(from entry: MemoryEntry) -> Value {
    .object([
      "key": .string(entry.key),
      "content": .string(entry.content),
      "updated_at": .string(entry.updatedAt),
    ])
  }
}
