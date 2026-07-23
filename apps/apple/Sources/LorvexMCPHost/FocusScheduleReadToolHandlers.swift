import Foundation
import MCP

extension ToolRegistry {
  func getSavedFocusScheduleResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let date = try await logicalDay(arguments["date"])
    let schedule = try await savedFocusSchedulePayload(date: date)
    return fencedReadResult(text: "Loaded focus schedule for \(date)", value: schedule)
  }
}
