import MCP

extension ToolRegistry {
  func habitReminderPoliciesPayload(habitID: String?) async throws -> Value {
    try await coreBridge.getHabitReminderPolicies(habitID: habitID)
  }

  func upsertHabitReminderPolicyPayload(
    id: String?,
    habitID: String,
    reminderTime: String,
    enabled: Bool
  ) async throws -> Value {
    try await coreBridge.upsertHabitReminderPolicy(
      id: id,
      habitID: habitID,
      reminderTime: reminderTime,
      enabled: enabled
    )
  }

  func deleteHabitReminderPolicyPayload(policyID: String) async throws -> Value {
    try await coreBridge.deleteHabitReminderPolicy(policyID: policyID)
  }
}
