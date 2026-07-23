import Foundation
import LorvexCloudSync

extension AppStore {
  /// Query the live iCloud account status and store it for the Cloud Sync
  /// settings tab. Best-effort: with no sync coordinator (previews/tests) or a
  /// failed query, the value stays `.couldNotDetermine`. Without this the
  /// Account row would always read "Unknown" since nothing else writes it.
  /// The durable pause reason rides along so the tab's "Sync Paused" notice is
  /// current whenever the tab is opened.
  func refreshCloudKitAccountAvailability() async {
    await refreshCloudSyncPauseReason()
    guard let checker = cloudSyncCoordinator?.accountChecker else { return }
    cloudKitAccountAvailability = (try? await checker.checkAccountStatus()) ?? .couldNotDetermine
  }

  /// A point-in-time snapshot of Cloud Sync health, derived from sync report
  /// storage and account availability. Suitable for display in Settings.
  var cloudSyncStatusReport: CloudSyncStatusReport {
    // Push and pull complete in one cycle, so both timestamps track the same
    // last-successful-cycle moment; the pull error doubles as the cycle error.
    let cycleAt = lastCloudSyncCycleReport == nil ? nil : lastCloudSyncRemoteChangeSucceededAt
    return CloudSyncStatusReport(
      mode: cloudSyncMode,
      accountAvailability: cloudKitAccountAvailability,
      pauseReason: cloudSyncPauseReason,
      lastPushAt: cycleAt,
      lastPushError: nil,
      lastPullAt: lastCloudSyncRemoteChangeSucceededAt,
      lastPullError: lastCloudSyncRemoteChangeErrorMessage,
      pendingCount: runtimeDiagnostics?.sync.pendingCount ?? 0
    )
  }
}
