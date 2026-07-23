import Foundation
import LorvexCloudSync

extension MobileStore {
  public var mobileCloudSyncStatusReport: CloudSyncStatusReport {
    let cycleAt = lastCloudSyncCycleReport == nil ? nil : lastCloudSyncRemoteChangeSucceededAt
    return CloudSyncStatusReport(
      mode: cloudSyncMode,
      accountAvailability: cloudKitAccountAvailability,
      pauseReason: cloudSyncPauseReason,
      lastPushAt: cycleAt,
      lastPushError: lastCloudSyncSubscriptionErrorMessage,
      lastPullAt: lastCloudSyncRemoteChangeSucceededAt,
      lastPullError: lastCloudSyncRemoteChangeErrorMessage,
      pendingCount: runtimeDiagnostics?.sync.pendingCount ?? 0
    )
  }

  /// User-facing Cloud Sync backend label derived from the effective
  /// ``cloudSyncMode``: `.off` reads "disabled"; `.recordPlan` and `.live` both
  /// read "CloudKit" (CloudKit is the transport whenever sync is engaged).
  /// Settings → Cloud Sync and Settings → Diagnostics both read this so they
  /// reflect the live mode rather than the core's static `backend` placeholder.
  public var cloudSyncBackendLabel: String {
    switch cloudSyncMode {
    case .off:
      return String(
        localized: "settings.sync.backend.disabled", defaultValue: "disabled", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .recordPlan:
      return String(
        localized: "settings.sync.backend.record_plan", defaultValue: "CloudKit",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .live:
      return String(
        localized: "settings.sync.backend.cloudkit", defaultValue: "CloudKit", table: "Localizable",
        bundle: MobileL10n.bundle)
    }
  }

  public func refreshCloudKitAccountAvailability() async {
    guard let checker = cloudSyncCoordinator?.accountChecker else {
      cloudKitAccountAvailability = cloudSyncMode == .live ? .couldNotDetermine : .available
      return
    }
    cloudKitAccountAvailability = (try? await checker.checkAccountStatus()) ?? .couldNotDetermine
  }
}
