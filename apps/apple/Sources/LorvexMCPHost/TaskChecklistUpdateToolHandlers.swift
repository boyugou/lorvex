import Foundation
import MCP

extension ToolRegistry {
  func updateTaskChecklistItemResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let itemID = arguments["item_id"]?.stringValue, !itemID.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "An item_id value is required.",
        toolName: "update_task_checklist_item")
    }
    guard
      let text = arguments["text"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
      !text.isEmpty
    else {
      return Self.errorResult(
        code: "validation", message: "A non-empty checklist text is required.",
        toolName: "update_task_checklist_item")
    }

    let value = try await updateTaskChecklistItemPayload(itemID: itemID, text: text)
    return successResult(text: "Updated checklist item text.", value: value)
  }
}
