import Foundation
import MCP

extension ToolRegistry {
  func batchUpdateTasksResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let updates = arguments["updates"]?.arrayValue, !updates.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "At least one update is required.",
        toolName: "batch_update_tasks")
    }
    guard updates.count <= MCPBatchLimits.maxItems else {
      return Self.errorResult(
        code: "validation",
        message:
          "batch_update_tasks accepts at most \(MCPBatchLimits.maxItems) updates per call; split larger sets across calls.",
        toolName: "batch_update_tasks")
    }

    let structured = try await batchUpdateTasksPayload(updates: updates)
    let applied = structured.objectValue?["count"]?.intValue ?? updates.count
    let skipped = structured.objectValue?["skipped"]?.arrayValue?.count ?? 0
    let text =
      skipped == 0 ? "Updated \(applied) tasks." : "Updated \(applied) tasks; skipped \(skipped)."
    return successResult(text: text, value: structured)
  }
}
