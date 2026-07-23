import Foundation
import MCP

extension ToolRegistry {
  func addToCurrentFocusResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let date = try await focusDate(arguments: arguments)
    let taskIDs = try focusTaskIDs(arguments: arguments)
    guard !taskIDs.isEmpty else {
      return focusTaskIDRequiredResult(toolName: "add_to_current_focus")
    }

    let focus = try await addToCurrentFocusPayload(
      date: date,
      taskIDs: taskIDs,
      briefing: try StrictScalarArguments.optionalString(
        arguments["briefing"], field: "briefing").map(Value.string) ?? .null,
      timezone: try StrictScalarArguments.string(arguments["timezone"], field: "timezone", default: "")
    )
    return CallTool.Result(
      content: [
        .text(text: "Added tasks to current focus for \(date)", annotations: nil, _meta: nil)
      ],
      structuredContent: Optional.some(focus),
      isError: false
    )
  }
}
