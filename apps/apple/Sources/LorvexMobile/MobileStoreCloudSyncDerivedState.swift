import Foundation
import LorvexCloudSync

/// What Settings → Cloud Sync tells the user about their data, in place of the
/// outbox row depth.
///
/// A row count is the wrong unit for that surface: one user edit stages two
/// `sync_outbox` rows — the entity write plus its mandatory `ai_changelog`
/// envelope — so "2" after creating a single task reads as a wrong number of
/// changes. The depth stays in Settings → Diagnostics, where rows are the unit;
/// here the user gets the state that depth implies.
public enum MobileCloudSyncActivityState: Equatable, Sendable {
  /// The user's chosen mode is Off, so no upload will happen and the mode
  /// footer already says what that means. Surfaces show no activity line.
  case disabled
  /// No queue state has been read yet this session.
  case checking
  /// Nothing is queued: every local change has reached iCloud.
  case upToDate
  /// Local changes are queued and the next cycle will upload them.
  case syncing
  /// Local changes are queued but nothing can upload them right now — sync is
  /// durably paused, or the iCloud account is unavailable.
  case waiting
}

extension MobileStore {
  public var mobileCloudSyncStatusReport: CloudSyncStatusReport {
    let cycleAt = lastCloudSyncCycleReport == nil ? nil : lastCloudSyncRemoteChangeSucceededAt
    return CloudSyncStatusReport(
      mode: cloudSyncMode,
      accountAvailability: cloudKitAccountAvailability,
      pauseReason: cloudSyncPauseReason,
      lastPushAt: cycleAt,
      lastPushError: nil,
      lastPullAt: lastCloudSyncRemoteChangeSucceededAt,
      lastPullError: lastCloudSyncRemoteChangeErrorMessage,
      pendingCount: syncPendingRowCount
    )
  }

  /// Number of `sync_outbox` rows waiting to upload, as of the last
  /// ``refreshSyncStatus()`` / ``loadRuntimeDiagnostics()``; `0` before the
  /// first read lands. This is a queue depth, not a count of user edits — one
  /// edit stages the entity row plus its `ai_changelog` envelope — so it is
  /// presented only where rows are the unit (Settings → Diagnostics).
  public var syncPendingRowCount: Int { syncStatus?.pendingCount ?? 0 }

  /// The subset of ``syncPendingRowCount`` that has already failed at least one
  /// upload attempt.
  ///
  /// Shown beside the pending depth in Settings → Diagnostics because the two
  /// numbers separate the only two ways a queue stays full, and nothing else on
  /// the device does: rows that have been attempted and rejected mean the push
  /// is reaching CloudKit and failing, while a backlog that has never been
  /// attempted means no cycle is running at all.
  public var syncRetryingRowCount: Int { syncStatus?.retryingCount ?? 0 }

  /// Cloud Sync state for the Settings activity line, derived from the queued
  /// row depth and whether anything can currently drain it.
  public var cloudSyncActivityState: MobileCloudSyncActivityState {
    guard cloudSyncMode == .live else { return .disabled }
    guard let pendingCount = syncStatus?.pendingCount else { return .checking }
    guard pendingCount > 0 else { return .upToDate }
    guard cloudSyncPauseReason == nil, cloudKitAccountAvailability == .available else {
      return .waiting
    }
    return .syncing
  }

  /// User-facing Cloud Sync backend label derived from the effective
  /// ``cloudSyncMode``: `.off` reads "Off", the word the sync mode picker uses,
  /// and `.live` reads "CloudKit".
  ///
  /// Settings → Diagnostics reads this so its Sync row reflects the live mode
  /// rather than the core's static `backend` placeholder.
  public var cloudSyncBackendLabel: String {
    switch cloudSyncMode {
    case .off:
      return String(
        localized: "settings.sync.backend.disabled", defaultValue: "Off", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .live:
      return String(
        localized: "settings.sync.backend.cloudkit", defaultValue: "CloudKit", table: "Localizable",
        bundle: MobileL10n.bundle)
    }
  }

  /// Queries the iCloud account for the Settings Account row. Only runs while
  /// sync is Live: with sync off Lorvex does not contact iCloud at all, and the
  /// row is hidden, so the value stays `.couldNotDetermine` until the first
  /// controller evaluation after sync is turned on.
  public func refreshCloudKitAccountAvailability() async {
    guard cloudSyncMode == .live, let cloudSyncController else {
      cloudKitAccountAvailability = .couldNotDetermine
      return
    }
    cloudKitAccountAvailability = await cloudSyncController.accountAvailability()
  }
}
