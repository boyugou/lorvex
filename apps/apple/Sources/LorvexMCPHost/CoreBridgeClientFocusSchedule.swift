import Foundation
import LorvexCore
import LorvexDomain
import MCP

extension CoreBridgeClient {
  func proposeFocusSchedule(
    date: String,
    workingHoursStart: String?,
    workingHoursEnd: String?,
    includeCalendarEvents: Bool?
  ) async throws -> Value {
    Self.focusScheduleValue(
      from: try await service.proposeFocusSchedule(
        date: date, workingHoursStart: workingHoursStart, workingHoursEnd: workingHoursEnd,
        includeCalendarEvents: includeCalendarEvents))
  }

  func loadFocusSchedule(date: String) async throws -> Value? {
    guard let schedule = try await service.loadFocusScheduleForAI(date: date) else {
      return nil
    }
    return Self.focusScheduleValue(from: schedule)
  }

  func saveFocusSchedule(date: String, blocks: [Value], rationale: String?) async throws -> Value {
    let parsedBlocks: [FocusScheduleBlock] = try blocks.enumerated().map { index, block in
      let object = block.objectValue ?? [:]
      let eventSource: FocusScheduleEventSource?
      if let raw = try StrictScalarArguments.optionalString(
        object["event_source"], field: "blocks[\(index)].event_source")
      {
        guard let parsed = FocusScheduleEventSource.parse(raw) else {
          throw LorvexCoreError.validation(
            field: "event_source",
            message: "event_source must be canonical, provider, or freeform.")
        }
        eventSource = parsed
      } else {
        eventSource = nil
      }
      return FocusScheduleBlock(
        blockType: try StrictScalarArguments.string(
          object["block_type"], field: "blocks[\(index)].block_type", default: "task"),
        startTime: try StrictScalarArguments.string(
          object["start_time"], field: "blocks[\(index)].start_time", default: ""),
        endTime: try StrictScalarArguments.string(
          object["end_time"], field: "blocks[\(index)].end_time", default: ""),
        taskID: try StrictScalarArguments.optionalString(
          object["task_id"], field: "blocks[\(index)].task_id"),
        calendarEventID: try StrictScalarArguments.optionalString(
          object["event_id"], field: "blocks[\(index)].event_id"),
        eventSource: eventSource,
        title: try StrictScalarArguments.optionalString(
          object["title"], field: "blocks[\(index)].title")
      )
    }
    let receipt = try await mcpMutations.saveFocusScheduleForMcp(
      date: date, blocks: parsedBlocks, rationale: rationale)
    var value = Self.focusScheduleValue(from: receipt.schedule).objectValue ?? [:]
    // Saving a schedule also merges its task blocks into the day's current-focus
    // plan (a separate, separately-logged mutation). Surface the resulting plan
    // so the caller sees the full effect, not just the schedule (Rule 7).
    value["current_focus"] = Self.currentFocusValueWithTasks(from: receipt.currentFocus)
    return .object(value)
  }
}
