import Foundation
import MCP

extension ToolRegistry {
  func removeFromCurrentFocusResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let date = try await focusDate(arguments: arguments)
    guard let taskID = try Self.taskScopedID(from: arguments) else {
      return focusSingleTaskIDRequiredResult(toolName: "remove_from_current_focus")
    }

    let structured = try await removeFromCurrentFocusPayload(date: date, taskID: taskID)
    return CallTool.Result(
      content: [
        .text(text: "Removed task from current focus for \(date)", annotations: nil, _meta: nil)
      ],
      structuredContent: Optional.some(structured),
      isError: false
    )
  }
}
