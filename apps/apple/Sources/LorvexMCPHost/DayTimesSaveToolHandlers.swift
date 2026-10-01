import Foundation
import LorvexDomain
import MCP

extension ToolRegistry {
  func saveDailyScheduleResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let date = arguments["date"]?.stringValue, !date.isEmpty else {
      return Self.errorResult(
        code: "validation",
        message: "A date value is required.",
        toolName: "save_daily_schedule"
      )
    }
    guard let entries = arguments["times"]?.arrayValue else {
      throw ValidationError.invalidFormat(
        field: "times", expected: "an array of {task_id, start_time, end_time} objects",
        actual: arguments["times"].map(StrictArgumentArray.describe) ?? "nothing")
    }
    let value = try await coreBridge.saveDayTimes(date: date, times: entries)
    let timed = value.objectValue?["timed_tasks"]?.arrayValue?.count ?? 0
    return successResult(
      text: entries.isEmpty
        ? "Cleared the times for \(date)" : "Saved the times for \(date); \(timed) task(s) timed",
      value: value)
  }
}
