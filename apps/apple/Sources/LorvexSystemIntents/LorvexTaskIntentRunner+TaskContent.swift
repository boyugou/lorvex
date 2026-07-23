import LorvexCore

extension LorvexTaskIntentRunner {
  public static func appendToTaskBody(
    id: LorvexTask.ID,
    text: String,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> LorvexTask {
    try await LorvexSystemIntentRunner.appendToTaskBody(id: id, text: text, core: core)
  }

  public static func setTaskReminders(
    id: LorvexTask.ID,
    remindersText: String,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> LorvexTask {
    try await LorvexSystemIntentRunner.setTaskReminders(
      id: id,
      remindersText: remindersText,
      core: core
    )
  }
}
