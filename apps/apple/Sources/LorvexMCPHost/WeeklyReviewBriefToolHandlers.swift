import MCP

extension ToolRegistry {
  func weeklyReviewBriefResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let value = try await coreBridge.loadWeeklyReviewBrief(arguments: arguments)
    return fencedReadResult(text: "Loaded weekly review brief.", value: value)
  }
}
