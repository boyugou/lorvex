import MCP

extension ToolRegistry {
  func removeTaskChecklistItemResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let itemID = arguments["item_id"]?.stringValue, !itemID.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "An item_id value is required.",
        toolName: "remove_task_checklist_item")
    }

    let value = try await removeTaskChecklistItemPayload(itemID: itemID)
    return successResult(text: "Removed checklist item.", value: value)
  }
}
