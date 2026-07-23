import Foundation
import MCP

extension ToolRegistry {
  func getHabitReminderPoliciesResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let habitID = try StrictScalarArguments.optionalString(
      arguments["habit_id"], field: "habit_id")

    let payload = try await habitReminderPoliciesPayload(habitID: habitID)
    let count = payload.objectValue?["policies"]?.arrayValue?.count ?? 0

    return CallTool.Result(
      content: [
        .text(
          text: "Returned \(count) habit reminder \(count == 1 ? "policy" : "policies").",
          annotations: nil, _meta: nil)
      ],
      structuredContent: Optional.some(payload),
      isError: false
    )
  }

  func upsertHabitReminderPolicyResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let habitID = arguments["habit_id"]?.stringValue, !habitID.isEmpty else {
      return Self.errorResult(code: "validation", message: "A habit_id is required.", toolName: "upsert_habit_reminder_policy")
    }
    guard let reminderTime = arguments["reminder_time"]?.stringValue, !reminderTime.isEmpty else {
      return Self.errorResult(code: "validation", message: "A reminder_time is required.", toolName: "upsert_habit_reminder_policy")
    }
    guard Self.isValidReminderTime(reminderTime) else {
      return Self.errorResult(code: "validation", message: "reminder_time must use HH:MM format.", toolName: "upsert_habit_reminder_policy")
    }
    let id = try StrictScalarArguments.optionalString(arguments["id"], field: "id")
    let enabled = try StrictScalarArguments.bool(
      arguments["enabled"], field: "enabled", default: true)

    let policy = try await upsertHabitReminderPolicyPayload(
      id: id,
      habitID: habitID,
      reminderTime: reminderTime,
      enabled: enabled
    )
    return successResult(text: "Saved habit reminder policy.", value: policy)
  }

  func deleteHabitReminderPolicyResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let id: String
    switch requiredTrimmedString("id", from: arguments, message: "An id is required.", toolName: "delete_habit_reminder_policy") {
    case .value(let value): id = value
    case .error(let result): return result
    }
    let payload = try await deleteHabitReminderPolicyPayload(policyID: id)
    let deleted = payload.objectValue?["deleted"]?.boolValue ?? false
    return CallTool.Result(
      content: [
        .text(
          text: deleted
            ? "Deleted habit reminder policy."
            : "No habit reminder policy with that id.",
          annotations: nil, _meta: nil)
      ],
      structuredContent: Optional.some(SecurityFencing.fenceValue(payload)),
      isError: false
    )
  }

  private static func isValidReminderTime(_ value: String) -> Bool {
    let parts = value.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2,
      let hour = Int(parts[0]),
      let minute = Int(parts[1])
    else {
      return false
    }
    return (0...23).contains(hour) && (0...59).contains(minute)
  }
}
