import MCP

extension ToolRegistry {
  func habitsResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let date = try await logicalDay(arguments["date"])
    let includeStats = try StrictScalarArguments.bool(
      arguments["include_stats"], field: "include_stats", default: false)
    let values = try await habitsPayload(date: date, includeStats: includeStats)
    return CallTool.Result(
      content: [
        .text(
          text: "Lorvex has \(values.count) habit(s) for \(date).", annotations: nil, _meta: nil)
      ],
      structuredContent: Optional.some(
        .object([
          "date": .string(date),
          "habits": .array(values),
        ])),
      isError: false
    )
  }

  func habitCompletionsResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let id = arguments["habit_id"]?.stringValue, !id.isEmpty else {
      return Self.errorResult(code: "validation", message: "A habit_id is required.", toolName: "get_habit_completions")
    }
    let from = try StrictScalarArguments.optionalString(arguments["from"], field: "from")
    let to = try StrictScalarArguments.optionalString(arguments["to"], field: "to")
    let limit = min(
      max(1, try StrictScalarArguments.int(arguments["limit"], field: "limit", default: 100)),
      500)

    let payload: Value
    payload = try await habitCompletionsPayload(id: id, from: from, to: to, limit: limit)
    let count = payload.objectValue?["returned"]?.intValue ?? 0

    return CallTool.Result(
      content: [
        .text(text: "Returned \(count) habit completion record(s).", annotations: nil, _meta: nil)
      ],
      structuredContent: Optional.some(payload),
      isError: false
    )
  }

  func habitStatsResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let id = arguments["habit_id"]?.stringValue, !id.isEmpty else {
      return Self.errorResult(code: "validation", message: "A habit_id is required.", toolName: "get_habit_stats")
    }

    let payload: Value
    payload = try await habitStatsPayload(id: id)

    return fencedReadResult(text: "Habit stats for \(id).", value: payload)
  }
}
