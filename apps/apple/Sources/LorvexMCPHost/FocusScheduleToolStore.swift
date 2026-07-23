import MCP

extension ToolRegistry {
  func savedFocusSchedulePayload(date: String) async throws -> Value {
    // The bridge returns nil when no schedule is saved; surface a top-level
    // JSON null, matching the tool's documented "or null if none saved".
    try await coreBridge.loadFocusSchedule(date: date) ?? .null
  }

  func proposedFocusSchedulePayload(
    date: String,
    workingHoursStart: String?,
    workingHoursEnd: String?,
    includeCalendarEvents: Bool?
  ) async throws -> Value {
    try await coreBridge.proposeFocusSchedule(
      date: date, workingHoursStart: workingHoursStart, workingHoursEnd: workingHoursEnd,
      includeCalendarEvents: includeCalendarEvents)
  }

  func saveFocusSchedulePayload(
    date: String,
    blocks: [Value],
    rationale: String?
  ) async throws -> Value {
    try await coreBridge.saveFocusSchedule(date: date, blocks: blocks, rationale: rationale)
  }
}
