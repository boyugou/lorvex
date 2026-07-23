import Foundation
import MCP

extension ToolRegistry {
  /// The focus date a write tool operates on, defaulting an omitted `date` to
  /// today in the configured product time zone — the same resolution the focus read tools
  /// (`get_current_focus`, `get_saved_focus_schedule`) use, so a plain "plan my
  /// focus" with no date lands on the day the reads show. A present wrong-typed
  /// `date` rejects instead of silently targeting today.
  func focusDate(arguments: [String: Value]) async throws -> String {
    try await logicalDay(arguments["date"])
  }

  func focusTaskIDs(arguments: [String: Value]) throws -> [String] {
    try StrictArgumentArray.requiredUniqueStrings(arguments["task_ids"], field: "task_ids")
  }

  func focusTaskIDRequiredResult(toolName: String) -> CallTool.Result {
    Self.errorResult(
      code: "validation",
      message: "At least one task_id is required.",
      toolName: toolName
    )
  }

  func focusSingleTaskIDRequiredResult(toolName: String) -> CallTool.Result {
    Self.errorResult(code: "validation", message: "A task_id value is required.", toolName: toolName)
  }

}
