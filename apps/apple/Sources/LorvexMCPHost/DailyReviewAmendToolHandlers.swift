import Foundation
import MCP

extension ToolRegistry {
  func amendDailyReviewResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let date = arguments["date"]?.stringValue, !date.isEmpty else {
      return Self.errorResult(
        code: "validation",
        message: "A date is required.",
        toolName: "amend_daily_review"
      )
    }
    let mood = try StrictScalarArguments.optionalInt(arguments["mood"], field: "mood")
    let energyLevel = try StrictScalarArguments.optionalInt(
      arguments["energy_level"], field: "energy_level")
    if let mood, !(1...5).contains(mood) {
      return Self.errorResult(
        code: "validation",
        message: "Mood must be between 1 and 5.",
        toolName: "amend_daily_review"
      )
    }
    if let energyLevel, !(1...5).contains(energyLevel) {
      return Self.errorResult(
        code: "validation",
        message: "Energy must be between 1 and 5.",
        toolName: "amend_daily_review"
      )
    }
    if let summary = try StrictScalarArguments.optionalString(
      arguments["summary"], field: "summary")
    {
      let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else {
        return Self.errorResult(
          code: "validation",
          message: "Summary must not be empty.",
          toolName: "amend_daily_review"
        )
      }
    }
    let value: Value
    do {
      value = try await amendDailyReviewPayload(date: date, arguments: arguments)
    } catch let error as DailyReviewToolStoreError {
      return notFoundResult(error, toolName: "amend_daily_review")
    }
    return successResult(text: "Amended daily review for \(date).", value: value)
  }
}
