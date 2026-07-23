import Foundation
import LorvexCore
import MCP

extension CoreBridgeClient {
  /// Wraps a service task result in the MCP task `Value` shape. Centralizes the
  /// `LorvexTask` → `Value` mapping for the single-task mutation delegations.
  func taskValue(_ task: LorvexTask) -> Value {
    Self.taskValue(from: task)
  }
}
