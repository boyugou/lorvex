import Foundation

extension LorvexSystemIntentRunner {
  public static func addTaskReminder(
    taskID: LorvexTask.ID,
    reminderAt: String,
    core: any LorvexCoreServicing
  ) async throws -> LorvexTask {
    try await core.addTaskReminder(
      taskID: validatedTaskID(taskID),
      reminderAt: validatedReminderTimestamp(reminderAt)
    )
  }

  public static func removeTaskReminder(
    taskID: LorvexTask.ID,
    reminderID: TaskReminder.ID,
    core: any LorvexCoreServicing
  ) async throws -> LorvexTask {
    try await core.removeTaskReminder(
      taskID: validatedTaskID(taskID),
      reminderID: validatedReminderID(reminderID)
    )
  }

  public static func readDueTaskReminders(
    asOf: String?,
    limit: Int?,
    core: any LorvexCoreServicing
  ) async throws -> [TaskReminderWithTask] {
    try await core.getDueTaskReminders(
      asOf: asOf.trimmedNilIfEmpty,
      limit: validatedReminderLimit(limit)
    )
  }

  public static func readUpcomingTaskReminders(
    hoursAhead: Int?,
    limit: Int?,
    core: any LorvexCoreServicing
  ) async throws -> [TaskReminderWithTask] {
    try await core.getUpcomingTaskReminders(
      hoursAhead: validatedHoursAhead(hoursAhead),
      limit: validatedReminderLimit(limit)
    )
  }
}
