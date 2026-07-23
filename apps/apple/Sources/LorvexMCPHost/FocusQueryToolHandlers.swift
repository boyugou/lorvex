import Foundation
import MCP

extension ToolRegistry {
  func getCurrentFocusResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let date = try await logicalDay(arguments["date"])
    let value = try await currentFocusPayload(date: date)

    return fencedReadResult(text: "Loaded current focus for \(date)", value: value)
  }
}
