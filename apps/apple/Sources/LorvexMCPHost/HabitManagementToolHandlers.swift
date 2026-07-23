import Foundation
import MCP

extension ToolRegistry {
  func updateHabitResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let id: String
    switch requiredTrimmedString("id", from: arguments, message: "A habit id is required.", toolName: "update_habit") {
    case .value(let value): id = value
    case .error(let result): return result
    }
    if let name = try StrictScalarArguments.optionalString(arguments["name"], field: "name")?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      name.isEmpty
    {
      return Self.errorResult(
        code: "validation", message: "Habit name must not be empty.", toolName: "update_habit")
    }
    let targetCount = try StrictScalarArguments.optionalInt(
      arguments["target_count"], field: "target_count")
    if let targetCount, targetCount < 1 {
      return Self.errorResult(
        code: "validation", message: "target_count must be at least 1.", toolName: "update_habit")
    }

    let habit = try await updateHabitPayload(id: id, arguments: arguments)
    return successResult(text: "Updated habit: \(id)", value: habit)
  }

  func deleteHabitResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let id: String
    switch requiredTrimmedString("id", from: arguments, message: "A habit id is required.", toolName: "delete_habit") {
    case .value(let value): id = value
    case .error(let result): return result
    }

    let date = try await logicalDay(nil)
    let deleted = try await deleteHabitPayload(id: id, date: date)
    return successResult(text: "Deleted habit: \(id)", value: deleted)
  }

  func reorderHabitsResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let habitIDs = try StrictArgumentArray.requiredUniqueStrings(
      arguments["habit_ids"], field: "habit_ids")
    guard !habitIDs.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "A non-empty habit_ids array is required.",
        toolName: "reorder_habits")
    }
    let date = try await logicalDay(arguments["date"])

    let values = try await reorderHabitsPayload(orderedIDs: habitIDs, date: date)
    return successResult(
      text: "Reordered \(values.count) habit(s) for \(date).",
      value: .object([
        "date": .string(date),
        "habits": .array(values),
      ]))
  }

  func batchCompleteHabitResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let ids = try StrictArgumentArray.requiredUniqueStrings(
      arguments["habit_ids"], field: "habit_ids")
    guard !ids.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "habit_ids cannot be empty.",
        toolName: "batch_complete_habits")
    }
    guard ids.count <= MCPBatchLimits.maxItems else {
      return Self.errorResult(
        code: "validation",
        message:
          "batch_complete_habits accepts at most \(MCPBatchLimits.maxItems) habit_ids per call; split larger sets across calls.",
        toolName: "batch_complete_habits")
    }
    let date = try await logicalDay(arguments["date"])

    let result = try await batchCompleteHabitsPayload(ids: ids, date: date)
    let count = result.objectValue?["count"]?.intValue ?? 0
    return CallTool.Result(
      content: [
        .text(text: "Completed \(count) habit(s) for \(date).", annotations: nil, _meta: nil)
      ],
      structuredContent: Optional.some(result),
      isError: false
    )
  }
}
