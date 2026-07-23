import Foundation
import LorvexCore
import MCP

extension CoreBridgeClient {
  func setCurrentFocus(
    date: String,
    taskIDs: [String],
    briefing: String?,
    timezone: String
  ) async throws -> Value {
    let projection = try await mcpMutations.setCurrentFocusForMcp(
      date: date, taskIDs: taskIDs, briefing: briefing, timezone: timezone)
    return Self.currentFocusValueWithTasks(from: projection)
  }

  func addToCurrentFocus(
    date: String,
    taskIDs: [String],
    briefing: String?,
    timezone: String
  ) async throws -> Value {
    let projection = try await mcpMutations.addToCurrentFocusForMcp(
      date: date, taskIDs: taskIDs, briefing: briefing, timezone: timezone)
    return Self.currentFocusValueWithTasks(from: projection)
  }
}
