public struct RuntimeDiagnosticsSnapshot: Equatable, Sendable {
  public var setup: SetupStatusSnapshot
  public var sync: SyncStatusSnapshot
  public var changelog: AIChangelogSnapshot
  public var recentLogs: RecentLogsSnapshot

  public init(
    setup: SetupStatusSnapshot,
    sync: SyncStatusSnapshot,
    changelog: AIChangelogSnapshot,
    recentLogs: RecentLogsSnapshot
  ) {
    self.setup = setup
    self.sync = sync
    self.changelog = changelog
    self.recentLogs = recentLogs
  }
}
