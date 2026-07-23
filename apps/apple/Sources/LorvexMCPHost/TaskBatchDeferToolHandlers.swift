import MCP

extension ToolRegistry {
  func batchDeferTasksResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let taskIDs = try Self.batchTaskIDStrings(arguments)
    guard !taskIDs.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "At least one task id is required.",
        toolName: "batch_defer_tasks")
    }
    guard taskIDs.count <= MCPBatchLimits.maxItems else {
      return Self.errorResult(
        code: "validation",
        message:
          "batch_defer_tasks accepts at most \(MCPBatchLimits.maxItems) task_ids per call; split larger sets across calls.",
        toolName: "batch_defer_tasks")
    }
    guard let untilDate = arguments["until_date"]?.stringValue, !untilDate.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "An until_date value is required.",
        toolName: "batch_defer_tasks")
    }

    let value = try await coreBridge.batchDeferTasks(
      taskIDs: taskIDs,
      untilDate: untilDate,
      reason: try StrictScalarArguments.optionalString(arguments["reason"], field: "reason"),
      structuredReason: try StrictScalarArguments.optionalString(
        arguments["structured_reason"], field: "structured_reason")
    )

    return CallTool.Result(
      content: [
        .text(
          text: "Deferred \(value.objectValue?["count"]?.intValue ?? 0) task(s).",
          annotations: nil, _meta: nil)
      ],
      structuredContent: Optional.some(SecurityFencing.fenceValue(value)),
      isError: false
    )
  }
}
