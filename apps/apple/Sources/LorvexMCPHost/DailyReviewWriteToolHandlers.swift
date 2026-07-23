import Foundation
import MCP

extension ToolRegistry {
  func addDailyReviewResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard
      let summary = arguments["summary"]?.stringValue?.trimmingCharacters(
        in: .whitespacesAndNewlines),
      !summary.isEmpty
    else {
      return Self.errorResult(
        code: "validation",
        message: "A non-empty summary is required.",
        toolName: "add_daily_review"
      )
    }
    let date = try await logicalDay(arguments["date"])
    let mood = try StrictScalarArguments.optionalInt(arguments["mood"], field: "mood")
    let energyLevel = try StrictScalarArguments.optionalInt(
      arguments["energy_level"], field: "energy_level")
    if let mood, !(1...5).contains(mood) {
      return Self.errorResult(
        code: "validation",
        message: "Mood must be between 1 and 5.",
        toolName: "add_daily_review"
      )
    }
    if let energyLevel, !(1...5).contains(energyLevel) {
      return Self.errorResult(
        code: "validation",
        message: "Energy must be between 1 and 5.",
        toolName: "add_daily_review"
      )
    }

    let value = try await upsertDailyReviewPayload(
      date: date,
      summary: summary,
      mood: mood,
      energyLevel: energyLevel,
      arguments: arguments
    )
    return successResult(text: "Saved daily review for \(date).", value: value)
  }
}
