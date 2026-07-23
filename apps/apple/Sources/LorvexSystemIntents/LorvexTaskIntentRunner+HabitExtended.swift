import LorvexCore

extension LorvexTaskIntentRunner {
  public static func readHabitCompletions(
    id: LorvexHabit.ID,
    from: String? = nil,
    to: String? = nil,
    limit: Int = 500,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> HabitCompletionsSnapshot {
    try await LorvexSystemIntentRunner.readHabitCompletions(
      id: id,
      from: from,
      to: to,
      limit: limit,
      core: core
    )
  }

  public static func readHabitStats(
    id: LorvexHabit.ID,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> HabitStats {
    try await LorvexSystemIntentRunner.readHabitStats(id: id, core: core)
  }

  public static func batchCompleteHabits(
    habitIDs: [LorvexHabit.ID],
    date: String? = nil,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> HabitCatalogSnapshot {
    try await LorvexSystemIntentRunner.batchCompleteHabits(
      habitIDs: habitIDs,
      date: date,
      core: core
    )
  }

  public static func readHabitReminderPolicies(
    id: LorvexHabit.ID,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> [HabitReminderPolicy] {
    try await LorvexSystemIntentRunner.readHabitReminderPolicies(id: id, core: core)
  }

  public static func upsertHabitReminderPolicy(
    id: LorvexHabit.ID,
    policyID: String? = nil,
    reminderTime: String,
    enabled: Bool,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> HabitReminderPolicy {
    try await LorvexSystemIntentRunner.upsertHabitReminderPolicy(
      id: id,
      policyID: policyID,
      reminderTime: reminderTime,
      enabled: enabled,
      core: core
    )
  }

  public static func deleteHabitReminderPolicy(
    policyID: String,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> HabitReminderPolicy? {
    try await LorvexSystemIntentRunner.deleteHabitReminderPolicy(policyID: policyID, core: core)
  }
}
