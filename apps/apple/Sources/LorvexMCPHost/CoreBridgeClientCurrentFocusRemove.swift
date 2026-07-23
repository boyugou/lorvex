import Foundation
import LorvexCore
import MCP

extension CoreBridgeClient {
  func removeFromCurrentFocus(date: String, taskID: String) async throws -> Value {
    let receipt = try await mcpMutations.removeFromCurrentFocusForMcp(
      date: date, taskID: taskID)
    guard receipt.current.plan != nil else {
      return clearedFocusValue(date: date, removed: receipt.removed)
    }
    var value = Self.currentFocusValueWithTasks(from: receipt.current)
    if case .object(var object) = value {
      object["removed"] = .bool(receipt.removed)
      object["plan_cleared"] = .bool(false)
      value = .object(object)
    }
    return value
  }
}
