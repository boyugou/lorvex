import Foundation
import LorvexCloudSync
import LorvexCore

struct CloudDeletionReenableRequest: Sendable {
  fileprivate let deletionEpoch: UInt64
}

struct CloudSyncResumeRequest: Sendable {
  fileprivate let adoptionRequest: CloudSyncAccountAdoptionRequest
  fileprivate let deletionEpoch: UInt64
}

extension AppStore {
  /// Refresh `cloudSyncPauseReason` from the coordinator's durable pause state
  /// so Settings can show a "sync paused" notice. A no-op when no coordinator
  /// is wired (sync off / previews / tests): the stored value is left as-is so
  /// a reason recorded by `deleteCloudDataEverywhere` — which turns sync off —
  /// is not blanked by an unrelated refresh.
  func refreshCloudSyncPauseReason() async {
    guard let cloudSyncCoordinator else { return }
    cloudSyncPauseReason = await cloudSyncCoordinator.currentPauseReason()
  }

  /// Best-effort continuation of a previously published CloudKit deletion
  /// barrier. It is intentionally available while sync is off: the coordinator
  /// performs only namespace cleanup authorized by the remote `.deleted` state.
  func retryPendingCloudDataDeletionCleanup() async {
    guard !isDataImportRunning, !isLocalFactoryResetRunning,
      !isCloudDataDeletionRunning, !isCloudDeletionMaintenanceRunning,
      let sync = core as? any EnvelopeSyncServicing,
      let coordinator = cloudDataMaintenanceCoordinator
    else { return }
    isCloudDeletionMaintenanceRunning = true
    defer { isCloudDeletionMaintenanceRunning = false }
    _ = try? await Task.detached(priority: .utility) {
      try await coordinator.retryPendingCloudDataDeletionCleanup(sync: sync)
    }.value
  }

  /// Delete every Lorvex record from the signed-in iCloud account — for all
  /// devices that sync with it — leaving the local database untouched, then
  /// turn sync off durably. Sync stays off (and the engine stays paused behind
  /// the `userDeletedZone` re-opt-in gate) until the user explicitly re-enables
  /// it, which re-uploads this Mac's data.
  ///
  /// Returns `nil` on success, or a localized user-facing error message when
  /// the operation could not finish. A failure before the fleet-visible delete
  /// barrier leaves sync unchanged. Once that barrier is durable it cannot be
  /// rolled back: if physical cleanup then fails, sync still turns off and the
  /// returned message asks the user to retry the remaining cleanup. Works with
  /// sync off — the common case is a user who disabled sync and now wants the
  /// cloud copy gone too.
  func deleteCloudDataEverywhere(settings: AppSettingsStore) async -> String? {
    guard !isDataImportRunning, !isLocalFactoryResetRunning else {
      let busyDetail = String(
        localized: "settings.data_import.error.busy",
        defaultValue:
          "Another import or data operation is still running. Wait for it to finish, then try again.",
        table: "Localizable", bundle: LorvexL10n.bundle)
      return String(
        format: String(
          localized: "settings.cloud_delete.error.failed",
          defaultValue:
            "Couldn’t finish deleting iCloud data (%@). Check your connection and try again.",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ),
        busyDetail)
    }
    guard let sync = core as? any EnvelopeSyncServicing else {
      return String(
        format: String(
          localized: "settings.cloud_delete.error.failed",
          defaultValue:
            "Couldn’t finish deleting iCloud data (%@). Check your connection and try again.",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ),
        "Cloud sync storage is unavailable.")
    }
    guard let coordinator = cloudDataMaintenanceCoordinator else {
      return String(
        format: String(
          localized: "settings.cloud_delete.error.failed",
          defaultValue:
            "Couldn’t finish deleting iCloud data (%@). Check your connection and try again.",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ),
        "Cloud sync coordinator is unavailable.")
    }
    guard !isCloudDataDeletionRunning else {
      return String(
        format: String(
          localized: "settings.cloud_delete.error.failed",
          defaultValue:
            "Couldn’t finish deleting iCloud data (%@). Check your connection and try again.",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ),
        "Cloud data deletion is already in progress.")
    }
    cloudDataDeletionEpoch &+= 1
    isCloudDataDeletionRunning = true
    defer { isCloudDataDeletionRunning = false }
    var cleanupFailureMessage: String?
    do {
      try await Task.detached(priority: .userInitiated) {
        try await coordinator.deleteAllCloudData(sync: sync)
      }.value
    } catch let deletionError as CloudSyncCloudDataDeletionError {
      switch deletionError {
      case .accountUnavailable:
        return String(
          localized: "settings.cloud_delete.error.no_account",
          defaultValue: "No usable iCloud account. Sign in to iCloud and try again.",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        )
      case .cleanupIncomplete(let detail):
        cleanupFailureMessage = String(
          format: String(
            localized: "settings.cloud_delete.error.failed",
            defaultValue:
              "Couldn’t finish deleting iCloud data (%@). Check your connection and try again.",
            table: "Localizable",
            bundle: LorvexL10n.bundle
          ),
          detail)
      }
    } catch {
      return String(
        format: String(
          localized: "settings.cloud_delete.error.failed",
          defaultValue:
            "Couldn’t finish deleting iCloud data (%@). Check your connection and try again.",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ),
        error.localizedDescription)
    }
    // The cloud copy is gone; honor "sync stays off until re-enabled" at the
    // app level too. The persisted mode flips to `.off` and the runtime mode
    // halts cycles immediately; the engine-side pause is belt-and-suspenders
    // against any path that re-enables live mode without the explicit
    // re-opt-in below.
    settings.cloudSyncMode = .off
    cloudSyncMode = .off
    cloudSyncPacing.reset()
    cloudSyncPauseReason = .userDeletedZone
    return cleanupFailureMessage
  }

  /// The explicit re-opt-in that follows an iCloud-data deletion: the user
  /// turned the sync mode back to Live in Settings, which is the consent to
  /// re-create the zone and re-upload this Mac's data. Lifts ONLY a
  /// `userDeletedZone` pause — an `accountChanged` pause keeps its own
  /// adopt-account consent flow (`adoptCurrentCloudAccountAndResumeSync`).
  ///
  /// Runs against the on-demand maintenance coordinator when sync is not live
  /// yet (on macOS the Live mode takes effect after relaunch): it clears the
  /// durable pause and enqueues the re-upload backfill now, so the first cycle
  /// after relaunch re-creates the zone and pushes rather than wedging at the
  /// pause gate.
  func makeCloudDeletionReenableRequest() -> CloudDeletionReenableRequest? {
    guard !isCloudDataDeletionRunning else { return nil }
    return CloudDeletionReenableRequest(deletionEpoch: cloudDataDeletionEpoch)
  }

  func liftCloudDeletionPauseForExplicitReenable() async {
    guard let request = makeCloudDeletionReenableRequest() else { return }
    await liftCloudDeletionPauseForExplicitReenable(request: request)
  }

  func liftCloudDeletionPauseForExplicitReenable(
    request: CloudDeletionReenableRequest
  ) async {
    guard let coordinator = cloudDataMaintenanceCoordinator,
      let sync = core as? any EnvelopeSyncServicing
    else { return }
    guard let adoptionRequest = await coordinator
      .makeSameAccountDeletedZoneReenableRequest(sync: sync)
    else {
      cloudSyncPauseReason = await coordinator.currentPauseReason()
      return
    }
    let authorization: @Sendable () async -> Bool = { [weak self] in
      await MainActor.run {
        guard let self else { return false }
        return !self.isCloudDataDeletionRunning
          && self.cloudDataDeletionEpoch == request.deletionEpoch
      }
    }
    _ = await Task.detached(priority: .userInitiated) {
      await coordinator.confirmDeletedZoneReenable(
        sync: sync, request: adoptionRequest, authorization: authorization)
    }.value
    cloudSyncPauseReason = await coordinator.currentPauseReason()
  }

  /// Adopt the currently signed-in iCloud account and resume sync — the action
  /// the "Sync Paused" notice offers. Re-uploads this Mac's data into the
  /// current account's zone (re-creating the Lorvex zone when it was deleted),
  /// records that account as the one this Mac syncs with, and lifts the
  /// durable pause. Mirrors the mobile store's action of the same name. A
  /// no-op when no live coordinator / envelope backend is wired.
  /// Capture consent synchronously before the UI creates an unstructured Task.
  /// A later cloud deletion advances the epoch, making that queued request
  /// incapable of re-enabling the newly-deleted namespace.
  func makeCloudSyncResumeRequest() async -> CloudSyncResumeRequest? {
    guard !isCloudDataDeletionRunning, let pauseReason = cloudSyncPauseReason else {
      return nil
    }
    guard let coordinator = cloudSyncCoordinator ?? cloudDataMaintenanceCoordinator,
      let sync = core as? any EnvelopeSyncServicing,
      let adoptionRequest = await coordinator.makeAccountAdoptionRequest(
        sync: sync, expectedPauseReason: pauseReason),
      !isCloudDataDeletionRunning,
      cloudSyncPauseReason == pauseReason
    else { return nil }
    return CloudSyncResumeRequest(
      adoptionRequest: adoptionRequest, deletionEpoch: cloudDataDeletionEpoch)
  }

  func adoptCurrentCloudAccountAndResumeSync(
    request: CloudSyncResumeRequest
  ) async {
    guard let sync = core as? any EnvelopeSyncServicing else { return }
    if request.adoptionRequest.pauseReason == .userDeletedZone {
      guard let coordinator = cloudDataMaintenanceCoordinator else { return }
      let authorization: @Sendable () async -> Bool = { [weak self] in
        await MainActor.run {
          guard let self else { return false }
          return !self.isCloudDataDeletionRunning
            && self.cloudDataDeletionEpoch == request.deletionEpoch
        }
      }
      _ = await Task.detached(priority: .userInitiated) {
        await coordinator.confirmDeletedZoneReenable(
          sync: sync, request: request.adoptionRequest,
          authorization: authorization)
      }.value
    } else if let coordinator = cloudSyncCoordinator {
      _ = await Task.detached(priority: .userInitiated) {
        await coordinator.confirmBackfillIntoCurrentAccount(
          sync: sync, request: request.adoptionRequest)
      }.value
    }
    await refreshCloudSyncPauseReason()
    cloudSyncPacing.reset()
    await refresh()
  }
}
