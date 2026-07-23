import MCP

extension ToolRegistry {
  func reorderTaskChecklistItemsResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let taskID = try Self.taskScopedID(from: arguments) else {
      return Self.errorResult(
        code: "validation", message: "A task_id value is required.",
        toolName: "reorder_task_checklist_items")
    }
    let itemIDs = try StrictArgumentArray.requiredUniqueStrings(
      arguments["item_ids"], field: "item_ids")
    guard !itemIDs.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "A non-empty item_ids array is required.",
        toolName: "reorder_task_checklist_items")
    }

    let value = try await reorderTaskChecklistItemsPayload(taskID: taskID, itemIDs: itemIDs)
    return successResult(text: "Reordered checklist items.", value: value)
  }
}
