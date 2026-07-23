import LorvexCore

extension LorvexTaskIntentRunner {
  public static func completeTask(
    id: LorvexTask.ID,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> String {
    try await LorvexSystemIntentRunner.completeTask(id: id, core: core)
  }

  public static func cancelTask(
    id: LorvexTask.ID,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> String {
    try await LorvexSystemIntentRunner.cancelTask(id: id, core: core)
  }

  public static func reopenTask(
    id: LorvexTask.ID,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> String {
    try await LorvexSystemIntentRunner.reopenTask(id: id, core: core)
  }

  public static func deferTaskUntilTomorrow(
    id: LorvexTask.ID,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> String {
    try await LorvexSystemIntentRunner.deferTaskUntilTomorrow(id: id, core: core)
  }
}
