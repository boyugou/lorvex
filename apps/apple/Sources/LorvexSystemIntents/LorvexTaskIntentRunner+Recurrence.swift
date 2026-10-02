import LorvexCore

extension LorvexTaskIntentRunner {
  public static func setTaskRecurrence(
    taskID: LorvexTask.ID,
    frequency: TaskRecurrenceRule.Frequency,
    interval: Int? = nil,
    weekdays: [String]? = nil,
    until: String? = nil,
    count: Int? = nil,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> LorvexTask {
    try await LorvexIntentFailure.rewording(core: core) {
      try await LorvexSystemIntentRunner.setTaskRecurrence(
        taskID: taskID,
        frequency: frequency,
        interval: interval,
        weekdays: weekdays,
        until: until,
        count: count,
        core: core
      )
    }
  }

  public static func removeTaskRecurrence(
    taskID: LorvexTask.ID,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> LorvexTask {
    try await LorvexIntentFailure.rewording(core: core) {
      try await LorvexSystemIntentRunner.removeTaskRecurrence(taskID: taskID, core: core)
    }
  }

  public static func addTaskRecurrenceException(
    taskID: LorvexTask.ID,
    exceptionDate: String,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> LorvexTask {
    try await LorvexIntentFailure.rewording(core: core) {
      try await LorvexSystemIntentRunner.addTaskRecurrenceException(
        taskID: taskID,
        exceptionDate: exceptionDate,
        core: core
      )
    }
  }

  public static func removeTaskRecurrenceException(
    taskID: LorvexTask.ID,
    exceptionDate: String,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> LorvexTask {
    try await LorvexIntentFailure.rewording(core: core) {
      try await LorvexSystemIntentRunner.removeTaskRecurrenceException(
        taskID: taskID,
        exceptionDate: exceptionDate,
        core: core
      )
    }
  }
}
