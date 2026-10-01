import Foundation
import LorvexCloudSync
import LorvexCore

extension MobileStore {
  /// Delete every Lorvex record from the signed-in iCloud account — for all
  /// devices that sync with it — leaving the local database untouched, then
  /// turn sync off durably. Sync stays off (and the controller stays paused
  /// behind the `userDeletedZone` re-opt-in gate) until the user explicitly
  /// turns it back on, which re-uploads this device's data.
  ///
  /// Returns `nil` on success, or a localized user-facing error message when
  /// the deletion did not finish, in which case sync is left unchanged. Works
  /// with sync off — the common case is a user who disabled sync and now wants
  /// the cloud copy gone too.
  public func deleteCloudDataEverywhere() async -> String? {
    guard !isSettingCloudSyncMode, !isDataImportRunning, !isCloudDataDeletionRunning,
      !isLocalDataResetRunning
    else {
      return String(
        localized: "settings.sync.delete_cloud.error.busy",
        defaultValue: "Cloud Sync is updating. Try again in a moment.", table: "Localizable",
        bundle: MobileL10n.bundle)
    }
    guard let cloudSyncController else {
      return String(
        localized: "settings.sync.delete_cloud.error.unavailable",
        defaultValue: "iCloud sync isn’t available in this build.", table: "Localizable",
        bundle: MobileL10n.bundle)
    }
    isCloudDataDeletionRunning = true
    defer { isCloudDataDeletionRunning = false }
    // Invalidate every mode request captured before the deletion started, so
    // a delayed "turn sync on" cannot re-upload what is being deleted.
    cloudDataDeletionEpoch &+= 1
    guard await cloudSyncController.accountAvailability() == .available else {
      return String(
        localized: "settings.sync.delete_cloud.error.no_account",
        defaultValue: "No usable iCloud account. Sign in to iCloud and try again.",
        table: "Localizable", bundle: MobileL10n.bundle)
    }
    do {
      try await cloudSyncController.deleteAllCloudData()
    } catch {
      return String(
        format: String(
          localized: "settings.sync.delete_cloud.error.failed",
          defaultValue:
            "Couldn’t finish deleting iCloud data (%@). Check your connection and try again.",
          table: "Localizable", bundle: MobileL10n.bundle),
        error.localizedDescription)
    }
    MobileSetupPreferences(defaults: defaults).setCloudSyncMode(.off)
    cloudSyncMode = .off
    cloudSyncPauseReason = .userDeletedZone
    await loadRuntimeDiagnostics()
    return nil
  }
}
