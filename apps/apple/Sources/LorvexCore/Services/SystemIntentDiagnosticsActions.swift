extension LorvexSystemIntentRunner {
  public static func readSetupStatus(
    core: any LorvexCoreServicing
  ) async throws -> SetupStatusSnapshot {
    try await core.loadRuntimeDiagnostics().setup
  }

  public static func readSyncStatus(
    core: any LorvexCoreServicing
  ) async throws -> SyncStatusSnapshot {
    try await core.loadSyncStatus()
  }

  public static func readAIChangelog(
    core: any LorvexCoreServicing
  ) async throws -> AIChangelogSnapshot {
    try await core.loadRuntimeDiagnostics().changelog
  }

  public static func readRecentLogs(
    core: any LorvexCoreServicing
  ) async throws -> RecentLogsSnapshot {
    try await core.loadRuntimeDiagnostics().recentLogs
  }
}
