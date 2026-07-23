import Foundation

extension LorvexSystemIntentRunner {
  public static func readHabitCompletions(
    id: LorvexHabit.ID,
    from: String?,
    to: String?,
    limit: Int = 500,
    core: any LorvexCoreServicing
  ) async throws -> HabitCompletionsSnapshot {
    try await core.getHabitCompletions(
      id: validatedHabitID(id),
      from: from.trimmedNilIfEmpty,
      to: to.trimmedNilIfEmpty,
      limit: limit
    )
  }

  public static func readHabitStats(
    id: LorvexHabit.ID,
    core: any LorvexCoreServicing
  ) async throws -> HabitStats {
    try await core.getHabitStats(id: validatedHabitID(id))
  }

  public static func batchCompleteHabits(
    habitIDs: [LorvexHabit.ID],
    date: String?,
    core: any LorvexCoreServicing
  ) async throws -> HabitCatalogSnapshot {
    // Reject malformed requests before resolving an omitted date through the
    // managed store. Validation failures must be deterministic and must not
    // touch production storage as a side effect.
    let ids = try validatedHabitIDList(habitIDs)
    let completionDate = try await logicalDay(date, core: core)
    return try await core.batchCompleteHabits(ids: ids, date: completionDate)
  }

  public static func readHabitReminderPolicies(
    id: LorvexHabit.ID,
    core: any LorvexCoreServicing
  ) async throws -> [HabitReminderPolicy] {
    try await core.getHabitReminderPolicies(id: validatedHabitID(id))
  }

  public static func upsertHabitReminderPolicy(
    id: LorvexHabit.ID,
    policyID: String?,
    reminderTime: String,
    enabled: Bool,
    core: any LorvexCoreServicing
  ) async throws -> HabitReminderPolicy {
    let policy = HabitReminderPolicy(
      id: policyID.trimmedNilIfEmpty ?? "",
      habitID: id,
      habitName: "",
      reminderTime: try validatedReminderTime(reminderTime),
      enabled: enabled,
      createdAt: "",
      updatedAt: ""
    )
    return try await core.upsertHabitReminderPolicy(id: validatedHabitID(id), policy: policy)
  }

  /// Delete one reminder policy by id; returns the removed policy or nil
  /// when no such policy exists.
  public static func deleteHabitReminderPolicy(
    policyID: String,
    core: any LorvexCoreServicing
  ) async throws -> HabitReminderPolicy? {
    let trimmed = policyID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw LorvexCoreError.validation(field: "policy_id", message: "A policy ID is required.")
    }
    return try await core.deleteHabitReminderPolicy(policyID: trimmed)
  }

  private static func validatedHabitIDList(_ ids: [LorvexHabit.ID]) throws -> [LorvexHabit.ID] {
    guard !ids.isEmpty else {
      throw LorvexCoreError.validation(
        field: "habit_ids", message: "At least one habit ID is required.")
    }
    return ids
  }

  private static func validatedReminderTime(_ value: String) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let pattern = #"^([01]\d|2[0-3]):[0-5]\d$"#
    guard trimmed.range(of: pattern, options: .regularExpression) != nil else {
      throw LorvexCoreError.validation(
        field: "reminder_time", message: "Reminder time must use HH:mm.")
    }
    return trimmed
  }
}
