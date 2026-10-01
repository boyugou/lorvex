import Foundation
import MCP

extension ToolRegistry {
  func proposeDailyScheduleResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let date = try await logicalDay(arguments["date"])
    let value = try await coreBridge.proposeDayTimes(
      date: date,
      workingHoursStart: try StrictScalarArguments.optionalString(
        arguments["working_hours_start"], field: "working_hours_start"),
      workingHoursEnd: try StrictScalarArguments.optionalString(
        arguments["working_hours_end"], field: "working_hours_end"),
      includeCalendarEvents: try StrictScalarArguments.optionalBool(
        arguments["include_calendar_events"], field: "include_calendar_events"))
    let placed = value.objectValue?["placements"]?.arrayValue?.count ?? 0
    let unplaced = value.objectValue?["unscheduled"]?.arrayValue?.count ?? 0
    let text: String
    if placed == 0, unplaced == 0 {
      text = "No open tasks on \(date) to place; put tasks on that day first"
    } else if unplaced == 0 {
      text = "Suggested times for \(placed) task(s) on \(date)"
    } else {
      text = "Suggested times for \(placed) task(s) on \(date); \(unplaced) did not fit"
    }
    return fencedReadResult(text: text, value: value)
  }
}
