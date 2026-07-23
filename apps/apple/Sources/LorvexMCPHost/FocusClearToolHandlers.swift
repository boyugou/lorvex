import Foundation
import MCP

extension ToolRegistry {
  func clearCurrentFocusResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let date = try await focusDate(arguments: arguments)

    let structured = try await clearCurrentFocusPayload(date: date)
    return successResult(text: "Cleared current focus for \(date)", value: structured)
  }
}
