import Foundation
import MCP

extension ToolRegistry {
  func getDailyScheduleResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let date = try await logicalDay(arguments["date"])
    let value = try await coreBridge.loadDayTimes(date: date)
    let count = value.objectValue?["timed_tasks"]?.arrayValue?.count ?? 0
    return fencedReadResult(
      text: count == 0 ? "No times on \(date)" : "Loaded \(count) timed task(s) on \(date)",
      value: value)
  }
}
