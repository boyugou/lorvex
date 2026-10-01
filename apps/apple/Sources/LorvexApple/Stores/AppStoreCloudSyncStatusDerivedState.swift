import Foundation
import LorvexCloudSync

extension AppStore {
  /// Query the live iCloud account status and store it for the Cloud Sync
  /// settings tab. Best-effort: with no sync controller (previews/tests) the
  /// value is left alone, and a failed query reads `.couldNotDetermine`.
  /// With sync off Lorvex does not contact iCloud at all: the value resets to
  /// `.couldNotDetermine`, which the tab shows as "Not checked".
  /// The durable pause reason rides along so the tab's "Sync Paused" notice is
  /// current whenever the tab is opened.
  func refreshCloudKitAccountAvailability() async {
    await refreshCloudSyncPauseReason()
    guard let cloudSyncController else { return }
    guard cloudSyncMode == .live else {
      cloudKitAccountAvailability = .couldNotDetermine
      return
    }
    cloudKitAccountAvailability = await cloudSyncController.accountAvailability()
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
