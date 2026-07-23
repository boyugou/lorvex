import LorvexCore

extension LorvexTaskIntentRunner {
  public static func addTaskReminder(
    taskID: LorvexTask.ID,
    reminderAt: String,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> LorvexTask {
    try await LorvexSystemIntentRunner.addTaskReminder(
      taskID: taskID,
      reminderAt: reminderAt,
      core: core
    )
  }

  public static func removeTaskReminder(
    taskID: LorvexTask.ID,
    reminderID: TaskReminder.ID,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> LorvexTask {
    try await LorvexSystemIntentRunner.removeTaskReminder(
      taskID: taskID,
      reminderID: reminderID,
      core: core
    )
  }

  public static func readDueTaskReminders(
    asOf: String? = nil,
    limit: Int? = nil,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> [TaskReminderWithTask] {
    try await LorvexSystemIntentRunner.readDueTaskReminders(
      asOf: asOf,
      limit: limit,
      core: core
    )
  }

  public static func readUpcomingTaskReminders(
    hoursAhead: Int? = nil,
    limit: Int? = nil,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> [TaskReminderWithTask] {
    try await LorvexSystemIntentRunner.readUpcomingTaskReminders(
      hoursAhead: hoursAhead,
      limit: limit,
      core: core
    )
  }
}
