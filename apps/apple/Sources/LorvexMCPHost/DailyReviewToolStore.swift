import MCP

extension ToolRegistry {
  func dailyReviewPayload(date: String) async throws -> Value {
    try await coreBridge.loadDailyReview(date: date)
  }

  func upsertDailyReviewPayload(
    date: String,
    summary: String,
    mood: Int?,
    energyLevel: Int?,
    arguments: [String: Value]
  ) async throws -> Value {
    try await coreBridge.upsertDailyReview(
      date: date,
      summary: summary,
      mood: mood,
      energyLevel: energyLevel,
      wins: try StrictScalarArguments.optionalString(arguments["wins"], field: "wins"),
      blockers: try StrictScalarArguments.optionalString(arguments["blockers"], field: "blockers"),
      learnings: try StrictScalarArguments.optionalString(
        arguments["learnings"], field: "learnings"),
      linkedTaskIDs: try StrictArgumentArray.optionalStrings(
        arguments["linked_task_ids"], field: "linked_task_ids"),
      linkedListIDs: try StrictArgumentArray.optionalStrings(
        arguments["linked_list_ids"], field: "linked_list_ids")
    )
  }

  func amendDailyReviewPayload(date: String, arguments: [String: Value]) async throws -> Value {
    try await coreBridge.amendDailyReview(arguments: arguments)
  }
}

struct DailyReviewToolStoreError: ToolStoreError {
  let message: String
}
