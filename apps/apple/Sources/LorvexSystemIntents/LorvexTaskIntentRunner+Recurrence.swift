import LorvexCore

extension LorvexTaskIntentRunner {
  public static func setTaskRecurrence(
    taskID: LorvexTask.ID,
    frequency: TaskRecurrenceRule.Frequency,
    interval: Int? = nil,
    weekdaysText: String? = nil,
    until: String? = nil,
    count: Int? = nil,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> LorvexTask {
    try await LorvexSystemIntentRunner.setTaskRecurrence(
      taskID: taskID,
      frequency: frequency,
      interval: interval,
      weekdaysText: weekdaysText,
      until: until,
      count: count,
      core: core
    )
  }

  public static func removeTaskRecurrence(
    taskID: LorvexTask.ID,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> LorvexTask {
    try await LorvexSystemIntentRunner.removeTaskRecurrence(taskID: taskID, core: core)
  }

  public static func addTaskRecurrenceException(
    taskID: LorvexTask.ID,
    exceptionDate: String,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> LorvexTask {
    try await LorvexSystemIntentRunner.addTaskRecurrenceException(
      taskID: taskID,
      exceptionDate: exceptionDate,
      core: core
    )
  }

  public static func removeTaskRecurrenceException(
    taskID: LorvexTask.ID,
    exceptionDate: String,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> LorvexTask {
    try await LorvexSystemIntentRunner.removeTaskRecurrenceException(
      taskID: taskID,
      exceptionDate: exceptionDate,
      core: core
    )
  }
}
