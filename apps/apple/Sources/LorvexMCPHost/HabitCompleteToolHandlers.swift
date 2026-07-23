import MCP

extension ToolRegistry {
  func completeHabitResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let id: String
    switch requiredTrimmedString("id", from: arguments, message: "A habit id is required.", toolName: "complete_habit") {
    case .value(let value): id = value
    case .error(let result): return result
    }
    let date = try await logicalDay(arguments["date"])

    let habit = try await coreBridge.completeHabit(id: id, date: date)
    return successResult(text: "Completed habit for \(date): \(id)", value: habit)
  }

  func adjustHabitCompletionResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let id: String
    switch requiredTrimmedString("id", from: arguments, message: "A habit id is required.", toolName: "adjust_habit_completion") {
    case .value(let value): id = value
    case .error(let result): return result
    }
    guard let delta = arguments["delta"]?.intValue else {
      return Self.errorResult(code: "validation", message: "An integer delta is required.", toolName: "adjust_habit_completion")
    }
    let date = try await logicalDay(arguments["date"])

    let habit = try await coreBridge.adjustHabitCompletion(id: id, date: date, delta: delta)
    return CallTool.Result(
      content: [
        .text(text: "Adjusted habit \(id) by \(delta) for \(date)", annotations: nil, _meta: nil)
      ],
      structuredContent: Optional.some(habit),
      isError: false
    )
  }
}
