import Foundation
import MCP

extension ToolRegistry {
  func addTaskChecklistItemResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let taskID = try Self.taskScopedID(from: arguments) else {
      return Self.errorResult(
        code: "validation", message: "A task_id value is required.",
        toolName: "add_task_checklist_item")
    }
    guard
      let text = arguments["text"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
      !text.isEmpty
    else {
      return Self.errorResult(
        code: "validation", message: "A non-empty checklist text is required.",
        toolName: "add_task_checklist_item")
    }

    let value = try await addTaskChecklistItemPayload(taskID: taskID, text: text)
    return successResult(text: "Added checklist item.", value: value)
  }

  func toggleTaskChecklistItemResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let itemID = arguments["item_id"]?.stringValue, !itemID.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "An item_id value is required.",
        toolName: "toggle_task_checklist_item")
    }
    guard let completed = arguments["completed"]?.boolValue else {
      return Self.errorResult(
        code: "validation", message: "A completed boolean is required.",
        toolName: "toggle_task_checklist_item")
    }

    let value = try await toggleTaskChecklistItemPayload(itemID: itemID, completed: completed)
    return successResult(text: "Updated checklist item.", value: value)
  }
}
