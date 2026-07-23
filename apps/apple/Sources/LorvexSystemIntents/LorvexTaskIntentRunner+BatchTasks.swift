import LorvexCore

extension LorvexTaskIntentRunner {
  public static func batchCompleteTasks(
    taskIDs: [LorvexTask.ID],
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> TaskBatchLifecycleResult {
    try await LorvexSystemIntentRunner.batchCompleteTasks(taskIDs: taskIDs, core: core)
  }

  public static func batchReopenTasks(
    taskIDs: [LorvexTask.ID],
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> TaskBatchLifecycleResult {
    try await LorvexSystemIntentRunner.batchReopenTasks(taskIDs: taskIDs, core: core)
  }

  public static func batchCreateTasks(
    titlesText: String,
    notes: String? = nil,
    listID: LorvexList.ID? = nil,
    priority: Int? = nil,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> [LorvexTask] {
    try await LorvexSystemIntentRunner.batchCreateTasks(
      titlesText: titlesText,
      notes: notes,
      listID: listID,
      priority: priority,
      core: core
    )
  }

  public static func batchDeferTasks(
    taskIDs: [LorvexTask.ID],
    until: String,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> TaskBatchLifecycleResult {
    try await LorvexSystemIntentRunner.batchDeferTasks(
      taskIDs: taskIDs,
      until: until,
      core: core
    )
  }

  public static func batchMoveTasks(
    taskIDs: [LorvexTask.ID],
    listID: LorvexList.ID,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> [LorvexTask] {
    try await LorvexSystemIntentRunner.batchMoveTasks(
      taskIDs: taskIDs,
      listID: listID,
      core: core
    )
  }
}
