import Foundation
import MCP

extension ToolRegistry {
  func batchCreateTasksResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let taskInputs = arguments["tasks"]?.arrayValue, !taskInputs.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "At least one task is required.",
        toolName: "batch_create_tasks")
    }
    guard taskInputs.count <= MCPBatchLimits.maxItems else {
      return Self.errorResult(
        code: "validation",
        message:
          "batch_create_tasks accepts at most \(MCPBatchLimits.maxItems) tasks per call; split larger sets across calls.",
        toolName: "batch_create_tasks")
    }

    let structured = try await batchCreateTasksPayload(
      taskInputs: taskInputs,
      includeAdvice: try StrictScalarArguments.bool(
        arguments["include_advice"], field: "include_advice", default: false)
    )
    return successResult(text: "Created \(taskInputs.count) tasks.", value: structured)
  }
}
