import Foundation
import LorvexCloudSync
import LorvexCore

struct CloudDeletionReenableRequest: Sendable {
  fileprivate let deletionEpoch: UInt64
}

struct CloudSyncResumeRequest: Sendable {
  fileprivate let pauseReason: CloudSyncPauseReason
  fileprivate let deletionEpoch: UInt64
}

extension AppStore {
  /// Refresh `cloudSyncPauseReason` from the controller's durable pause state
  /// so Settings can show a "sync paused" notice. A no-op without a controller
  /// (previews and tests).
  func refreshCloudSyncPauseReason() async {
    guard let cloudSyncController else { return }
    cloudSyncPauseReason = await cloudSyncController.currentPauseReason()
  }

  /// Delete every Lorvex record from the signed-in iCloud account — for all
  /// devices that sync with it — leaving the local database untouched, then
  /// turn sync off durably. Sync stays off (and the engine stays paused behind
  /// the `userDeletedZone` re-opt-in gate) until the user explicitly re-enables
  /// it, which re-uploads this Mac's data.
  ///
  /// Returns `nil` on success, or a localized user-facing error message when
  /// the deletion could not finish, in which case sync is left unchanged.
  /// Works with sync off — the common case is a user who disabled sync and
  /// now wants the cloud copy gone too.
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
    guard let controller = cloudSyncController else {
      return String(
        format: String(
          localized: "settings.cloud_delete.error.failed",
          defaultValue:
            "Couldn’t finish deleting iCloud data (%@). Check your connection and try again.",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ),
        "Cloud sync is unavailable.")
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
    guard await controller.accountAvailability() == .available else {
      return String(
        localized: "settings.cloud_delete.error.no_account",
        defaultValue: "No usable iCloud account. Sign in to iCloud and try again.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    }
    do {
      try await controller.deleteAllCloudData()
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
    // The cloud copy is gone; sync stays off until the user turns it back on,
    // which re-uploads this Mac's data into a new zone.
    settings.cloudSyncMode = .off
    cloudSyncMode = .off
    cloudSyncPauseReason = .userDeletedZone
    return nil
  }

  /// The explicit re-opt-in that follows an iCloud-data deletion: turning sync
  /// back on is the consent to create a new zone and upload this Mac's data.
  /// The request is captured when the choice is made; a deletion accepted
  /// after it supersedes it.
  func makeCloudDeletionReenableRequest() -> CloudDeletionReenableRequest? {
    guard !isCloudDataDeletionRunning else { return nil }
    return CloudDeletionReenableRequest(deletionEpoch: cloudDataDeletionEpoch)
  }

  /// Whether `request` still stands: no cloud-data deletion is running, and
  /// none was accepted after the request was made.
  func isCurrent(_ request: CloudDeletionReenableRequest) -> Bool {
    !isCloudDataDeletionRunning && cloudDataDeletionEpoch == request.deletionEpoch
  }

  /// Lifts a `userDeletedZone` pause for an explicit re-enable. An
  /// `accountChanged` pause keeps its own consent flow
  /// (``adoptCurrentCloudAccountAndResumeSync(request:)``).
  func liftCloudDeletionPauseForExplicitReenable(
    request: CloudDeletionReenableRequest
  ) async {
    guard let controller = cloudSyncController, isCurrent(request),
      await controller.currentPauseReason() == .userDeletedZone
    else { return }
    await applyCloudSyncControllerState(
      (try? await controller.reenableAfterCloudDeletion()) ?? .failed("reenable failed"))
  }

  /// Adopt the currently signed-in iCloud account and resume sync — the action
  /// the "Sync Paused" notice offers. After an account change this uploads
  /// this Mac's data into the current account and merges it with what is
  /// there; after a cloud-data deletion it uploads into a new zone. Consent is
  /// captured synchronously before the UI creates an unstructured Task, so a
  /// cloud deletion accepted afterwards makes the request void.
  func makeCloudSyncResumeRequest() async -> CloudSyncResumeRequest? {
    guard !isCloudDataDeletionRunning, let pauseReason = cloudSyncPauseReason,
      cloudSyncController != nil
    else { return nil }
    return CloudSyncResumeRequest(pauseReason: pauseReason, deletionEpoch: cloudDataDeletionEpoch)
  }

  func adoptCurrentCloudAccountAndResumeSync(
    request: CloudSyncResumeRequest
  ) async {
    guard let controller = cloudSyncController, !isCloudDataDeletionRunning,
      cloudDataDeletionEpoch == request.deletionEpoch,
      await controller.currentPauseReason() == request.pauseReason
    else { return }
    let state: CloudSyncControllerState
    switch request.pauseReason {
    case .userDeletedZone:
      state = (try? await controller.reenableAfterCloudDeletion()) ?? .failed("reenable failed")
    case .accountChanged:
      state = (try? await controller.adoptCurrentAccount()) ?? .failed("adoption failed")
    }
    await applyCloudSyncControllerState(state)
    await refresh()
  }
}
