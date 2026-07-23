import Foundation
import MCP

extension ToolRegistry {
  func proposeDailyScheduleResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let date = try await logicalDay(arguments["date"])
    let schedule = try await proposedFocusSchedulePayload(
      date: date,
      workingHoursStart: try StrictScalarArguments.optionalString(
        arguments["working_hours_start"], field: "working_hours_start"),
      workingHoursEnd: try StrictScalarArguments.optionalString(
        arguments["working_hours_end"], field: "working_hours_end"),
      includeCalendarEvents: try StrictScalarArguments.optionalBool(
        arguments["include_calendar_events"], field: "include_calendar_events"))
    return successResult(text: "Proposed focus schedule for \(date)", value: schedule)
  }
}
