import MCP

extension ToolRegistry {
  func skipHabitResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let id: String
    switch requiredTrimmedString("id", from: arguments, message: "A habit id is required.", toolName: "skip_habit") {
    case .value(let value): id = value
    case .error(let result): return result
    }
    let date = try await logicalDay(arguments["date"])

    let habit = try await coreBridge.skipHabit(id: id, date: date)
    return successResult(text: "Skipped habit for \(date): \(id)", value: habit)
  }

  func unskipHabitResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let id: String
    switch requiredTrimmedString("id", from: arguments, message: "A habit id is required.", toolName: "unskip_habit") {
    case .value(let value): id = value
    case .error(let result): return result
    }
    let date = try await logicalDay(arguments["date"])

    let habit = try await coreBridge.unskipHabit(id: id, date: date)
    return successResult(text: "Took back the skip for \(date): \(id)", value: habit)
  }
}
