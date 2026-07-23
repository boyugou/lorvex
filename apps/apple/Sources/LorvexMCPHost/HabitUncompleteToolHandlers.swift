import MCP

extension ToolRegistry {
  func uncompleteHabitResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let id: String
    switch requiredTrimmedString("id", from: arguments, message: "A habit id is required.", toolName: "uncomplete_habit") {
    case .value(let value): id = value
    case .error(let result): return result
    }
    let date = try await logicalDay(arguments["date"])

    let habit = try await coreBridge.uncompleteHabit(id: id, date: date)
    return successResult(text: "Reset habit for \(date): \(id)", value: habit)
  }
}
