import Foundation

extension MobileStore {
  public func loadRuntimeDiagnostics() async {
    guard !isLoadingRuntimeDiagnostics else { return }
    isLoadingRuntimeDiagnostics = true
    defer { isLoadingRuntimeDiagnostics = false }
    do {
      runtimeDiagnostics = try await core.loadRuntimeDiagnostics()
      errorMessage = nil
    } catch {
      await presentUserFacingError(error)
    }
    await loadRecentDiagnosticLogs()
  }

  /// Refresh the crash-scoped diagnostics feed shown read-only in Settings:
  /// only the MetricKit crash / hang / CPU / disk-write rows, so the feed
  /// matches its "Crashes, hangs, and resource exceptions" footer rather than
  /// mixing in unrelated `error_log` rows (sync failures, retention GC).
  ///
  /// Scans a generous slice of the `error_log` stream through the service, then
  /// keeps only the MetricKit rows (identified by ``RecentLogEntry/origin``), so
  /// crashes aren't hidden behind a burst of sync errors. Best-effort: a failed
  /// read leaves the prior list intact rather than surfacing an alert, since
  /// this is a secondary observability panel.
  public func loadRecentDiagnosticLogs() async {
    if let page = try? await core.loadRecentLogs(
      limit: 200, offset: 0, since: nil, levels: nil, sources: ["error_log"], redact: true)
    {
      recentDiagnosticLogs = page.entries.filter(\.isMetricKitDiagnostic)
    }
  }

  public func setBadgeEnabled(
    _ enabled: Bool,
    preferences: MobileSetupPreferences = MobileSetupPreferences()
  ) {
    badgeEnabled = enabled
    preferences.setBadgeEnabled(enabled)
    Task { await updateBadge() }
  }

}
