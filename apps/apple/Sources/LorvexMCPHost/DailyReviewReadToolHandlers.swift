import MCP

extension ToolRegistry {
  func dailyReviewResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let date = try await logicalDay(arguments["date"])
    let value = try await dailyReviewPayload(date: date)
    return fencedReadResult(text: "Loaded daily review for \(date).", value: .object([
          "date": .string(date),
          "review": value,
        ]))
  }
}
