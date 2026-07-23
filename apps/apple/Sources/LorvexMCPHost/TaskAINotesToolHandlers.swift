import Foundation
import MCP

extension ToolRegistry {
  func setTaskAINotesResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let taskID = try Self.taskScopedID(from: arguments) else {
      return Self.errorResult(
        code: "validation", message: "A task_id value is required.", toolName: "set_task_ai_notes")
    }
    guard let notes = arguments["notes"]?.stringValue else {
      return Self.errorResult(
        code: "validation",
        message: "A notes value is required; pass an empty string to clear.",
        toolName: "set_task_ai_notes"
      )
    }

    let value = try await coreBridge.setTaskAINotes(taskID: taskID, notes: notes)
    return successResult(text: "Set task AI context.", value: value)
  }
}
