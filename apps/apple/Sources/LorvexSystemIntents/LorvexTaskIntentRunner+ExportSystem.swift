import LorvexCore

extension LorvexTaskIntentRunner {
  public static func exportData(
    format: String,
    entities: [String],
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> String {
    try await LorvexSystemIntentRunner.exportData(format: format, entities: entities, core: core)
  }

  public static func exportCalendarICS(
    from: String?,
    to: String?,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> String {
    try await LorvexSystemIntentRunner.exportCalendarICS(from: from, to: to, core: core)
  }

  public static func readRuntimeDiagnostics(
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> RuntimeDiagnosticsSnapshot {
    try await LorvexSystemIntentRunner.readRuntimeDiagnostics(core: core)
  }
}
