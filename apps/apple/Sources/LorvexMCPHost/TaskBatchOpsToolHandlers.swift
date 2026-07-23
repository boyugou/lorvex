import Foundation
import LorvexDomain
import MCP

extension ToolRegistry {
  func batchCompleteTasksResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let ids = try Self.batchTaskIDStrings(arguments)
    guard !ids.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "At least one task_id is required.",
        toolName: "batch_complete_tasks")
    }
    guard ids.count <= MCPBatchLimits.maxItems else {
      return Self.errorResult(
        code: "validation",
        message:
          "A batch accepts at most \(MCPBatchLimits.maxItems) task_ids per call; split larger sets across calls.",
        toolName: "batch_complete_tasks")
    }
    let value = try await batchCompleteTasksPayload(taskIDs: ids)
    return successResult(text: "Completed \(ids.count) task(s).", value: value)
  }

  func batchReopenTasksResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let ids = try Self.batchTaskIDStrings(arguments)
    guard !ids.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "At least one task_id is required.",
        toolName: "batch_reopen_tasks")
    }
    guard ids.count <= MCPBatchLimits.maxItems else {
      return Self.errorResult(
        code: "validation",
        message:
          "A batch accepts at most \(MCPBatchLimits.maxItems) task_ids per call; split larger sets across calls.",
        toolName: "batch_reopen_tasks")
    }
    let value = try await batchReopenTasksPayload(taskIDs: ids)
    return CallTool.Result(
      content: [
        .text(
          text: "Reopened \(value.objectValue?["count"]?.intValue ?? ids.count) task(s).",
          annotations: nil,
          _meta: nil
        )
      ],
      structuredContent: Optional.some(value),
      isError: false
    )
  }

  func batchCancelTasksResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let ids = try Self.batchTaskIDStrings(arguments)
    guard !ids.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "At least one task_id is required.",
        toolName: "batch_cancel_tasks")
    }
    guard ids.count <= MCPBatchLimits.maxItems else {
      return Self.errorResult(
        code: "validation",
        message:
          "A batch accepts at most \(MCPBatchLimits.maxItems) task_ids per call; split larger sets across calls.",
        toolName: "batch_cancel_tasks")
    }
    let cancelSeries = try StrictScalarArguments.bool(
      arguments["cancel_series"], field: "cancel_series", default: false)
    let value = try await batchCancelTasksPayload(taskIDs: ids, cancelSeries: cancelSeries)
    let count = value.objectValue?["count"]?.intValue ?? 0
    return CallTool.Result(
      content: [
        .text(text: "Cancelled \(count) task(s).", annotations: nil, _meta: nil)
      ],
      structuredContent: Optional.some(value),
      isError: false
    )
  }

  func batchMoveTasksResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let ids = try Self.batchTaskIDStrings(arguments)
    guard !ids.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "At least one task_id is required.",
        toolName: "batch_move_tasks")
    }
    guard ids.count <= MCPBatchLimits.maxItems else {
      return Self.errorResult(
        code: "validation",
        message:
          "A batch accepts at most \(MCPBatchLimits.maxItems) task_ids per call; split larger sets across calls.",
        toolName: "batch_move_tasks")
    }
    guard let listID = arguments["list_id"]?.stringValue, !listID.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "A list_id is required.", toolName: "batch_move_tasks")
    }
    let value = try await batchMoveTasksPayload(taskIDs: ids, listID: listID)
    return CallTool.Result(
      content: [
        .text(
          text: "Moved \(value.objectValue?["count"]?.intValue ?? ids.count) task(s).",
          annotations: nil,
          _meta: nil
        )
      ],
      structuredContent: Optional.some(value),
      isError: false
    )
  }
}

extension ToolRegistry {
  /// Reads a `task_ids` argument as `[String]`, rejecting the whole call when any
  /// array element is not a JSON string. A bare `compactMap(\.stringValue)` would
  /// silently drop a malformed id (a number, null, object, …), letting a partial
  /// batch report as a full run; throwing surfaces a `validation` error instead.
  /// An absent or empty array yields `[]` for the caller's own non-empty check to
  /// reject with the tool-specific message.
  static func batchTaskIDStrings(_ arguments: [String: Value]) throws -> [String] {
    try StrictArgumentArray.requiredUniqueStrings(
      arguments["task_ids"], field: "task_ids")
  }

  func batchCancelTasksInListResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let listID = arguments["list_id"]?.stringValue, !listID.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "list_id is required.",
        toolName: "batch_cancel_tasks_in_list")
    }
    let statuses = try StrictArgumentArray.optionalStrings(arguments["statuses"], field: "statuses")
    let cancelSeries = try StrictScalarArguments.bool(
      arguments["cancel_series"], field: "cancel_series", default: false)
    let value = try await batchCancelTasksInListPayload(
      listID: listID, statuses: statuses, cancelSeries: cancelSeries)
    let count = value.objectValue?["count"]?.intValue ?? 0
    return CallTool.Result(
      content: [
        .text(
          text: "Cancelled \(count) task(s) in list '\(listID)'.", annotations: nil, _meta: nil)
      ],
      structuredContent: Optional.some(value),
      isError: false
    )
  }
}
