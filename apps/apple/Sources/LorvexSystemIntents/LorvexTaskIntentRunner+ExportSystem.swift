import LorvexCore

extension LorvexTaskIntentRunner {
  public static func exportData(
    format: String,
    entities: [String],
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> String {
    try await LorvexIntentFailure.rewording(core: core) {
      try await LorvexSystemIntentRunner.exportData(format: format, entities: entities, core: core)
    }
  }

  public static func exportCalendarICS(
    from: String?,
    to: String?,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> String {
    try await LorvexIntentFailure.rewording(core: core) {
      try await LorvexSystemIntentRunner.exportCalendarICS(from: from, to: to, core: core)
    }
  }
}
