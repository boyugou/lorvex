import Foundation
import MCP

extension ToolRegistry {
  func setDailyBriefingResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let date = try await logicalDay(arguments["date"])
    // The key is required: an omitted briefing would otherwise read as an empty one and clear
    // the day's briefing. An empty string is the explicit way to clear it.
    guard let briefing = try StrictScalarArguments.optionalString(
      arguments["briefing"], field: "briefing")
    else {
      return Self.errorResult(
        code: "validation",
        message: "briefing is required. Pass an empty string to clear the day's briefing.",
        toolName: "set_daily_briefing")
    }
    let value = try await coreBridge.setDailyBriefing(date: date, briefing: briefing)
    let changed = value.objectValue?["changed"]?.boolValue ?? false
    return successResult(
      text: changed ? "Set the briefing for \(date)" : "The briefing for \(date) is unchanged",
      value: value)
  }
}
