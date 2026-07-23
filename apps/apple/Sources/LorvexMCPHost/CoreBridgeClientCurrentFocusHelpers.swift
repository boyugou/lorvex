import Foundation
import LorvexCore
import MCP

extension CoreBridgeClient {
  func clearedFocusValue(date: String, removed: Bool) -> Value {
    .object([
      "date": .string(date),
      "removed": .bool(removed),
      "task_count": .int(0),
      "task_ids": .array([]),
      "plan_cleared": .bool(true),
    ])
  }
}
