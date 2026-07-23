import Foundation
import MCP

/// A domain tool-store error carrying a ready-to-surface, user-facing message.
/// The per-domain stores (`ListToolStore`, `HabitToolStore`, …) throw their own
/// `*ToolStoreError` value on a lookup miss; conforming them here lets every
/// handler collapse the caught error into the shared `not_found` envelope via
/// ``ToolRegistry/notFoundResult(_:toolName:)``.
protocol ToolStoreError: Error {
  var message: String { get }
}

extension ToolRegistry {
  /// The `not_found` error envelope for a domain-store lookup miss, over any
  /// ``ToolStoreError``. The generic sibling of ``focusStoreErrorResult(_:toolName:)``;
  /// both wrap ``errorResult(code:message:toolName:)`` with `code: "not_found"`
  /// and the error's own `message`.
  func notFoundResult(_ error: some ToolStoreError, toolName: String) -> CallTool.Result {
    Self.errorResult(code: "not_found", message: error.message, toolName: toolName)
  }
}
