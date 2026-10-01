import Foundation
import LorvexCore
import LorvexDomain

extension MobileStore {
  public func loadRuntimeDiagnostics() async {
    guard !isLoadingRuntimeDiagnostics else { return }
    isLoadingRuntimeDiagnostics = true
    defer { isLoadingRuntimeDiagnostics = false }
    do {
      let diagnostics = try await core.loadRuntimeDiagnostics()
      runtimeDiagnostics = diagnostics
      // The composed snapshot already carries the outbox read
      // `refreshSyncStatus()` performs, so adopt it into the shared
      // `syncStatus` rather than leaving a second, older depth on the store.
      syncStatus = diagnostics.sync
      errorMessage = nil
    } catch {
      await presentUserFacingError(error)
    }
    await loadRecentDiagnosticLogs()
  }

  /// Re-read the Cloud Sync queue state shown in Settings.
  ///
  /// Narrow on purpose: `loadSyncStatus()` scans only `sync_outbox`, so this is
  /// cheap enough to run every time the queue can have moved — Settings
  /// appearing, a refresh, a sync cycle that pushed or failed. The alternative,
  /// ``loadRuntimeDiagnostics()``, additionally reads preferences, counts tasks
  /// and lists, pages the changelog, and merges the recent-log stream, and so
  /// must stay off those paths.
  ///
  /// Best-effort: a failed read keeps the last known value. This backs a status
  /// line, and blanking it or raising an alert would be a worse answer than a
  /// momentarily stale depth.
  public func refreshSyncStatus() async {
    guard let status = try? await core.loadSyncStatus() else { return }
    syncStatus = status
  }

  /// Refresh the failure feed shown read-only in Settings → Diagnostics: the
  /// MetricKit crash / hang / CPU / disk-write rows the system reports, plus
  /// every `error`-level row Lorvex recorded itself.
  ///
  /// Including the app's own errors is what makes a background failure
  /// diagnosable at all. A Cloud Sync cycle keeps its technical detail out of
  /// the user-facing status line on purpose and writes it to `error_logs`
  /// instead, and a release build logs it to OSLog as private — so without this
  /// feed the reason a queue is stuck exists only on the device and is readable
  /// by nobody, including the developer.
  ///
  /// The predicate is by level, not by an allowlist of `error_logs.source`
  /// prefixes. An allowlist silently stops covering each new subsystem that
  /// starts logging, and the feed would go quiet exactly where it was needed;
  /// "anything the app called an error" needs no maintenance to stay complete.
  /// Lower levels stay out: `warn` and `info` rows are routine and would bury
  /// the failures this panel exists to show.
  ///
  /// Scans a generous slice of the stream so a crash is not hidden behind a
  /// burst of sync errors. Best-effort: a failed read leaves the prior list
  /// intact rather than surfacing an alert, since this is a secondary
  /// observability panel.
  public func loadRecentDiagnosticLogs() async {
    let fallback = diagnosticFallback.recentEntries()
    if let page = try? await core.loadRecentLogs(
      limit: 200, offset: 0, since: nil, levels: nil, sources: ["error_log"], redact: true)
    {
      let stored = page.entries.filter { $0.isMetricKitDiagnostic || $0.level == .error }
      recentDiagnosticLogs = Self.newestFirst(stored + fallback)
    } else if !fallback.isEmpty {
      // The store cannot be read at all: the fallback file is all there is.
      recentDiagnosticLogs = fallback
    }
  }

  /// Merges diagnostics rows newest first. Timestamps are the canonical
  /// ISO-8601 UTC strings, which order correctly as text; an undated row sorts
  /// last.
  nonisolated static func newestFirst(_ entries: [RecentLogEntry]) -> [RecentLogEntry] {
    entries.sorted { ($0.timestamp ?? "") > ($1.timestamp ?? "") }
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
