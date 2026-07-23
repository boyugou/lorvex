import LorvexCore

extension LorvexTaskIntentRunner {
  public static func addTaskChecklistItem(
    taskID: LorvexTask.ID,
    text: String,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> LorvexTask {
    try await LorvexSystemIntentRunner.addTaskChecklistItem(
      taskID: taskID,
      text: text,
      core: core
    )
  }

  public static func toggleTaskChecklistItem(
    itemID: TaskChecklistItem.ID,
    completed: Bool,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> LorvexTask {
    try await LorvexSystemIntentRunner.toggleTaskChecklistItem(
      itemID: itemID,
      completed: completed,
      core: core
    )
  }

  public static func updateTaskChecklistItem(
    itemID: TaskChecklistItem.ID,
    text: String,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> LorvexTask {
    try await LorvexSystemIntentRunner.updateTaskChecklistItem(
      itemID: itemID,
      text: text,
      core: core
    )
  }

  public static func removeTaskChecklistItem(
    itemID: TaskChecklistItem.ID,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> LorvexTask {
    try await LorvexSystemIntentRunner.removeTaskChecklistItem(itemID: itemID, core: core)
  }
}
