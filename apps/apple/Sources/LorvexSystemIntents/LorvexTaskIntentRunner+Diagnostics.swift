import LorvexCore

extension LorvexTaskIntentRunner {
  public static func readSetupStatus(
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> SetupStatusSnapshot {
    try await LorvexSystemIntentRunner.readSetupStatus(core: core)
  }

  public static func readSyncStatus(
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> SyncStatusSnapshot {
    try await LorvexSystemIntentRunner.readSyncStatus(core: core)
  }

  public static func readAIChangelog(
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> AIChangelogSnapshot {
    try await LorvexSystemIntentRunner.readAIChangelog(core: core)
  }

  public static func readRecentLogs(
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> RecentLogsSnapshot {
    try await LorvexSystemIntentRunner.readRecentLogs(core: core)
  }

  public static func readGuide(
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> GuideSnapshot {
    try await LorvexSystemIntentRunner.readGuide(core: core)
  }
}
