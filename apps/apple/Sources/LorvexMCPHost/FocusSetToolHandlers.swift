import Foundation
import MCP

extension ToolRegistry {
  func setCurrentFocusResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let date = try await focusDate(arguments: arguments)
    let taskIDs = try focusTaskIDs(arguments: arguments)

    let focus = try await setCurrentFocusPayload(
      date: date,
      taskIDs: taskIDs,
      briefing: try StrictScalarArguments.optionalString(
        arguments["briefing"], field: "briefing").map(Value.string) ?? .null,
      timezone: try StrictScalarArguments.string(arguments["timezone"], field: "timezone", default: "")
    )
    return successResult(text: "Set current focus for \(date)", value: focus)
  }
}
