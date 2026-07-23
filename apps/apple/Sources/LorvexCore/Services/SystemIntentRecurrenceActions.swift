import Foundation

extension LorvexSystemIntentRunner {
  public static func setTaskRecurrence(
    taskID: LorvexTask.ID,
    frequency: TaskRecurrenceRule.Frequency,
    interval: Int?,
    weekdaysText: String?,
    until: String?,
    count: Int?,
    core: any LorvexCoreServicing
  ) async throws -> LorvexTask {
    try await core.setTaskRecurrence(
      taskID: validatedTaskID(taskID),
      rule: TaskRecurrenceRule(
        freq: frequency,
        interval: validatedRecurrenceInterval(interval),
        byDay: parsedRecurrenceWeekdays(weekdaysText),
        until: until.trimmedNilIfEmpty,
        count: validatedRecurrenceCount(count)
      )
    )
  }

  public static func removeTaskRecurrence(
    taskID: LorvexTask.ID,
    core: any LorvexCoreServicing
  ) async throws -> LorvexTask {
    try await core.removeTaskRecurrence(taskID: validatedTaskID(taskID))
  }

  public static func addTaskRecurrenceException(
    taskID: LorvexTask.ID,
    exceptionDate: String,
    core: any LorvexCoreServicing
  ) async throws -> LorvexTask {
    try await core.addTaskRecurrenceException(
      taskID: validatedTaskID(taskID),
      exceptionDate: validatedRecurrenceDate(exceptionDate)
    )
  }

  public static func removeTaskRecurrenceException(
    taskID: LorvexTask.ID,
    exceptionDate: String,
    core: any LorvexCoreServicing
  ) async throws -> LorvexTask {
    try await core.removeTaskRecurrenceException(
      taskID: validatedTaskID(taskID),
      exceptionDate: validatedRecurrenceDate(exceptionDate)
    )
  }
}
