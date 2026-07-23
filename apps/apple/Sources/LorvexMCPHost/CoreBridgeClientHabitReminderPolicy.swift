import Foundation
import LorvexCore
import MCP

extension CoreBridgeClient {
  func getHabitReminderPolicies(habitID: String?) async throws -> Value {
    // habit_id is optional: omit it to list every habit's policies (the
    // documented all-habits behavior).
    let policies: [HabitReminderPolicy]
    if let habitID, !habitID.isEmpty {
      policies = try await service.getHabitReminderPolicies(id: habitID)
    } else {
      policies = try await service.getAllHabitReminderPolicies()
    }
    return .object(["policies": .array(policies.map(Self.habitReminderPolicyValue(from:)))])
  }

  func upsertHabitReminderPolicy(
    id: String?,
    habitID: String,
    reminderTime: String,
    enabled: Bool
  ) async throws -> Value {
    let policy = HabitReminderPolicy(
      id: id ?? "",
      habitID: habitID,
      habitName: "",
      reminderTime: reminderTime,
      enabled: enabled,
      createdAt: "",
      updatedAt: ""
    )
    let saved = try await service.upsertHabitReminderPolicy(id: habitID, policy: policy)
    return Self.habitReminderPolicyValue(from: saved)
  }

  func deleteHabitReminderPolicy(policyID: String) async throws -> Value {
    let previous = try await service.deleteHabitReminderPolicy(policyID: policyID)
    return .object([
      "deleted": .bool(previous != nil),
      "id": .string(policyID),
      "previous": previous.map(Self.habitReminderPolicyValue(from:)) ?? .null,
    ])
  }
}
