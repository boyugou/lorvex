import Foundation
import MCP

extension ToolRegistry {
  func setDailyBriefingResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let date = try await logicalDay(arguments["date"])
    let briefing = try StrictScalarArguments.string(
      arguments["briefing"], field: "briefing", default: "")
    let value = try await coreBridge.setDailyBriefing(date: date, briefing: briefing)
    let changed = value.objectValue?["changed"]?.boolValue ?? false
    return successResult(
      text: changed ? "Set the briefing for \(date)" : "The briefing for \(date) is unchanged",
      value: value)
  }
}
